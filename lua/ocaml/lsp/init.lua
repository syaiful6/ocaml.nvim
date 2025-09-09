---@mod ocaml.lsp
---@brief [[
---LSP integration for OCaml
---@brief ]]

local config = require("ocaml.config.internal")
local lsp_helpers = require("ocaml.lsp.helpers")
local helpers = require("ocaml.helpers")

local M = {}

---@class ocaml.lsp.StartConfig: ocaml.lsp.ClientConfig
---@field root_dir string | nil
---@field cmd string[]
---@field name string
---@field filetypes string[]
---@field handlers lsp.Handler[]
---@field on_init function
---@field on_attach function
---@field on_exit function

---Start LSP client for the current buffer
---
---@param bufnr? number The buffer number (optional), default to the current buffer
M.start = function(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  local ocaml_config = vim.lsp.config[lsp_helpers.ocaml_client_name] or {}
  ---@type ocaml.lsp.StartConfig
  local lsp_start_config = vim.tbl_deep_extend("force", config.lsp, ocaml_config) --[[@as ocaml.lsp.StartConfig]]

  -- Find project root using OCaml-specific patterns
  local root_dir = helpers.root_pattern(
    "dune-project",
    "dune-workspace",
    "package.json", -- for esy projects
    "esy.json", -- for esy projects
    "*.opam",
    "_build",
    ".git"
  )(bufname)

  if not root_dir then
    vim.notify(
      [[
ocaml.nvim:
No project root found.
      ]],
      vim.log.levels.INFO
    )
    root_dir = vim.fs.dirname(bufname)
  end

  -- Normalize paths for consistent comparison
  local normalized_cwd = vim.fs.normalize(root_dir)
  lsp_start_config.root_dir = normalized_cwd
  lsp_start_config.settings = type(lsp_start_config.settings) == "function"
      and lsp_start_config.settings(normalized_cwd)
    or lsp_start_config.settings
  lsp_start_config.cmd = lsp_helpers.get_lsp_cmd(normalized_cwd)
  lsp_start_config.name = lsp_helpers.ocaml_client_name
  lsp_start_config.filetypes = { "ocaml", "reason", "ocaml.mlx", "ocaml.cram" }

  -- Check if client is already running
  local clients = lsp_helpers.get_active_lsp_clients()
  for _, client in ipairs(clients) do
    local client_root_dir = vim.fs.normalize(client.config.root_dir or "")
    if client_root_dir == normalized_cwd then
      -- Client already running for this project
      vim.lsp.buf_attach_client(bufnr, client.id)
      return
    end
  end

  -- Start new LSP client
  local client_id = vim.lsp.start(lsp_start_config, { bufnr = bufnr })

  if client_id then
    vim.lsp.buf_attach_client(bufnr, client_id)

    -- Call on_attach if configured
    if lsp_start_config.on_attach then
      lsp_start_config.on_attach(client_id, bufnr)
    end
  else
    vim.notify("[ocaml.nvim] Failed to start OCaml LSP server", vim.log.levels.ERROR)
  end
end

---Stop LSP client for the current buffer
---@param bufnr? number The buffer number (optional), default to the current buffer
M.stop = function(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local clients = lsp_helpers.get_active_lsp_clients(bufnr)

  for _, client in ipairs(clients) do
    vim.lsp.stop_client(client.id)
  end
end

---Restart LSP client for the current buffer
---@param bufnr? number The buffer number (optional), default to the current buffer
M.restart = function(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  M.stop(bufnr)

  -- Small delay to ensure client is fully stopped
  vim.defer_fn(function()
    M.start(bufnr)
  end, 100)
end

---Get LSP client status for the current buffer
---@param bufnr? number The buffer number (optional), default to the current buffer
---@return boolean is_running true if LSP client is running
M.get_status = function(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local clients = lsp_helpers.get_active_lsp_clients(bufnr)
  return #clients > 0
end

---@enum ocaml.lsp.Cmd
local Cmd = {
  start = "start",
  stop = "stop",
  restart = "restart",
}

local function ocaml_lsp_user_cmd(opts)
  local fargs = opts.fargs
  local cmd = table.remove(fargs, 1)
  ---@cast cmd ocaml.lsp.Cmd
  if cmd == Cmd.start then
    M.start()
  elseif cmd == Cmd.stop then
    M.stop()
  elseif cmd == Cmd.restart then
    M.restart()
  end
end

vim.api.nvim_create_user_command("OcamlLsp", ocaml_lsp_user_cmd, {
  nargs = "+",
  desc = "Start, stops the OCaml LSP client",
  complete = function(arg_lead, cmdline, _)
    local clients = lsp_helpers.get_active_lsp_clients()
    ---@type ocaml.lsp.Cmd[]
    local commands = #clients == 0 and { "start" } or { "stop", "restart" }
    if cmdline:match("^OcamlLsp%s+%w*$") then
      return vim.tbl_filter(function(command)
        return command:find(arg_lead) ~= nil
      end, commands)
    end
  end,
})

return M
