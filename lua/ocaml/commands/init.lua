---@mod ocaml.commands
---@brief [[
---User commands for OCaml development
---]]

local TS = require("ocaml.commands.treesitter")
local LSP = require("ocaml.lsp")

local M = {}

---@class ocaml.commands.Subcommand
---
---The command implementation
---@field impl fun(args: string[], opts: vim.api.keyset.user_command)
---
---Command completion callback, taking the lead of the subcommand's arguments
---Or a list of subcommand
---@field complete? string[] | fun(subcmd_arg_lead: string): string[]
---
---Whether the command supports a bang!
---@field bang? boolean

---@type table<string, ocaml.commands.Subcommand>
local command_tbl = {}

---@param name string The name of the subcommand
---@param subcmd_tbl table<string, ocaml.commands.Subcommand> The subcommand's subcommand table
local function register_subcommand_tbl(name, subcmd_tbl)
  command_tbl[name] = {
    impl = function(args, ...)
      local subcmd = subcmd_tbl[table.remove(args, 1)]
      if subcmd then
        subcmd.impl(args, ...)
      else
        vim.notify(
          ([[
OCaml %s: Expected subcommand.
Available subcommands:
%s
]]):format(name, table.concat(vim.tbl_keys(subcmd_tbl), ", ")),
          vim.log.levels.ERROR
        )
      end
    end,
    complete = function(subcmd_arg_lead)
      local subcmd, next_arg_lead = subcmd_arg_lead:match("^(%S+)%s*(.*)$")
      if subcmd and next_arg_lead and subcmd_tbl[subcmd] and subcmd_tbl[subcmd].complete then
        return subcmd_tbl[subcmd].complete(next_arg_lead)
      end
      if subcmd_arg_lead and subcmd_arg_lead ~= "" then
        return vim
          .iter(subcmd_tbl)
          ---@param subcmd_name string
          :filter(function(subcmd_name)
            return subcmd_name:find(subcmd_arg_lead) ~= nil
          end)
          :totable()
      end
      return vim.tbl_keys(subcmd_tbl)
    end,
  }
end

---@type table<string, ocaml.commands.Subcommand>
local treesitter_subcmd_tbl = {
  install_reason = {
    impl = function()
      TS.install_reason()
    end,
  },
  install_mlx = {
    impl = function()
      TS.install_mlx()
    end,
  },
}

register_subcommand_tbl("ts", treesitter_subcmd_tbl)

---@type table<string, ocaml.commands.Subcommand>
local lsp_subcmd_tbl = {
  start = {
    impl = function()
      LSP.start()
    end,
  },
  stop = {
    impl = function()
      LSP.stop()
    end,
  },
  restart = {
    impl = function()
      LSP.restart()
    end,
  },
}

register_subcommand_tbl("lsp", lsp_subcmd_tbl)

---@generic K,V
---@param predicate fun(V): boolean
---@param tbl table<K,V>
---@return K[]
local function filter_keys_by_value(predicate, tbl)
  local result = {}
  for k, v in pairs(tbl) do
    if predicate(v) then
      table.insert(result, k)
    end
  end
  return result
end

local function ocaml_command_impl(opts)
  local fargs = opts.fargs
  local cmd = fargs[1]
  local args = #fargs > 1 and vim.list_slice(fargs, 2, #fargs) or {}
  local command = command_tbl[cmd]
  if not command then
    vim.notify(
      string.format("[ocaml.nvim] Unknown command '%s' for :OCaml", cmd and cmd or "<nil>"),
      vim.log.levels.ERROR
    )
    return
  end
  command.impl(args, opts)
end

function M.setup()
  vim.api.nvim_create_user_command("OCaml", ocaml_command_impl, {
    nargs = "+",
    complete = function(arg_lead, cmdline, _)
      local commands = cmdline:match("^['<,'>]*OCaml!") ~= nil
          and filter_keys_by_value(function(c)
            return c.bang == true
          end, command_tbl)
        or vim.tbl_keys(command_tbl)
      local subcmd, subcmd_arg_lead = cmdline:match("^['<,'>]*OCaml[!]*%s(%S+)%s(.*)$")
      if subcmd and subcmd_arg_lead and command_tbl[subcmd] and command_tbl[subcmd].complete then
        return command_tbl[subcmd].complete(subcmd_arg_lead)
      end
      if cmdline:match("^['<,'>]*OCaml[!]*%s+%w$") then
        return vim.tbl_filter(function(c)
          return c:find(arg_lead) ~= nil
        end, commands)
      end
    end,
    bang = false,
  })
end

return M
