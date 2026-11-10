---@mod ocaml.sandbox.providers.opam Opam sandbox provider
---
---@brief [[
---WARNING: This is not part of the public API. It may change without warning.
---Use at your own risk.
---@brief ]]

local Opam = require("ocaml.sandbox.opam")

---@class ocaml.sandbox.opam.Data
---@field binary string The opam binary
---@field opam_root string The opam root directory
---@field switch string The switch name (a path for local switches)

---@class ocaml.sandbox.providers.Opam: ocaml.sandbox.Provider
local M = {
  name = "opam",
}

---The shared opam binary and root. `false` means opam is unavailable.
---@type ocaml.sandbox.opam.Sandbox|false|nil
local installation = nil

---Callbacks waiting for the installation lookup.
---@type fun(opam: ocaml.sandbox.opam.Sandbox|nil)[]|nil
local installation_waiters = nil

---@param cb fun(opam: ocaml.sandbox.opam.Sandbox|nil)
local function get_installation(cb)
  if installation ~= nil then
    return cb(installation or nil)
  end

  if installation_waiters then
    table.insert(installation_waiters, cb)
    return
  end

  local waiters = { cb }
  installation_waiters = waiters
  Opam.create_sandbox(nil, nil, function(opam)
    -- Do not cache the result if reset() ran during lookup.
    if installation_waiters == waiters then
      installation_waiters = nil
      installation = opam or false
    end
    for _, waiter in ipairs(waiters) do
      waiter(opam)
    end
  end)
end

function M.reset()
  installation = nil
  installation_waiters = nil
end

function M.detect(root, cb)
  if vim.fn.executable("opam") == 0 then
    return cb({})
  end

  get_installation(function(opam)
    if not opam then
      return cb({})
    end

    -- Global and parent-directory switches are not detected yet.
    Opam.get_local_switch(opam, root, function(switch)
      if not switch then
        return cb({})
      end

      cb({
        {
          id = "opam:" .. switch,
          provider = M.name,
          label = "opam " .. vim.fn.fnamemodify(switch, ":~:.") .. " (local)",
          root = root,
          ---@type ocaml.sandbox.opam.Data
          data = { binary = opam.binary, opam_root = opam.root, switch = switch },
        },
      })
    end)
  end)
end

function M.wrap(sandbox, cmd)
  local data = sandbox.data
  return Opam.get_command({ binary = data.binary, root = data.opam_root }, data.switch, cmd)
end

return M
