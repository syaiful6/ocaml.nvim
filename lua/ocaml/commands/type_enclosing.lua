---@mod ocaml.commands.type_enclosing
---@brief [[
--- Commands for displaying types of expressions under cursor with ability to
--- navigate through enclosing expressions (zoom in/out through the type tree)
---]]

local LspHelpers = require("ocaml.lsp.helpers")
local M = {}

---@class ocaml.commands.TypeEnclosingParams
---@field uri string Document URI
---@field at lsp.Position | lsp.Range Position or range to query
---@field index integer Index of enclosing to query (0 = innermost)
---@field verbosity? integer Number of alias expansions (optional)

---@class ocaml.commands.TypeEnclosingResponse
---@field enclosings lsp.Range[] Array of enclosing ranges
---@field index integer Index of the current enclosing
---@field type string Type as a string

-- State for the current type enclosing session
local current_state = {
  enclosings = nil, ---@type lsp.Range[]?
  index = 0,
  win = nil, ---@type integer?
  buf = nil, ---@type integer?
  ns_id = vim.api.nvim_create_namespace("ocaml_type_enclosing"),
}

---Clear all highlights
local function clear_highlights()
  if current_state.ns_id then
    vim.api.nvim_buf_clear_namespace(0, current_state.ns_id, 0, -1)
  end
end

---Close the floating window if it exists
local function close_window()
  if current_state.win and vim.api.nvim_win_is_valid(current_state.win) then
    vim.api.nvim_win_close(current_state.win, true)
    current_state.win = nil
    current_state.buf = nil
  end
  clear_highlights()
end

---Highlight a range in the buffer
---@param range lsp.Range
local function highlight_range(range)
  clear_highlights()
  if not range or not range.start or not range["end"] then
    return
  end

  -- Highlight the range
  vim.highlight.range(
    0,
    current_state.ns_id,
    "Visual",
    { range.start.line, range.start.character },
    { range["end"].line, range["end"].character },
    {}
  )
end

---Create or update the floating window with type information
---@param type_str string The type to display
---@param index integer Current index
---@param total integer Total number of enclosings
local function show_type_window(type_str, index, total)
  -- Split type string into lines (it may contain newlines)
  local type_lines = {}
  for line in type_str:gmatch("[^\r\n]+") do
    table.insert(type_lines, line)
  end

  -- Build the complete lines array
  local lines = {
    string.format("Type [%d/%d]:", index + 1, total),
    "",
  }

  -- Add type lines
  for _, line in ipairs(type_lines) do
    table.insert(lines, line)
  end

  -- Add footer
  table.insert(lines, "")
  table.insert(lines, "─────────────────────")
  table.insert(lines, "↑/K: Outer  ↓/J: Inner")
  table.insert(lines, "d: Delete  y: Yank  c: Change")
  table.insert(lines, "q/Esc: Close")

  -- Calculate window size
  local max_width = 0
  for _, line in ipairs(lines) do
    max_width = math.max(max_width, vim.fn.strdisplaywidth(line))
  end
  local width = math.min(max_width + 4, vim.o.columns - 4)
  local height = #lines

  -- Create buffer if it doesn't exist
  if not current_state.buf or not vim.api.nvim_buf_is_valid(current_state.buf) then
    current_state.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[current_state.buf].filetype = "ocaml"
  end

  -- Set buffer content (make sure it's modifiable first)
  vim.bo[current_state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(current_state.buf, 0, -1, false, lines)
  vim.bo[current_state.buf].modifiable = false

  -- Create or update window
  if not current_state.win or not vim.api.nvim_win_is_valid(current_state.win) then
    current_state.win = vim.api.nvim_open_win(current_state.buf, false, {
      relative = "cursor",
      width = width,
      height = height,
      row = 1,
      col = 0,
      style = "minimal",
      border = "rounded",
      title = " Type Enclosing ",
      title_pos = "center",
    })

    -- Set window options
    vim.wo[current_state.win].wrap = true
    vim.wo[current_state.win].linebreak = true
  else
    -- Update existing window size
    vim.api.nvim_win_set_config(current_state.win, {
      relative = "cursor",
      width = width,
      height = height,
      row = 1,
      col = 0,
    })
  end
end

---Query type enclosing at a specific index
---@param position lsp.Position
---@param index integer
---@param enclosings? lsp.Range[] Cached enclosings from previous query
local function query_type_enclosing(position, index, enclosings)
  ---@type ocaml.commands.TypeEnclosingParams
  local params = {
    uri = vim.uri_from_bufnr(0),
    at = position,
    index = index,
    verbosity = 0,
  }

  LspHelpers.buf_request(0, "ocamllsp/typeEnclosing", params, function(err, result)
    if err then
      vim.notify("[ocaml.nvim] Error requesting type enclosing: " .. err.message, vim.log.levels.ERROR)
      close_window()
      return
    end

    if not result or not result.type then
      vim.notify("[ocaml.nvim] No type information available", vim.log.levels.INFO)
      close_window()
      return
    end

    ---@cast result ocaml.commands.TypeEnclosingResponse

    -- Store enclosings if this is the first query
    if not enclosings then
      current_state.enclosings = result.enclosings
      current_state.index = index
    else
      current_state.enclosings = enclosings
      current_state.index = index
    end

    -- Show the type and highlight the range
    if current_state.enclosings and #current_state.enclosings > 0 then
      local current_range = current_state.enclosings[index + 1] -- Lua is 1-indexed
      if current_range then
        highlight_range(current_range)
      end
      show_type_window(result.type, index, #current_state.enclosings)
    end
  end)
end

---Move to the next outer enclosing (increase index)
local function next_enclosing()
  if not current_state.enclosings or #current_state.enclosings == 0 then
    return
  end

  local new_index = math.min(current_state.index + 1, #current_state.enclosings - 1)
  if new_index ~= current_state.index then
    local row, col = unpack(vim.api.nvim_win_get_cursor(0))
    query_type_enclosing({ line = row - 1, character = col }, new_index, current_state.enclosings)
  end
end

---Move to the next inner enclosing (decrease index)
local function prev_enclosing()
  if not current_state.enclosings or #current_state.enclosings == 0 then
    return
  end

  local new_index = math.max(current_state.index - 1, 0)
  if new_index ~= current_state.index then
    local row, col = unpack(vim.api.nvim_win_get_cursor(0))
    query_type_enclosing({ line = row - 1, character = col }, new_index, current_state.enclosings)
  end
end

---Apply an operator (delete, yank, change) to the current enclosing range
---@param operator string The operator to apply ('d', 'y', 'c')
local function apply_operator_to_current_range(operator)
  if not current_state.enclosings or #current_state.enclosings == 0 then
    return
  end

  local range = current_state.enclosings[current_state.index + 1]
  if not range or not range.start or not range["end"] then
    return
  end

  -- Close the window first
  close_window()

  -- Convert to 1-indexed positions for Neovim
  local start_line = range.start.line + 1
  local start_col = range.start.character + 1
  local end_line = range["end"].line + 1
  local end_col = range["end"].character + 1

  -- Move to start position
  vim.api.nvim_win_set_cursor(0, { start_line, start_col - 1 })

  -- Enter visual mode and select the range
  vim.cmd("normal! v")
  vim.api.nvim_win_set_cursor(0, { end_line, end_col - 1 })

  -- Apply the operator
  if operator == "d" then
    vim.cmd("normal! d")
  elseif operator == "y" then
    vim.cmd("normal! y")
  elseif operator == "c" then
    vim.cmd("normal! c")
  end
end

---Set up keybindings for navigating enclosings
local function setup_keybindings()
  local source_buf = vim.api.nvim_get_current_buf()
  local opts = { buffer = source_buf, nowait = true, silent = true }

  -- Store keymaps to be removed later
  local keymaps_to_remove = {}

  -- Helper to create removable keymap
  local function set_temp_keymap(mode, lhs, rhs)
    vim.keymap.set(mode, lhs, rhs, opts)
    table.insert(keymaps_to_remove, { mode = mode, lhs = lhs, buffer = source_buf })
  end

  -- Close window and remove keymaps
  local function close_and_cleanup()
    close_window()
    for _, map in ipairs(keymaps_to_remove) do
      pcall(vim.keymap.del, map.mode, map.lhs, { buffer = map.buffer })
    end
  end

  -- Close window
  set_temp_keymap("n", "q", close_and_cleanup)
  set_temp_keymap("n", "<Esc>", close_and_cleanup)

  -- Navigate enclosings
  set_temp_keymap("n", "<Up>", next_enclosing)
  set_temp_keymap("n", "K", next_enclosing)
  set_temp_keymap("n", "<Down>", prev_enclosing)
  set_temp_keymap("n", "J", prev_enclosing)

  -- Operators
  set_temp_keymap("n", "d", function()
    apply_operator_to_current_range("d")
    close_and_cleanup()
  end)
  set_temp_keymap("n", "y", function()
    apply_operator_to_current_range("y")
    close_and_cleanup()
  end)
  set_temp_keymap("n", "c", function()
    apply_operator_to_current_range("c")
    close_and_cleanup()
  end)

  -- Also set up autocmd to close on cursor move in source buffer
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "BufLeave" }, {
    buffer = source_buf,
    once = true,
    callback = close_and_cleanup,
  })
end

---Show type enclosing at cursor position
---@param opts? { verbosity?: integer }
function M.show_type_enclosing(opts)
  opts = opts or {} -- luacheck: ignore 311

  -- Close any existing window first
  close_window()

  -- Get cursor position
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local position = { line = row - 1, character = col }

  -- Query type enclosing starting at index 0 (innermost)
  query_type_enclosing(position, 0, nil)

  -- Set up keybindings after a short delay to ensure window is created
  vim.defer_fn(setup_keybindings, 50)
end

---Show type enclosing for a visual selection
function M.show_type_enclosing_range()
  -- Close any existing window first
  close_window()

  -- Get visual selection range
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")

  local range = {
    start = { line = start_pos[2] - 1, character = start_pos[3] - 1 },
    ["end"] = { line = end_pos[2] - 1, character = end_pos[3] - 1 },
  }

  ---@type ocaml.commands.TypeEnclosingParams
  local params = {
    uri = vim.uri_from_bufnr(0),
    at = range,
    index = 0,
    verbosity = 0,
  }

  LspHelpers.buf_request(0, "ocamllsp/typeEnclosing", params, function(err, result)
    if err then
      vim.notify("[ocaml.nvim] Error requesting type enclosing: " .. err.message, vim.log.levels.ERROR)
      return
    end

    if not result or not result.type then
      vim.notify("[ocaml.nvim] No type information available for selection", vim.log.levels.INFO)
      return
    end

    ---@cast result ocaml.commands.TypeEnclosingResponse

    current_state.enclosings = result.enclosings
    current_state.index = 0

    if current_state.enclosings and #current_state.enclosings > 0 then
      local current_range = current_state.enclosings[1]
      if current_range then
        highlight_range(current_range)
      end
      show_type_window(result.type, 0, #current_state.enclosings)
      vim.defer_fn(setup_keybindings, 50)
    end
  end)
end

return M
