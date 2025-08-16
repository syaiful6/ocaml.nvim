---@mod ocaml.commands
---@brief [[
---User commands for OCaml development
---]]

local M = {}

function M.setup()
  require("ocaml.commands.treesitter").setup()
end

return M
