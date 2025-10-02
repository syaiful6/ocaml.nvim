---@mod ocaml.sandbox
---
---@brief [[
---WARNING: This is not part of the public API. It may change without warning.
---Use at your own risk.

---@brief ]]

---@class ocaml.Sandbox
local M = {}
local Esy = require("ocaml.sandbox.esy")
local Opam = require("ocaml.sandbox.opam")

-- Detect if the given directory is an esy sandbox.
-- @param dir string The directory to check
-- @return boolean True if the directory is an esy sandbox, false otherwise
local function is_esy_sandbox(dir)
  -- first check if esy command is available
  if vim.fn.executable("esy") == 0 then
    return false
  end

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

-- Get the sandboxed command for any OCaml tool in the given directory.
-- Priority: esy sandbox > opam local switch > global command
-- @param dir string The directory to check
-- @param cmd string[] The command to run (e.g., {"dune", "build", "--watch"})
-- @return string[] The sandboxed command
function M.get_command(dir, cmd)
  -- Check esy first (higher priority)
  if is_esy_sandbox(dir) then
    local esy_cmd = Esy.get_command(Esy.get_project_manifest(dir), cmd)
    if esy_cmd then
      return esy_cmd
    end
  end

  -- Check opam local switch
  if vim.fn.executable("opam") == 1 then
    local sandbox, _ = Opam.create_sandbox()
    local switch = Opam.get_local_switch(sandbox, dir)
    if switch then
      local opam_cmd = Opam.get_command(sandbox, switch, cmd)
      if opam_cmd then
        return opam_cmd
      end
    end
  end

  -- Fallback to global command
  return cmd
end

-- Get the LSP command for the given directory.
-- Priority: esy sandbox > opam local switch > global command
-- @param dir string The directory to check
-- @param args string[] Additional arguments to pass to the lsp command
-- @return string[] The lsp command
function M.get_lsp_command(dir, args)
  local cmd = { "ocamllsp" }
  -- insert additional args
  vim.list_extend(cmd, args or {})

  return M.get_command(dir, cmd)
end

return M
