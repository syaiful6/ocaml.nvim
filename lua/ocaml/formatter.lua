---@mod ocaml.formatter conform.nvim integration
---
---@brief [[
---Internal module. Its API may change without notice.
---
---Runs conform.nvim's `ocamlformat` and `ocamlformat_mlx` through the project
---sandbox. This uses the version installed in the project's opam switch, esy
---environment or dune dev tools, falling back to PATH when the sandbox does
---not provide it.
---
---ocaml.nvim only selects the command; other conform settings remain intact.
---Set `command` to a different executable, or set `format`, to disable sandbox
---selection for that formatter.
---@brief ]]

local M = {}

---conform formatter name → executable name.
M.tools = {
  ocamlformat = "ocamlformat",
  ocamlformat_mlx = "ocamlformat-mlx",
}

---Default definition of formatters conform does not ship.
---@type table<string, table>
M.defaults = {
  ocamlformat_mlx = {
    inherit = false,
    command = "ocamlformat-mlx",
    args = { "--name", "$FILENAME", "--impl", "-" },
    stdin = true,
  },
}

---Build the command for `tool`, using the project's sandbox when available.
---@param bufnr integer
---@param tool string
---@return string[]
function M.tool_command(bufnr, tool)
  local Sandbox = require("ocaml.sandbox")
  local sandbox = Sandbox.resolve_sync(Sandbox.buffer_root(bufnr))
  local cmd = sandbox and Sandbox.get_tool_command(sandbox, tool)
  if sandbox and not cmd then
    -- Use PATH for this run. The sandbox may install the tool for later runs.
    Sandbox.ensure_tool(sandbox, tool, function() end)
  end
  return cmd or { tool }
end

---Prepend arguments to conform args, preserving their original form.
---@param extra string[]
---@param args nil|string|string[]|function
---@return string|string[]|function
local function prepend(extra, args)
  if args == nil then
    return extra
  elseif type(args) == "function" then
    return function(...)
      return prepend(extra, args(...))
    end
  elseif type(args) == "string" then
    return table.concat(vim.tbl_map(vim.fn.shellescape, extra), " ") .. " " .. args
  end
  local ret = vim.deepcopy(extra)
  return vim.list_extend(ret, args)
end

---Apply the buffer's sandbox command to a formatter override.
---@param tool string
---@param override table|nil The user's override, if any
---@param bufnr integer
---@return table|nil
function M.sandboxed(tool, override, bufnr)
  if override and (override.format or (override.command ~= nil and override.command ~= tool)) then
    -- The user picked their own command.
    return override
  end

  local result = vim.deepcopy(override or {})
  local cmd = M.tool_command(bufnr, tool)
  result.command = cmd[1]
  local extra = vim.list_slice(cmd, 2)
  if #extra == 0 then
    return result
  end

  if result.inherit == false then
    -- Conform ignores prepend_args for complete definitions.
    result.args = prepend(extra, result.args)
    if result.range_args then
      result.range_args = prepend(extra, result.range_args)
    end
  else
    -- Conform prepends these to the built-in args and range_args.
    result.prepend_args = prepend(extra, result.prepend_args)
  end
  return result
end

---Register sandbox-aware formatters with conform.
---@param conform table The conform module
function M.setup(conform)
  for name, tool in pairs(M.tools) do
    local user = conform.formatters[name] or M.defaults[name]
    conform.formatters[name] = function(bufnr)
      local override = user
      if type(override) == "function" then
        override = override(bufnr)
      end
      return M.sandboxed(tool, override, bufnr)
    end
  end
end

return M
