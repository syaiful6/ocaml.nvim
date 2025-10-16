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

---Parser definitions
---@type table<string, table>
local PARSERS = {
  reason = {
    install_info = {
      url = "https://github.com/reasonml-editor/tree-sitter-reason",
      files = { "src/parser.c", "src/scanner.c" },
      branch = "master",
    },
  },
  ocaml_mlx = {
    install_info = {
      location = "grammars/mlx",
      url = "https://github.com/syaiful6/tree-sitter-mlx.git",
      files = { "src/parser.c", "src/scanner.c" },
      branch = "update-grammar",
    },
    filetype = "ocaml.mlx",
  },
  dune = {
    install_info = {
      url = "https://github.com/WHForks/tree-sitter-dune",
      files = { "src/parser.c" },
      branch = "with-generated",
    },
    filetype = "dune",
  },
  menhir = {
    install_info = {
      url = "https://github.com/Kerl13/tree-sitter-menhir",
      files = { "src/parser.c", "src/scanner.c" },
      branch = "master",
    },
    filetype = "menhir",
  },
  ocamllex = {
    install_info = {
      url = "https://github.com/314eter/tree-sitter-ocamllex",
      files = { "src/parser.c", "src/scanner.c" },
      branch = "master",
    },
    filetype = "ocamllex",
  },
}

---Register all parsers in parser config
---@param parsers_config table parser config table
local function register_parsers(parsers_config)
  for name, info in pairs(PARSERS) do
    parsers_config[name] = info
  end
end

function M.install_language_parsers()
  if not pcall(require, "nvim-treesitter") then
    vim.notify("[ocaml.nvim] nvim-treesitter is required for Treesitter support", vim.log.levels.ERROR)
    return
  end

  -- Register parsers initially
  local parsers_config = get_parser_config()
  register_parsers(parsers_config)

  -- Re-register all parsers after TSUpdate
  vim.api.nvim_create_autocmd("User", {
    pattern = "TSUpdate",
    callback = function()
      local config = get_parser_config()
      register_parsers(config)
    end,
  })
end

return M
