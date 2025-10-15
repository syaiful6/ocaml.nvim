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

---Install a parser
---@param name string parser name
---@param info table parser info
---@return boolean success
local function install_parser(name, info)
  if not pcall(require, "nvim-treesitter") then
    vim.notify("[ocaml.nvim] nvim-treesitter is required for Treesitter support", vim.log.levels.ERROR)
    return false
  end

  local list = get_parser_config()
  list[name] = info

  vim.api.nvim_create_autocmd("User", {
    pattern = "TSUpdate",
    callback = function()
      local parsers = get_parser_config()
      parsers[name] = info
    end,
  })

  return true
end

function M.install_language_parsers()
  install_parser("reason", {
    install_info = {
      url = "https://github.com/reasonml-editor/tree-sitter-reason",
      files = { "src/parser.c", "src/scanner.c" },
      branch = "master",
    },
  })

  install_parser("ocaml_mlx", {
    install_info = {
      location = "grammars/mlx",
      url = "https://github.com/ocaml-mlx/tree-sitter-mlx",
      files = { "src/parser.c", "src/scanner.c" },
      branch = "master",
      -- generate_requires_npm = false,
      -- requires_generate_from_grammar = false,
    },
  })

  install_parser("dune", {
    install_info = {
      url = "https://github.com/WHForks/tree-sitter-dune",
      files = { "src/parser.c" },
      branch = "with-generated",
    },
    filetype = "dune",
  })

  install_parser("menhir", {
    install_info = {
      url = "https://github.com/Kerl13/tree-sitter-menhir",
      files = { "src/parser.c", "src/scanner.c" },
      branch = "master",
    },
    filetype = "menhir",
  })

  install_parser("ocamllex", {
    install_info = {
      url = "https://github.com/314eter/tree-sitter-ocamllex",
      files = { "src/parser.c", "src/scanner.c" },
      branch = "master",
    },
    filetype = "ocamllex",
  })
end

return M
