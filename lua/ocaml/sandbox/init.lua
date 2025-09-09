---@mod ocaml.sandbox
---
---@brief [[
---WARNING: This is not part of the public API. It may change without warning.
---Use at your own risk.

---@brief ]]

---@class ocaml.Sandbox
local M = {}
local Esy = require("ocaml.sandbox.esy")

-- Detect if the given directory is an esy sandbox.
-- @param dir string The directory to check
-- @return boolean True if the directory is an esy sandbox, false otherwise
local function is_esy_sandbox(dir)
  local manifest = Esy.get_project_manifest(dir)
  if not manifest then
    return false
  end
  -- if there's a manifest, check if it has an "esy" field
  local has_esy_field = false
  local ok, content = pcall(vim.fn.readfile, manifest)
  if not ok or not content then
    return false
  end
  local ok_json, json = pcall(vim.fn.json_decode, content)
  if ok_json and json and type(json) == "table" then
    has_esy_field = json["esy"] ~= nil
  end
  return manifest and has_esy_field
end

-- Get the lsp command for the given directory.
-- If the directory is an esy sandbox, return the esy command.
-- Otherwise, return the default command.
-- @param dir string The directory to check
-- @param args string[] Additional arguments to pass to the lsp command
-- @return string[] The lsp command
function M.get_lsp_command(dir, args)
  local cmd = { "ocamllsp" }
  -- insert additional args
  vim.list_extend(cmd, args or {})
  if is_esy_sandbox(dir) then
    return Esy.get_command(Esy.get_project_manifest(dir), cmd)
  end
  -- not a sandbox, return the command as is
  return cmd
end

return M
