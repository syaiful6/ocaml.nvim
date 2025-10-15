---@mod ocaml.lsp
---@brief [[
---LSP integration for OCaml
---@brief ]]

local config = require("ocaml.config.internal")
local lsp_helpers = require("ocaml.lsp.helpers")
local helpers = require("ocaml.helpers")

local M = {}

---@class ocaml.lsp.ocamllsp.Enabled
---@field enable boolean

---Configure LSP settings for OCaml LSP server
---@param lsp_config ocaml.lsp.StartConfig
---@return table<string, ocaml.lsp.ocamllsp.Enabled>
local function configure_settings(lsp_config)
  local ocaml_settings = lsp_config.settings or {}
  for key, value in pairs(ocaml_settings) do
    if type(value) == "boolean" then
      ocaml_settings[key] = { enable = value }
    end
  end
  return ocaml_settings
end

---Configure supported filetypes and language ID mapping
---@param lsp_config ocaml.lsp.StartConfig
---@return table
local function configure_filetypes(lsp_config)
  local filetypes = vim.deepcopy(lsp_config.filetypes or {})

  local ensure_filetypes = {
    "ocaml",
    "ocaml.interface",
    "ocaml.menhir",
    "ocaml.ocamllex",
    "reason",
    "reason.interface",
    "ocaml.mlx",
    "ocaml.cram",
    "dune",
    "dune-project",
    "dune-workspace",
  }

  for _, ft in ipairs(ensure_filetypes) do
    if not vim.tbl_contains(filetypes, ft) then
      table.insert(filetypes, ft)
    end
  end

  local original_get_language_id = lsp_config.get_language_id
  local get_language_id = function(buf, filetype)
    -- Map filetypes to language IDs expected by ocamllsp
    -- See: https://github.com/ocaml/ocaml-lsp/blob/master/ocaml-lsp-server/src/document.ml
    if filetype == "ocaml.interface" then
      return "ocaml.interface"
    elseif filetype == "ocaml.menhir" then
      return "ocaml.menhir"
    elseif filetype == "ocaml.ocamllex" then
      return "ocaml.ocamllex"
    elseif filetype == "reason" or filetype == "reason.interface" then
      return "reason"
    elseif filetype == "ocaml.mlx" then
      return "ocaml"
    elseif filetype == "ocaml.cram" then
      return "cram"
    elseif filetype == "dune" or filetype == "dune-project" or filetype == "dune-workspace" then
      return "dune"
    else
      return original_get_language_id and original_get_language_id(buf, filetype) or filetype
    end
  end

  return filetypes, get_language_id
end

--- Default on_attach function
---@param client vim.lsp.Client The LSP client
---@param bufnr number The buffer number
local function default_on_attach(client, bufnr)
  -- Enable completion with autotrigger
  vim.lsp.completion.enable(true, client.id, bufnr, {
    autotrigger = true,
  })

  -- Enable inlay hints if supported
  if client.server_capabilities.inlayHintProvider then
    vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
  end
end

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
  local client_config = vim.tbl_deep_extend("force", ocaml_config, config.lsp or {}) --[[@as ocaml.lsp.ClientConfig]]
  ---@type ocaml.lsp.StartConfig
  local lsp_start_config = vim.tbl_deep_extend("force", {}, client_config) --[[@as ocaml.lsp.StartConfig]]

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

  -- Configure LSP components using extracted functions
  lsp_start_config.settings = configure_settings(lsp_start_config)

  local filetypes, get_language_id = configure_filetypes(lsp_start_config)
  lsp_start_config.filetypes = filetypes
  lsp_start_config.get_language_id = get_language_id

  -- Get and validate LSP command
  local lsp_cmd = lsp_helpers.get_lsp_cmd(normalized_cwd)
  if not lsp_cmd or type(lsp_cmd) ~= "table" or #lsp_cmd == 0 then
    vim.notify("[ocaml.nvim] Invalid LSP command: " .. vim.inspect(lsp_cmd), vim.log.levels.ERROR)
    return
  end

  -- Ensure all command arguments are strings
  for i, arg in ipairs(lsp_cmd) do
    if type(arg) ~= "string" then
      vim.notify("[ocaml.nvim] Invalid LSP command argument at index " .. i .. ": " .. type(arg), vim.log.levels.ERROR)
      return
    end
  end

  lsp_start_config.cmd = vim.deepcopy(lsp_cmd)
  lsp_start_config.name = lsp_helpers.ocaml_client_name

  -- Check if client is already running for this project
  local clients = lsp_helpers.get_active_lsp_clients()
  for _, client in ipairs(clients) do
    local client_root_dir = vim.fs.normalize(client.config.root_dir or "")
    if client_root_dir == normalized_cwd then
      -- Client already running for this project
      vim.lsp.buf_attach_client(bufnr, client.id)
      return
    end
  end

  local on_attach = lsp_start_config.on_attach
  lsp_start_config.on_attach = function(client, buf)
    default_on_attach(client, buf)
    if on_attach and type(on_attach) == "function" then
      on_attach(client, buf)
    end
  end

  -- Start new LSP client
  local client_id = vim.lsp.start(lsp_start_config, { bufnr = bufnr })

  if not client_id then
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

return M
