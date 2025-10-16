---@mod ocaml.commands.jump
---@brief [[
--- Commands for jumping to definitions and references in OCaml code
---]]

local LspHelpers = require("ocaml.lsp.helpers")
local Picker = require("ocaml.picker")
local M = {}

--- Jump to next or previous typed hole at a given
--- position.
--- @param direction "next" | "prev" Direction to jump
--- @param range? lsp.Range Optional range to limit the search
function M.jump_to_typed_hole(direction, range)
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local params = {
    uri = vim.uri_from_bufnr(0),
    position = { line = row - 1, character = col },
    direction = direction,
    range = range,
  }
  LspHelpers.buf_request(0, "ocamllsp/jumpToTypedHole", params, function(err, result)
    if err then
      vim.notify("[ocaml.nvim] Error requesting typehole: " .. err.message, vim.log.levels.ERROR)
      return
    end
    if not result then
      vim.notify("[ocaml.nvim] No typehole found", vim.log.levels.INFO)
      return
    end
    vim.api.nvim_win_set_cursor(0, { result.start.line + 1, result.start.character })
  end)
end

--- Jump to position of the next or previous phrase
--- (top-level definition or module definition).
--- @param direction "next" | "prev" Direction to jump
function M.phrase(direction)
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local params = {
    uri = vim.uri_from_bufnr(0),
    command = "phrase",
    args = {
      "-position",
      row .. ":" .. col,
      "-target",
      direction,
    },
    resultAsSexp = false,
  }
  LspHelpers.buf_request(0, "ocamllsp/merlinCallCompatible", params, function(err, result)
    if err then
      vim.notify("[ocaml.nvim] Error requesting phrase: " .. vim.inspect(err), vim.log.levels.ERROR)
      return
    end
    if not (result and result.result) then
      vim.notify("[ocaml.nvim] No phrase found at cursor", vim.log.levels.INFO)
      return
    end

    local data = result.result
    local ok, parsed = pcall(vim.json.decode, data)
    if not ok or not parsed.value or not parsed.value.pos then
      vim.notify("[ocaml.nvim] Unexpected response from ocamllsp: " .. vim.inspect(data), vim.log.levels.ERROR)
      return
    end
    local line = parsed.value.pos.line
    col = parsed.value.pos.col
    if line > vim.api.nvim_buf_line_count(0) then
      vim.notify("[ocaml.nvim] No further phrases found.", vim.log.levels.INFO)
      return
    end
    vim.api.nvim_win_set_cursor(0, { line, col })
  end)
end

---@class ocaml.commands.Jump
---@field target string
---@field position lsp.Position

---@class ocaml.commands.JumpRequest: lsp.TextDocumentPositionParams
---@field target? "fun" | "let" | "module-type" | "match" | "match-next-case" | "match-prev-case" one of merlin's jump targets

---@param target? "fun" | "let" | "module-type" | "match" | "match-next-case" | "match-prev-case" one of merlin's jump targets
---@return nil
function M.merlin_jump(target)
  local text_document_position = vim.lsp.util.make_position_params(0, "utf-8") --[[@as ocaml.commands.JumpRequest]]
  text_document_position.target = target
  LspHelpers.buf_request(0, "ocamllsp/jump", text_document_position, function(err, result)
    if err then
      vim.notify("[ocaml.nvim] Error requesting merlin jump: " .. vim.inspect(err), vim.log.levels.ERROR)
      return
    end
    local jumps = result.jumps --[[@as ocaml.commands.Jump[] ]]

    if #jumps == 0 then
      vim.notify("[ocaml.nvim] No jump target found", vim.log.levels.INFO)
      return
    end

    --- If there are only one jump, go there directly
    if #jumps == 1 then
      local jump = jumps[1]
      local pos = jump.position
      vim.api.nvim_win_set_cursor(0, { pos.line + 1, pos.character })
      return
    end
    --- If there are multiple jumps, show a selection UI
    Picker.select(jumps, {
      prompt = "Select jump target:",
      format_item = function(item)
        return string.format("%s (line %d, col %d)", item.target, item.position.line + 1, item.position.character + 1)
      end,
      on_choice = function(choice)
        if choice then
          local pos = choice.position
          vim.api.nvim_win_set_cursor(0, { pos.line + 1, pos.character })
        end
      end,
    })
  end)
end

return M
