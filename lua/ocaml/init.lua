---@mod ocaml Public API
---
---@brief [[
---This plugin is a filetype plugin and starts on its own; requiring this
---module is only needed to use the public API. Submodules load on first use.
---
---  require("ocaml").sandbox  -- see |ocaml.api.sandbox|
---@brief ]]

---@class ocaml.Api
---@field sandbox ocaml.api.sandbox
local M = {}

local submodules = {
  sandbox = "ocaml.api.sandbox",
}

return setmetatable(M, {
  __index = function(t, key)
    local name = submodules[key]
    if name then
      local mod = require(name)
      rawset(t, key, mod)
      return mod
    end
  end,
})
