---@mod ocaml.config plugin configuration
---
---@brief [[
---
---ocaml.nvim is a filetype plugin, and does not need
---a `setup` function to work.
---
---To configure the plugin, set the variable `vim.g.ocamlnvim`
---which is a `ocaml.Opts` table, in your configuration.
---
---Example:
--->
------@type ocaml.Opts
---vim.g.ocamlnvim = {
---   ---@type ocaml.lsp.ClientOpts
---   lsp = {
---     on_attach = function(client, bufnr)
---       -- Set keybindings, etc. here
---     end,
---   }
---}
---@brief ]]

local M = {}

---@type ocaml.Opts | fun():ocaml.Opts | nil
vim.g.ocamlnvim = vim.g.ocamlnvim or {}

---@class ocaml.Opts
---
---@field lsp? ocaml.lsp.ClientOpts
---The buffer from which the executor was invoked.
---@field bufnr? integer
---@field env? table<string, string>

---@class ocaml.lsp.ClientOpts
---
---Whether to automatically attach the LSP client.
---@field auto_attach? boolean | fun():boolean
---
---Whether to enable OCaml language server debug logging.
---@field debug? boolean | fun():boolean
---
---@field on_attach? fun(client:integer, bufnr:integer)
---
---LSP server settings
---@field settings? ocaml.lsp.Settings
---
---Experimental capabilities
---@field experimental? ocaml.lsp.Experimental

---@class ocaml.lsp.Settings
---OCaml LSP server configuration settings
---
---Enable/disable Dune-specific diagnostics
---@field duneDiagnostics? boolean
---
---Enable/disable syntax documentation
---@field syntaxDocumentation? boolean

---@class ocaml.lsp.Experimental
---Experimental OCaml LSP features
---
---Enable switching between implementation and interface files
---@field switchImplIntf? boolean
---
---Enable interface inference
---@field inferIntf? boolean
---
---Enable typed holes support
---@field typedHoles? boolean
---
---Enable type enclosing
---@field typeEnclosing? boolean
---
---Enable construct handling
---@field construct? boolean
---
---Enable destruct handling
---@field destruct? boolean
---
---Enable jump to next hole functionality
---@field jumpToNextHole? boolean

return M
