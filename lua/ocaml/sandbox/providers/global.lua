---@mod ocaml.sandbox.providers.global Global (no sandbox) provider
---
---@brief [[
---WARNING: This is not part of the public API. It may change without warning.
---Use at your own risk.
---
---Commands run unchanged from the user's PATH. This provider always returns
---one candidate and belongs last in the priority list.
---@brief ]]

---@class ocaml.sandbox.providers.Global: ocaml.sandbox.Provider
local M = {
  name = "global",
}

function M.detect(root, cb)
  cb({
    {
      id = "global",
      provider = M.name,
      label = "global",
      root = root,
      data = {},
    },
  })
end

function M.wrap(_, cmd)
  return vim.deepcopy(cmd)
end

return M
