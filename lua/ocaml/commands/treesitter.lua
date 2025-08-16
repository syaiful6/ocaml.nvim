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
local install_reason = function()
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

  local install = require("nvim-treesitter.install")
  install.ensure_installed("reason")
end

local install_mlx = function()
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

  local install = require("nvim-treesitter.install")
  install.ensure_installed("ocaml_mlx")
end

---@enum ocaml.commands.treesitter.Cmd
local Cmd = {
  install_reason = "install_reason",
  install_mlx = "install_mlx",
}

local function ocaml_treesitter_user_cmd(opts)
  local fargs = opts.fargs
  local cmd = table.remove(fargs, 1)
  if cmd == Cmd.install_reason then
    install_reason()
  elseif cmd == Cmd.install_mlx then
    install_mlx()
  end
end

---Setup Treesitter commands
function M.setup()
  vim.api.nvim_create_user_command("OCamlTS", ocaml_treesitter_user_cmd, {
    nargs = "+",
    desc = "Install Reason and Mlx etc",
    complete = function(arg_lead, cmdline, _)
      if cmdline:match("^OCamlTS%s+%w*$") then
        return vim.tbl_filter(function(command)
          return command:find(arg_lead) ~= nil
        end, Cmd)
      end
    end,
  })
end

return M
