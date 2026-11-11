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
  local config = require("ocaml.config.internal").sandbox.opam
  Opam.create_sandbox(config.binary, config.root, function(opam)
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
  if vim.fn.executable(require("ocaml.config.internal").sandbox.opam.binary) == 0 then
    return cb({})
  end

  get_installation(function(opam)
    if not opam then
      return cb({})
    end

    Opam.get_switches(opam, function(switches)
      if not switches then
        return cb({})
      end

      local locals = Opam.find_local_switches(switches, root)
      if #locals > 0 then
        return cb(M.build_candidates(opam, root, switches, locals, nil))
      end

      -- No local switch: ask opam which switch it would use here
      -- (OPAMSWITCH or the globally selected one).
      Opam.get_current_switch(opam, root, function(current)
        cb(M.build_candidates(opam, root, switches, locals, current))
      end)
    end)
  end)
end

---Whether `ocamllsp` is installed in a switch.
---@param opam ocaml.sandbox.opam.Sandbox
---@param switch string
---@return boolean
function M.has_ocamllsp(opam, switch)
  local bin = vim.fs.joinpath(Opam.switch_prefix(opam, switch), "bin", "ocamllsp")
  return vim.fn.executable(bin) == 1
end

---Order the switches available to `root`, with local switches first.
---Local switches are always eligible for automatic selection. The current
---global switch is eligible only when it contains `ocamllsp`; other global
---switches remain available for manual selection. Switches local to unrelated
---projects are excluded.
---@param opam ocaml.sandbox.opam.Sandbox
---@param root string
---@param switches string[] All switches, from `opam switch list -s`
---@param locals string[] Local switches applying to `root`, nearest first
---@param current string|nil The switch opam selects in `root`, if known
---@return ocaml.sandbox.Sandbox[]
function M.build_candidates(opam, root, switches, locals, current)
  local candidates = {}
  local seen = {}

  local function add(switch, auto)
    if seen[switch] then
      return
    end
    seen[switch] = true
    local is_local = Opam.is_local_switch(switch)
    local label = "opam "
      .. (is_local and vim.fn.fnamemodify(switch, ":~") .. " (local)" or switch)
      .. (switch == current and " (current)" or "")
    table.insert(candidates, {
      id = "opam:" .. switch,
      provider = M.name,
      label = label,
      root = root,
      auto = auto,
      ---@type ocaml.sandbox.opam.Data
      data = { binary = opam.binary, opam_root = opam.root, switch = switch },
    })
  end

  for _, switch in ipairs(locals) do
    add(switch, true)
  end
  if current then
    add(current, M.has_ocamllsp(opam, current))
  end
  for _, switch in ipairs(switches) do
    if not Opam.is_local_switch(switch) then
      add(switch, false)
    end
  end
  return candidates
end

function M.wrap(sandbox, cmd)
  local data = sandbox.data
  return Opam.get_command({ binary = data.binary, root = data.opam_root }, data.switch, cmd)
end

return M
