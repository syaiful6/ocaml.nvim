---@mod ocaml.sandbox.providers.esy Esy sandbox provider
---
---@brief [[
---WARNING: This is not part of the public API. It may change without warning.
---Use at your own risk.
---@brief ]]

local Esy = require("ocaml.sandbox.esy")

---@class ocaml.sandbox.esy.Data
---@field manifest string Path to the esy.json / package.json manifest
---@field binary string The esy binary

---@class ocaml.sandbox.providers.Esy: ocaml.sandbox.Provider
local M = {
  name = "esy",
}

--- Return true when the manifest declares an "esy" field.
---@param manifest string
---@return boolean
local function has_esy_field(manifest)
  local ok, content = pcall(vim.fn.readfile, manifest)
  if not ok or not content then
    return false
  end
  local ok_json, json = pcall(vim.fn.json_decode, content)
  return ok_json and type(json) == "table" and json["esy"] ~= nil
end

function M.detect(root, cb)
  local binary = require("ocaml.config.internal").sandbox.esy.binary
  if vim.fn.executable(binary) == 0 then
    return cb({})
  end

  local manifest = Esy.get_project_manifest(root)
  if not manifest or not has_esy_field(manifest) then
    return cb({})
  end

  cb({
    {
      id = "esy:" .. manifest,
      provider = M.name,
      label = "esy " .. vim.fn.fnamemodify(manifest, ":~:."),
      root = root,
      ---@type ocaml.sandbox.esy.Data
      data = { manifest = manifest, binary = binary },
    },
  })
end

function M.wrap(sandbox, cmd)
  return Esy.get_command(sandbox.data.manifest, cmd, sandbox.data.binary)
end

return M
