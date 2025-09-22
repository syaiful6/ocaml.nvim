---@mod ocaml.command.treesitter
---
---@brief [[
---treesitter parser management commands for OCaml
---]]

local M = {}

---Get parser configurations
---@return table parser_configs
local function get_parser_config()
  if not pcall(require, "nvim-treesitter") then
    return {}
  end

  local parsers = require("nvim-treesitter.parsers")
  return parsers.get_parser_configs and parsers.get_parser_configs() or parsers
end

--- Install Reason Treesitter
function M.install_reason()
  if not pcall(require, "nvim-treesitter") then
    vim.notify("[ocaml.nvim] nvim-treesitter is required for Treesitter support", vim.log.levels.ERROR)
    return false
  end

  local list = get_parser_config()

  --- Configure Reason parsers
  list.reason = {
    install_info = {
      url = "https://github.com/reasonml-editor/tree-sitter-reason",
      files = { "src/parser.c", "src/scanner.c" },
      branch = "master",
    },
  }
end

function M.install_mlx()
  if not pcall(require, "nvim-treesitter") then
    vim.notify("[ocaml.nvim] nvim-treesitter is required for Treesitter support", vim.log.levels.ERROR)
    return false
  end

  local list = get_parser_config()

  list.ocaml_mlx = {
    tier = 0,

    install_info = {
      location = "grammars/mlx",
      url = "https://github.com/ocaml-mlx/tree-sitter-mlx",
      files = { "src/parser.c", "src/scanner.c" },
      branch = "master",
    },
    filetype = "ocaml_mlx",
  }
end

return M
