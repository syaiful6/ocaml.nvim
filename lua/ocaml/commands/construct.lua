---@mod ocaml.commands.construct
---@brief [[
--- Commands for pattern matching construction and deconstruction.
---
--- - construct: Fill typed holes (_) with suggested constructions. Such holes sometimes
---   appear in the result of destruct and can also be inserted manually in the source.
--- - destruct: Generate exhaustive pattern matching for expressions by enumerating all
---   possible constructors of the type.
---
--- Both commands are also accessible through the built-in LSP code action menu, however
--- in certain situations it may be more convenient to have dedicated commands.
---@brief ]]

local LspHelpers = require("ocaml.lsp.helpers")
local Picker = require("ocaml.picker")
local M = {}

---@class ocaml.commands.construct.HoleFillRequestParams
---@field uri string The URI of the buffer
---@field position lsp.Position The position of the typed hole
---@field depth? integer The depth of the construction (default: 0)
---@field withValues? "local" | "none"

function M.construct()
  local buf = vim.api.nvim_get_current_buf()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  ---@type ocaml.commands.construct.HoleFillRequestParams
  local params = {
    uri = vim.uri_from_bufnr(buf),
    position = { line = row - 1, character = col },
  }

  LspHelpers.buf_request(buf, "ocamllsp/construct", params, function(err, result)
    if err then
      vim.notify("[ocaml.nvim] Error requesting construct: " .. err.message, vim.log.levels.ERROR)
      return
    end

    if not (result and result.result and #result.result > 0) then
      vim.notify("[ocaml.nvim] No constructions available", vim.log.levels.WARN)
      return
    end

    local choices = result.result
    ---@type lsp.Range
    local range = result.position

    Picker.select(choices, {
      prompt = "Select construction:",
      format_item = function(item)
        return item
      end,
      on_choice = function(choice)
        if choice then
          vim.api.nvim_buf_set_text(
            buf,
            range.start.line,
            range.start.character,
            range["end"].line,
            range["end"].character,
            { choice }
          )
        end
      end,
    })
  end)
end

--- Generate exhaustive pattern matching by enumerating all constructors
--- of the expression's type at the cursor position.
---
--- This replaces the expression with a match statement containing branches
--- for all possible constructors. Can also be used on wildcard patterns to
--- refine them or on non-exhaustive matches to add missing cases.
function M.destruct()
  vim.lsp.buf.code_action({
    filter = function(action)
      return action.title:match("^Destruct%s*%(") ~= nil
    end,
    apply = true,
  })
end

return M
