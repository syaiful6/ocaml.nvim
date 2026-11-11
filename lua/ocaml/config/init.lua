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
---Sandbox (opam switch, esy, ...) detection options.
---@field sandbox? ocaml.sandbox.Opts
---The buffer from which the executor was invoked.
---@field bufnr? integer
---@field env? table<string, string>

---@class ocaml.sandbox.Opts
---
---Providers to use, in priority order; also an allow-list. "global" (tools
---from PATH) is always used as the last resort, even when not listed.
---Default: { "esy", "opam", "global" }
---@field providers? ("esy"|"opam"|"global")[]
---
---@field opam? { binary?: string, root?: string }
---
---@field esy? { binary?: string }
---
---Pick the sandbox for a project yourself. Receives every candidate found by
---the enabled providers; return one of them (or its id, e.g. "opam:4.14.2"),
---or nil to keep the default choice. Setting this makes detection run every
---enabled provider instead of stopping at the first match.
---@field resolve? fun(root: string, candidates: ocaml.sandbox.Sandbox[]): ocaml.sandbox.Sandbox|string|nil

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
---@class ocaml.lsp.Settings
---OCaml LSP server configuration settings
---
---Enable/disable Dune-specific diagnostics
---@field duneDiagnostics? boolean
---
---Enable/disable syntax documentation
---@field syntaxDocumentation? boolean

return M
