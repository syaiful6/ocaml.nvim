if vim.fn.has("nvim-0.11") ~= 1 then
  vim.notify_once("ocaml.nvim requires Neovim 0.11 or above", vim.log.levels.ERROR)
  return
end

require("ocaml.internal").ftplugin()

--- Since user open reason file, we can go ahead and install Treesitter reason for them
vim.cmd.OCamlTS("instal_reason")
