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

---@param bufnr? number the buffer to get clients for
---@param method string LSP method name
---@param params table|nil Parameters to send to the server
---@param handler? lsp.Handler The handler to call when the response is received,
---@return boolean client_found True if a client was found and the request was sent
M.buf_request = function(bufnr, method, params, handler)
  if bufnr == nil or bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  local client_found = false
  local clients = M.get_active_lsp_clients(bufnr, { method = method })
  for _, client in ipairs(clients) do
    client:request(method, params, handler, 0)
    client_found = true
  end
  return client_found
end

--- Resolve the sandbox for a project root and build the OCaml LSP command.
---
---@param root_dir string The project root directory
---@param cb fun(cmd: string[]|nil, sandbox: ocaml.sandbox.Sandbox, err: string|nil)
M.get_lsp_cmd = function(root_dir, cb)
  local sandbox = require("ocaml.sandbox")
  sandbox.resolve(root_dir, function(sb)
    local cmd, err = sandbox.get_lsp_command(sb, {})
    cb(cmd, sb, err)
  end)
end

return M
