---@mod ocaml.lsp.helpers
---
---@brief [[
---
---WARNING: This is not part of the public API.
---Breaking changes to this module will not be reflected in the semantic versioning
---of this plugin.
---@brief ]]

---@class ocaml.lsp.Helpers
local M = {}

M.ocaml_client_name = "ocamllsp"

---@param bufnr? number the buffer to get clients for
---@param filter? vim.lsp.get_clients.Filter
---@return vim.lsp.Client[] ocaml_clients The ocaml clients
M.get_active_lsp_clients = function(bufnr, filter)
  local client_filter = vim.tbl_deep_extend("force", filter or {}, {
    name = M.ocaml_client_name,
  })
  if bufnr then
    client_filter.bufnr = bufnr
  end
  return vim.lsp.get_clients(client_filter)
end

--- Get OCaml LSP command using sandbox detection
---
---@param root_dir string The project root directory
---@return string[] The LSP command array
M.get_lsp_cmd = function(root_dir)
  local sandbox = require("ocaml.sandbox")
  return sandbox.get_lsp_command(root_dir, {})
end

return M
