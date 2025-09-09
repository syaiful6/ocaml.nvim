---@mod ocaml.sandbox.esy Esy sandbox operations
---
---@brief [[
---
---WARNING: This is not part of the public API. It may change without warning.
---Use at your own risk.
---
---@brief ]]

local Helpers = require("ocaml.helpers")

---@class ocaml.sandbox.Esy
local M = {}

--- Get the project manifest file (package.json or esy.json) in the given path.
--- @param path string The path to search in
--- @return string|nil The path to the manifest file, or nil if not found
function M.get_project_manifest(path)
  local match = Helpers.root_pattern("esy.json", "package.json")
  local dir = match(path)
  if not dir then
    return nil
  end

  dir = Helpers.escape_glob_wildcards(dir)
  for _, pattern in ipairs(vim.fn.glob(vim.fs.joinpath(dir, "{esy.json,package.json}"), true, true)) do
    if vim.fn.filereadable(pattern) == 1 then
      return pattern
    end
  end
end

-- Get the esy command to run in the sandbox
-- @param manifest string The path to the manifest file
-- @param args string[] Additional arguments to pass to esy
-- @return string[]|nil The esy command, or nil if the manifest file is not readable
function M.get_command(manifest, args)
  if not manifest or vim.fn.filereadable(manifest) == 0 then
    return nil
  end
  local cmd = { "esy", "-P", manifest }
  for _, arg in ipairs(args or {}) do
    table.insert(cmd, arg)
  end
  return cmd
end

return M
