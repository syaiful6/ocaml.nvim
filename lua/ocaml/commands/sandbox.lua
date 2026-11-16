---@mod ocaml.commands.sandbox
---
---@brief [[
---WARNING: This is not part of the public API. It may change without warning.
---Use at your own risk.
---
---Implementation of `:OCaml sandbox info`.
---@brief ]]

local M = {}

---@class ocaml.commands.sandbox.Report
---@field root string Project root
---@field active ocaml.sandbox.Sandbox The sandbox in use
---@field chosen_by ocaml.sandbox.ChosenBy|nil
---@field has_hook boolean Whether a `sandbox.resolve` hook is configured
---@field priority string[] Enabled providers, in priority order
---@field candidates ocaml.sandbox.Sandbox[] Every candidate, in priority order
---Command of the running client, or the one that would be started.
---@field lsp_cmd string[]|nil
---@field lsp_err string|nil Why no LSP command could be built
---@field lsp_client_id integer|nil Running ocamllsp client for the root

---A line is a list of `{ text, hl_group }` chunks.
---@alias ocaml.commands.sandbox.Line [string, string?][]

---@param cmd string[]
---@return string
function M.format_cmd(cmd)
  return table.concat(
    vim.tbl_map(function(arg)
      return arg:find("[%s'\"]") and vim.fn.shellescape(arg) or arg
    end, cmd),
    " "
  )
end

---Running ocamllsp client for a project root, if any.
---@param root string
---@return vim.lsp.Client|nil
local function running_client(root)
  for _, client in ipairs(require("ocaml.lsp.helpers").get_active_lsp_clients()) do
    if not client:is_stopped() and vim.fs.normalize(client.config.root_dir or "") == root then
      return client
    end
  end
end

---Gather what `:OCaml sandbox info` shows for a project root.
---Runs detection for every provider, so it may finish asynchronously.
---@param root string
---@param cb fun(report: ocaml.commands.sandbox.Report)
function M.collect(root, cb)
  local Sandbox = require("ocaml.sandbox")
  Sandbox.resolve(root, function(active)
    Sandbox.list(root, function(candidates)
      ---@type ocaml.commands.sandbox.Report
      local report = {
        root = root,
        active = active,
        chosen_by = Sandbox.get_chosen_by(root),
        has_hook = Sandbox.config().resolve ~= nil,
        priority = Sandbox.priority(),
        candidates = candidates,
      }
      local client = running_client(root)
      if client and type(client.config.cmd) == "table" then
        report.lsp_cmd = client.config.cmd --[[@as string[] ]]
        report.lsp_client_id = client.id
      else
        report.lsp_cmd, report.lsp_err = Sandbox.get_lsp_command(active, {})
        report.lsp_client_id = client and client.id
      end
      cb(report)
    end)
  end)
end

---Explain why `report.active` was chosen.
---@param report ocaml.commands.sandbox.Report
---@return string[] lines
function M.explain(report)
  local active = report.active
  if report.chosen_by == "hook" then
    return { "chosen by your sandbox.resolve hook" }
  end

  local lines = {
    ("selected the first automatic candidate in provider order: %s"):format(table.concat(report.priority, " > ")),
  }
  if report.has_hook then
    lines[1] = lines[1] .. "; sandbox.resolve did not override it"
  end
  if report.chosen_by == nil then
    lines[1] = lines[1] .. " (detection was invalidated; the result may be out of date)"
  end

  ---@type table<string, ocaml.sandbox.Sandbox[]>
  local by_provider = {}
  for _, candidate in ipairs(report.candidates) do
    by_provider[candidate.provider] = by_provider[candidate.provider] or {}
    table.insert(by_provider[candidate.provider], candidate)
  end

  for _, name in ipairs(report.priority) do
    if name == active.provider then
      break
    end
    local found = by_provider[name] or {}
    if #found == 0 then
      table.insert(lines, ("%s: nothing found"):format(name))
    else
      local notes = {}
      for _, candidate in ipairs(found) do
        if candidate.note then
          table.insert(notes, ("%s (%s)"):format(candidate.id, candidate.note))
        end
      end
      table.insert(
        lines,
        ("%s: found %d, but none was eligible for automatic selection%s"):format(
          name,
          #found,
          #notes > 0 and ": " .. table.concat(notes, "; ") or ""
        )
      )
    end
  end

  if active.note then
    table.insert(lines, ("%s: %s"):format(active.provider, active.note))
  end
  return lines
end

---Render a report as highlighted lines.
---@param report ocaml.commands.sandbox.Report
---@return ocaml.commands.sandbox.Line[]
function M.format(report)
  local active = report.active
  ---@type ocaml.commands.sandbox.Line[]
  local lines = {}
  local function add(...)
    table.insert(lines, { ... })
  end
  local function field(name, value, hl)
    add({ ("  %-9s "):format(name), "Comment" }, { value, hl })
  end

  add({ "OCaml sandbox for " .. vim.fn.fnamemodify(report.root, ":~"), "Title" })
  field("active", active.label, "Identifier")
  field("id", active.id)
  field("provider", active.provider)

  for i, reason in ipairs(M.explain(report)) do
    if i == 1 then
      field("why", reason)
    else
      add({ ("  %-9s   "):format(""), "Comment" }, { reason })
    end
  end

  if report.lsp_cmd then
    local status = report.lsp_client_id and (" (running, client %d)"):format(report.lsp_client_id) or " (not running)"
    add({ ("  %-9s "):format("lsp"), "Comment" }, { M.format_cmd(report.lsp_cmd) }, { status, "Comment" })
  else
    field("lsp", report.lsp_err or "no command", "ErrorMsg")
  end

  local listed = false
  for _, candidate in ipairs(report.candidates) do
    listed = listed or candidate.id == active.id
  end
  if not listed then
    add({
      "  The active sandbox is no longer detected; run :OCaml sandbox refresh",
      "WarningMsg",
    })
  end

  add({ "" })
  add({ "Candidates", "Title" })
  local width = 0
  for _, candidate in ipairs(report.candidates) do
    width = math.max(width, vim.fn.strdisplaywidth(candidate.id))
  end
  for _, candidate in ipairs(report.candidates) do
    local is_active = candidate.id == active.id
    local id = candidate.id .. string.rep(" ", width - vim.fn.strdisplaywidth(candidate.id))
    local extra = {}
    if candidate.auto == false then
      table.insert(extra, "manual")
    end
    if candidate.note then
      table.insert(extra, candidate.note)
    end
    add(
      { is_active and "  ● " or "    ", "DiagnosticOk" },
      { id, is_active and "Identifier" or "Normal" },
      { "  " .. candidate.label },
      { #extra > 0 and "  " .. table.concat(extra, "; ") or "", "Comment" }
    )
  end
  return lines
end

---Plain text of formatted lines.
---@param lines ocaml.commands.sandbox.Line[]
---@return string[]
function M.to_text(lines)
  return vim.tbl_map(function(line)
    return table.concat(vim.tbl_map(function(chunk)
      return chunk[1]
    end, line))
  end, lines)
end

---Show the sandbox report for a buffer's project.
---@param bufnr? integer Default: the current buffer.
function M.info(bufnr)
  local root = require("ocaml.sandbox").buffer_root(bufnr)
  M.collect(root, function(report)
    -- Detection callbacks may run outside the main loop.
    vim.schedule(function()
      local chunks = {}
      for i, line in ipairs(M.format(report)) do
        if i > 1 then
          table.insert(chunks, { "\n" })
        end
        vim.list_extend(chunks, line)
      end
      vim.api.nvim_echo(chunks, true, {})
    end)
  end)
end

return M
