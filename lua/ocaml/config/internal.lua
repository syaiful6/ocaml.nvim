---@mod ocaml.config.internal
---
---@brief [[
---
---WARNING: This is not part of the public API.
---It is subject to change without notice.
---This module contains internal configuration types used by the OCaml plugin.
---
---@brief ]]

---@class ocaml.Config ocaml.nvim plugin configuration
local OcamlDefaultConfig = {
  ---@class ocaml.lsp.ClientConfig ocaml language client options
  lsp = {
    ---@type boolean | (fun():boolean) Whether to automatically attach the LSP client.
    auto_attach = true,
    ---@type (fun(client:number,bufnr:number))
    on_attach = function(_, _) end,
    ---@type ocaml.lsp.Settings
    settings = {
      duneDiagnostics = true,
      syntaxDocumentation = true,
    },
    ---@type ocaml.lsp.Experimental
    experimental = {
      switchImplIntf = false,
      inferIntf = false,
      typedHoles = false,
      typeEnclosing = false,
      construct = false,
      destruct = false,
      jumpToNextHole = false,
    },
  },
}

local ocamlnvim = vim.g.ocamlnvim or {}
---@type ocaml.Opts
local opts = type(ocamlnvim) == "function" and ocamlnvim() or ocamlnvim

---@type ocaml.Config
local M = vim.tbl_deep_extend("force", OcamlDefaultConfig, opts or {})
---TODO: check the config is valid

return M
