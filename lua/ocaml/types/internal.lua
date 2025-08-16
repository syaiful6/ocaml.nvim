---@mod ocaml.types.internal Internal types for OCaml

---@brief [[

---WARNING: This is not part of the public API.
---It is subject to change without notice.
---This module contains internal types used by the OCaml plugin.

--- Type definitions
---@brief ]]

local M = {}

---Evaluate a value that maybe a function
---or an evaluated value
---@generic T
---@param value(fun():T)|T
---@return T
M.evaluate = function(value)
  if type(value) == "function" then
    return value()
  end
  return value
end

--- Check if a module can be required
M.can_require = function(name)
  local ok, _ = pcall(require, name)
  return ok
end

return M
