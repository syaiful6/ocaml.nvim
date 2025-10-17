---@mod ocaml.commands.select_ast
---@brief [[
--- Commands for selecting based on OCaml AST structure.
--- Uses ocamllsp/wrappingAstNode to select the wrapping AST node at cursor.
---
--- For expanding/shrinking selections, use type_enclosing module instead,
--- which uses the ocamllsp/typeEnclosing LSP method.
---]]

local LspHelpers = require("ocaml.lsp.helpers")
local M = {}

---Get the wrapping AST node at cursor position
---@param position? lsp.Position Optional position (defaults to cursor)
---@param callback fun(range: lsp.Range|nil, err: any)
local function get_wrapping_ast_node(position, callback)
  if not position then
    local row, col = unpack(vim.api.nvim_win_get_cursor(0))
    position = { line = row - 1, character = col }
  end

  local params = {
    uri = vim.uri_from_bufnr(0),
    position = position,
  }

  LspHelpers.buf_request(0, "ocamllsp/wrappingAstNode", params, function(err, result)
    if err then
      callback(nil, err)
      return
    end

    callback(result, nil)
  end)
end

---Convert LSP range to Neovim selection
---@param range lsp.Range
local function select_range(range)
  if not range or not range.start or not range["end"] then
    return
  end

  -- Switch to visual mode if not already
  local mode = vim.api.nvim_get_mode().mode
  if mode ~= "v" and mode ~= "V" and mode ~= "\22" then -- \22 is <C-v>
    vim.cmd("normal! v")
  end

  -- Set selection (LSP uses 0-indexed lines, Neovim uses 1-indexed)
  vim.api.nvim_win_set_cursor(0, { range.start.line + 1, range.start.character })
  vim.cmd("normal! o")
  vim.api.nvim_win_set_cursor(0, { range["end"].line + 1, range["end"].character })
end

---Select the wrapping AST node at cursor position
function M.select_wrapping_ast_node()
  get_wrapping_ast_node(nil, function(range, err)
    if err then
      vim.notify("[ocaml.nvim] Error getting wrapping AST node: " .. err.message, vim.log.levels.ERROR)
      return
    end

    if not range then
      vim.notify("[ocaml.nvim] No wrapping AST node found", vim.log.levels.INFO)
      return
    end

    select_range(range)
  end)
end

return M
