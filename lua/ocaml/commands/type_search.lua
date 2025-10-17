---@mod ocaml.commands.type_search
---@brief [[
--- Commands for searching OCaml functions and types by type signature
---]]

local LspHelpers = require("ocaml.lsp.helpers")
local Picker = require("ocaml.picker")
local M = {}

---@class ocaml.commands.TypeSearchParams: lsp.TextDocumentPositionParams
---@field query string The type search pattern
---@field limit integer Maximum number of results to return
---@field with_doc boolean Whether to include documentation
---@field doc_format? string Documentation format

---@class ocaml.commands.TypeSearchResult
---@field name string The fully qualified name
---@field typ string The type signature
---@field loc lsp.Range The location of the definition
---@field doc? { value: string, kind: string } Optional documentation
---@field cost integer Distance between result and query
---@field constructible string Template to invoke this result

---Insert text at cursor position
---@param text string
local function insert_at_cursor(text)
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  vim.api.nvim_buf_set_text(0, row - 1, col, row - 1, col, { text })
  -- Move cursor to end of inserted text
  vim.api.nvim_win_set_cursor(0, { row, col + #text })
end

---Perform LSP type search query
---@param query string
---@param limit integer
---@param with_doc boolean
---@param callback fun(results: ocaml.commands.TypeSearchResult[]|nil, error: any)
local function lsp_type_search(query, limit, with_doc, callback)
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  ---@type ocaml.commands.TypeSearchParams
  local params = {
    textDocument = vim.lsp.util.make_text_document_params(0),
    position = { line = row - 1, character = col },
    query = query,
    limit = limit,
    with_doc = with_doc,
    doc_format = "markdown",
  }

  LspHelpers.buf_request(0, "ocamllsp/typeSearch", params, function(err, result)
    if err then
      callback(nil, err)
      return
    end

    if not result or #result == 0 then
      callback({}, nil)
      return
    end

    callback(result, nil)
  end)
end

---Perform a type search and show picker
---@param query string Type pattern to search for
---@param opts? { limit?: integer, with_doc?: boolean }
function M.type_search(query, opts)
  opts = opts or {}
  local limit = opts.limit or 20
  local with_doc = opts.with_doc == nil and true or opts.with_doc -- Enable docs by default

  if not query or query == "" then
    vim.notify("[ocaml.nvim] Type search query cannot be empty", vim.log.levels.WARN)
    return
  end

  -- Perform search
  lsp_type_search(query, limit, with_doc, function(results, err)
    if err then
      vim.notify("[ocaml.nvim] Error requesting type search: " .. err.message, vim.log.levels.ERROR)
      return
    end

    if not results or #results == 0 then
      vim.notify("[ocaml.nvim] No results found for query: " .. query, vim.log.levels.INFO)
      return
    end

    ---@cast results ocaml.commands.TypeSearchResult[]

    -- Use picker with fzf-lua/telescope fuzzy matching on results
    Picker.select(results, {
      prompt = "Type Search: " .. query .. " > ",
      format_item = function(item)
        return string.format("%s : %s", item.name, item.typ)
      end,
      on_choice = function(choice)
        if choice then
          insert_at_cursor(choice.constructible)
        end
      end,
    })
  end)
end

---Prompt user for query and perform type search
---@param opts? { limit?: integer, with_doc?: boolean }
function M.type_search_prompt(opts)
  vim.ui.input({ prompt = "Type search query: " }, function(query)
    if query and query ~= "" then
      M.type_search(query, opts)
    end
  end)
end

return M
