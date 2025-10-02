local LspHelpers = require("ocaml.lsp.helpers")
local M = {}

---@type integer | nil
local latest_buf_id = nil

---@type lsp.Handler
local function handler(err, result)
  if err then
    vim.notify("[ocaml.nvim] Error requesting ppx expansion: " .. vim.inspect(err), vim.log.levels.ERROR)
    return
  end

  local ok, parsed = pcall(vim.json.decode, result and result.result or "")
  if not ok or parsed.class ~= "return" or not parsed.value or not parsed.value.code then
    if parsed.class == "return" then
      vim.notify("[ocaml.nvim] " .. parsed.value, vim.log.levels.WARN)
      return
    end
    vim.notify("[ocaml.nvim] Unexpected response from ocamllsp: " .. vim.inspect(parsed), vim.log.levels.ERROR)
    return
  end
  -- Extract the expansion and display it in a new buffer, the expanded code
  -- on code attribute
  local merlin_result = parsed.value

  if latest_buf_id and vim.api.nvim_buf_is_valid(latest_buf_id) then
    vim.api.nvim_buf_delete(latest_buf_id, { force = true })
  end

  -- Create a new buffer and set its content to the expansion
  latest_buf_id = vim.api.nvim_create_buf(false, true)
  -- Split the window and open the new buffer in it
  vim.cmd("vsplit")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, latest_buf_id)

  local lines = vim.split(merlin_result.code, "\n")
  vim.bo[latest_buf_id].filetype = "ocaml"
  vim.api.nvim_buf_set_lines(latest_buf_id, 0, -1, false, lines)
end

--- Expand the ppx at the current cursor position
function M.expand_ppx()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local params = {
    uri = vim.uri_from_bufnr(0),
    command = "expand-ppx",
    args = {
      "-position",
      row .. ":" .. col,
    },
    resultAsSexp = false,
  }
  LspHelpers.buf_request(0, "ocamllsp/merlinCallCompatible", params, handler)
end

return M
