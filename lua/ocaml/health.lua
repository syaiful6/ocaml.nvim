---@mod ocaml.health
---
---@brief [[
---`:checkhealth ocaml`: Neovim version, configuration, executables, the
---sandbox of the most recently used OCaml buffer, and optional integrations.
---@brief ]]

local M = {}

local h = vim.health

---How long to wait for a `--version` call, in milliseconds.
M.VERSION_TIMEOUT = 5000

---How long to wait for sandbox detection, in milliseconds.
M.SANDBOX_TIMEOUT = 10000

---Filetypes handled by ocaml.nvim.
local FILETYPES = {
  "ocaml",
  "ocaml.interface",
  "ocaml.menhir",
  "ocaml.ocamllex",
  "ocaml.mlx",
  "ocaml.cram",
  "reason",
  "reason.interface",
  "dune",
  "dune-project",
  "dune-workspace",
}

---Treesitter parsers ocaml.nvim registers besides the core OCaml ones.
local EXTRA_PARSERS = { "reason", "ocaml_mlx", "dune", "menhir", "ocamllex" }

---First line of `{binary} --version`, or nil and an error.
---@param binary string
---@return string|nil version
---@return string|nil err
function M.version(binary)
  local ok, proc = pcall(vim.system, { binary, "--version" }, { text = true })
  if not ok then
    return nil, tostring(proc)
  end
  local result = proc:wait(M.VERSION_TIMEOUT)
  if result.code ~= 0 then
    local stderr = vim.trim(result.stderr or "")
    return nil, ("exit code %d%s"):format(result.code, stderr ~= "" and ": " .. stderr or "")
  end
  return vim.trim(vim.split(result.stdout or "", "\n", { trimempty = true })[1] or "")
end

---@param cmd string[]
---@return string
local function format_cmd(cmd)
  return require("ocaml.commands.sandbox").format_cmd(cmd)
end

---`vim.health.info` takes no advice; append it to the message instead.
---@param msg string
---@param advice? string[]
local function info(msg, advice)
  h.info(advice and #advice > 0 and msg .. " " .. table.concat(advice, ". ") or msg)
end

---The most recently used loaded buffer with an OCaml filetype.
---`:checkhealth` opens its own buffer, so the current one is never it.
---@return integer|nil
function M.find_buffer()
  local best, best_used
  for _, buf in ipairs(vim.fn.getbufinfo({ bufloaded = 1 })) do
    local ft = vim.bo[buf.bufnr].filetype
    if buf.name ~= "" and vim.tbl_contains(FILETYPES, ft) and (not best_used or buf.lastused > best_used) then
      best, best_used = buf.bufnr, buf.lastused
    end
  end
  return best
end

local function check_neovim()
  h.start("Neovim")
  local v = vim.version()
  local version = ("%d.%d.%d"):format(v.major, v.minor, v.patch)
  if vim.fn.has("nvim-0.11") == 1 then
    h.ok("Neovim " .. version)
  else
    h.error("Neovim " .. version .. " is too old", { "ocaml.nvim requires Neovim 0.11 or later" })
  end
end

local function check_config()
  h.start("Configuration")
  local user = vim.g.ocamlnvim
  if user ~= nil and type(user) ~= "table" and type(user) ~= "function" then
    h.error(("vim.g.ocamlnvim is a %s"):format(type(user)), { "Set it to a table, or a function returning one" })
  end

  local err = require("ocaml.config.status").sandbox_error
  if err then
    h.error("Invalid sandbox options; the defaults are used instead: " .. err)
  end

  local Sandbox = require("ocaml.sandbox")
  h.ok("Sandbox providers, in priority order: " .. table.concat(Sandbox.priority(), " > "))
  if Sandbox.config().resolve then
    h.info("A sandbox.resolve hook picks the sandbox when it returns one")
  end
end

---@param name string Display name
---@param binary string
---@param missing fun(msg: string, advice: string[]?) How to report a missing binary
---@param missing_msg string
---@param advice? string[]
local function check_executable(name, binary, missing, missing_msg, advice)
  local path = vim.fn.exepath(binary)
  if path == "" then
    return missing(("%s: `%s` not found. %s"):format(name, binary, missing_msg), advice)
  end
  local version, err = M.version(path)
  if version then
    h.ok(("%s: %s (%s)"):format(name, version, path))
  else
    h.warn(("%s: found at %s, but `%s --version` failed: %s"):format(name, path, binary, err))
  end
end

local function check_executables()
  h.start("Executables")
  local Sandbox = require("ocaml.sandbox")
  local config = Sandbox.config()
  local enabled = Sandbox.priority()

  for _, provider in ipairs({ "opam", "esy" }) do
    if vim.tbl_contains(enabled, provider) then
      check_executable(
        provider,
        config[provider].binary,
        info,
        ("%s sandboxes will not be detected."):format(provider),
        { ("Install %s, or set sandbox.%s.binary"):format(provider, provider) }
      )
    else
      h.info(("%s: provider disabled in sandbox.providers"):format(provider))
    end
  end

  check_executable("dune", "dune", info, "Fine when your sandbox provides it.")
  check_executable(
    "ocamllsp",
    "ocamllsp",
    info,
    "Only needed for projects without a sandbox.",
    { "Install it with `opam install ocaml-lsp-server`, or your system package manager" }
  )
end

---Advice for installing a tool in a sandbox.
---@param sandbox ocaml.sandbox.Sandbox
---@param package string opam package name
---@return string[]
local function install_advice(sandbox, package)
  if sandbox.provider == "opam" then
    return { ("Run `opam install %s --switch=%s`"):format(package, sandbox.data.switch) }
  elseif sandbox.provider == "esy" then
    return { ("Add `%s` to the esy manifest's devDependencies and run `esy install`"):format(package) }
  end
  return { ("Install %s with opam or your system package manager"):format(package) }
end

---Report whether `tool` can run in `sandbox`.
---@param sandbox ocaml.sandbox.Sandbox
---@param tool string
---@param package string opam package providing it
---@param missing fun(msg: string, advice: string[]?)
local function check_tool(sandbox, tool, package, missing)
  local cmd = require("ocaml.sandbox").get_tool_command(sandbox, tool)
  if not cmd then
    return missing(("%s is not installed in %s"):format(tool, sandbox.label), install_advice(sandbox, package))
  end
  if vim.fn.executable(cmd[1]) == 0 then
    return missing(("%s: `%s` is not executable"):format(tool, cmd[1]), install_advice(sandbox, package))
  end
  local path = vim.fn.exepath(cmd[1])
  local resolved = (path ~= "" and path ~= cmd[1]) and (" (%s)"):format(path) or ""
  h.ok(("%s: %s%s"):format(tool, format_cmd(cmd), resolved))
end

local function check_sandbox()
  h.start("Sandbox")
  local bufnr = M.find_buffer()
  if not bufnr then
    return h.info("No OCaml buffer is open. Open one and run :checkhealth ocaml again to check its sandbox.")
  end

  local Sandbox = require("ocaml.sandbox")
  local Info = require("ocaml.commands.sandbox")
  local root = Sandbox.buffer_root(bufnr)
  h.info(("Buffer: %s"):format(vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":~:.")))
  h.info(("Project root: %s"):format(vim.fn.fnamemodify(root, ":~")))

  ---@type ocaml.commands.sandbox.Report|nil
  local report
  Info.collect(root, function(r)
    report = r
  end)
  if not report and not vim.wait(M.SANDBOX_TIMEOUT, function()
    return report ~= nil
  end, 10) then
    return h.error(("Sandbox detection did not finish within %d ms"):format(M.SANDBOX_TIMEOUT))
  end
  ---@cast report ocaml.commands.sandbox.Report

  local active = report.active
  h.ok(("Active sandbox: %s (%s)"):format(active.label, active.id))
  for _, line in ipairs(Info.explain(report)) do
    h.info("Why: " .. line)
  end
  local others = #report.candidates - 1
  if others > 0 then
    h.info(("%d other candidate(s); see :OCaml sandbox info"):format(others))
  end

  check_tool(active, "ocamllsp", "ocaml-lsp-server", h.error)

  local has_ocamlformat_config = vim.fn.filereadable(vim.fs.joinpath(root, ".ocamlformat")) == 1
  check_tool(active, "ocamlformat", "ocamlformat", has_ocamlformat_config and h.warn or info)

  if report.lsp_client_id and report.lsp_cmd then
    h.ok(("ocamllsp is running (client %d): %s"):format(report.lsp_client_id, format_cmd(report.lsp_cmd)))
  elseif report.lsp_cmd then
    h.warn(("ocamllsp is not running for this project. It would run: %s"):format(format_cmd(report.lsp_cmd)), {
      "Start it with :OCaml lsp start",
      "If it exits right away, check :LspLog",
    })
  else
    h.error("Cannot build the ocamllsp command: " .. (report.lsp_err or "unknown error"))
  end
end

local function check_integrations()
  h.start("Integrations")

  local missing_core = {}
  for _, lang in ipairs({ "ocaml", "ocaml_interface" }) do
    local ok, added = pcall(vim.treesitter.language.add, lang)
    if not ok or not added then
      table.insert(missing_core, lang)
    end
  end
  if #missing_core == 0 then
    h.ok("Treesitter parsers: ocaml, ocaml_interface")
  else
    h.warn("Missing treesitter parsers: " .. table.concat(missing_core, ", "), {
      "Install them with nvim-treesitter: :TSInstall " .. table.concat(missing_core, " "),
    })
  end

  if not pcall(require, "nvim-treesitter") then
    h.warn("nvim-treesitter is not installed", {
      ("ocaml.nvim registers extra parsers (%s) through it"):format(table.concat(EXTRA_PARSERS, ", ")),
    })
  else
    local missing_extra = {}
    for _, lang in ipairs(EXTRA_PARSERS) do
      local ok, added = pcall(vim.treesitter.language.add, lang)
      if not ok or not added then
        table.insert(missing_extra, lang)
      end
    end
    if #missing_extra == 0 then
      h.ok("Extra treesitter parsers: " .. table.concat(EXTRA_PARSERS, ", "))
    else
      info("Extra treesitter parsers not installed: " .. table.concat(missing_extra, ", "), {
        "Install the ones you need with :TSInstall",
      })
    end
  end

  if pcall(require, "conform") then
    h.ok("conform.nvim: ocamlformat and ocamlformat_mlx run in the project's sandbox")
  else
    h.info("conform.nvim is not installed; formatting through the sandbox is not set up")
  end
end

function M.check()
  check_neovim()
  check_config()
  check_executables()
  check_sandbox()
  check_integrations()
end

return M
