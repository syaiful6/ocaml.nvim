---@mod ocaml.commands.dune
---@brief [[
---Dune build commands for OCaml development
---]]

local M = {}

function M.promote_file()
  if vim.bo.modified then
    vim.notify("[ocaml.nvim] Save file before trying to promote", vim.log.levels.WARN)
    return
  end

  local event = assert(vim.uv.new_fs_event())
  local path = vim.fn.expand("%:p")
  event:start(path, {}, function(err, _)
    event:stop()
    event:close()

    if err then
      vim.notify("[ocaml.nvim] File watcher error: " .. vim.inspect(err), vim.log.levels.ERROR)
      return
    end
    vim.defer_fn(vim.cmd.checktime, 100)
  end)

  vim.lsp.buf.code_action({
    filter = function(action)
      return string.find(action.title, "Promote") ~= nil
    end,
    apply = true,
    range = {
      ["start"] = { 0, 0 },
      ["end"] = { -1, -1 },
    },
  })
end

return M
