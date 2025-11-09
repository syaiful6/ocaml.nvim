---@mod ocaml.commands.doc
---@brief [[
--- Command to retrieve odoc documentation for a specific identifier.
--- This allows you to query documentation for modules, functions, types, etc.
--- by name without having to navigate to them first.
---
--- Example usage:
---   :OCaml doc List.map
---   :OCaml doc String.concat
---@brief ]]

local LspHelpers = require("ocaml.lsp.helpers")
local M = {}

---@class ocaml.commands.doc.GetDocParams
---@field textDocument lsp.TextDocumentIdentifier
---@field position lsp.Position
---@field identifier? string Specific identifier to look up
---@field contentFormat? "plaintext" | "markdown"

---@class ocaml.commands.doc.GetDocResponse
---@field doc lsp.MarkupContent

---Show documentation in a floating window
---@param doc lsp.MarkupContent The documentation to display
---@param identifier string The identifier being documented
local function show_documentation(doc, identifier)
  -- Prepare content based on markup kind
  local contents = vim.split(doc.value, "\n")

  local buf, win = vim.lsp.util.open_floating_preview(contents, doc.kind, {
    border = "rounded",
    max_width = math.floor(vim.o.columns * 0.8),
    max_height = math.floor(vim.o.lines * 0.8),
    focusable = true,
    focus_id = "ocaml_documentation",
    title = " Documentation: " .. identifier .. " ",
    title_pos = "center",
  })

  if win and vim.api.nvim_win_is_valid(win) then
    vim.keymap.set("n", "q", function()
      vim.api.nvim_win_close(win, true)
    end, { buffer = buf, nowait = true, silent = true })
    vim.keymap.set("n", "<Esc>", function()
      vim.api.nvim_win_close(win, true)
    end, { buffer = buf, nowait = true, silent = true })
  end
end

---Get documentation for a specific identifier
---@param identifier string The identifier to get documentation for (e.g., "List.map", "Piaf.Server")
function M.get_documentation(identifier)
  if not identifier or identifier == "" then
    vim.notify("[ocaml.nvim] Please provide an identifier (e.g., :OCaml doc List.map)", vim.log.levels.WARN)
    return
  end

  local buf = vim.api.nvim_get_current_buf()

  ---@type ocaml.commands.doc.GetDocParams
  local params = {
    textDocument = vim.lsp.util.make_text_document_params(buf),
    position = { line = 0, character = 0 }, -- Position doesn't matter when identifier is provided
    identifier = identifier,
    contentFormat = "markdown",
  }

  LspHelpers.buf_request(buf, "ocamllsp/getDocumentation", params, function(err, result)
    if err then
      vim.notify(
        "[ocaml.nvim] Error requesting documentation: " .. (err.message or vim.inspect(err)),
        vim.log.levels.ERROR
      )
      return
    end

    if not result or not result.doc then
      vim.notify(string.format("[ocaml.nvim] No documentation found for '%s'", identifier), vim.log.levels.WARN)
      return
    end

    ---@cast result ocaml.commands.doc.GetDocResponse
    show_documentation(result.doc, identifier)
  end)
end

return M
