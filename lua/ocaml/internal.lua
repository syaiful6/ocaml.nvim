---@type ocaml.Config
local OcamlConfig = require("ocaml.config.internal")

---@class ocaml.internal.Api
local M = {}

local function start_or_attach()
  local Types = require("ocaml.types.internal")
  if Types.evaluate(OcamlConfig.lsp.auto_attach) then
    ---TODO: start the LSP
  end
end

local function setup_formatter()
  local Types = require("ocaml.types.internal")
  if Types.can_require("conform") then
    local conform = require("conform")
    conform.formatters.ocamlformat_mlx = {
      inherit = false,
      command = "ocamlformat-mlx",
      args = { "--name", "$FILENAME", "--impl", "-" },
      stdin = true,
    }
  end
end

local function init()
  if vim.g.ocamlnvim_loaded then
    return
  end
  vim.g.ocamlnvim_loaded = true

  setup_formatter()

  --- Setup OCaml commands
  require("ocaml.commands").setup()
end

M.ftplugin = function()
  init()
  start_or_attach()
end

return M
