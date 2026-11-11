---@mod ocaml.config.internal
---
---@brief [[
---
---WARNING: This is not part of the public API.
---It is subject to change without notice.
---This module contains internal configuration types used by the OCaml plugin.
---
---@brief ]]

---@class ocaml.Config ocaml.nvim plugin configuration
local OcamlDefaultConfig = {
  ---@class ocaml.lsp.ClientConfig ocaml language client options
  lsp = {
    ---@type boolean | (fun():boolean) Whether to automatically attach the LSP client.
    auto_attach = true,
    ---@type (fun(client:number,bufnr:number))
    on_attach = function(_, _) end,
    ---@type ocaml.lsp.Settings
    settings = {
      extendedHover = true,
      codelens = true,
      duneDiagnostics = true,
      inlayHints = true,
      syntaxDocumentation = true,
      merlinJumpCodeActions = true,
    },
  },
  ---@class ocaml.sandbox.Config
  sandbox = {
    ---Providers to use, in priority order. "global" is always the last resort.
    ---@type string[]
    providers = { "esy", "opam", "global" },
    ---@class ocaml.sandbox.opam.Config
    opam = {
      ---@type string
      binary = "opam",
      ---Opam root; nil means detect it with `opam var root`.
      ---@type string|nil
      root = nil,
    },
    ---@class ocaml.sandbox.esy.Config
    esy = {
      ---@type string
      binary = "esy",
    },
    ---Pick the sandbox for a project yourself. Receives every candidate found
    ---by the enabled providers; return one of them (or its id), or nil to
    ---keep the default choice.
    ---@type (fun(root: string, candidates: ocaml.sandbox.Sandbox[]): ocaml.sandbox.Sandbox|string|nil)|nil
    resolve = nil,
  },
}

---Providers that can be listed in `sandbox.providers`.
local KNOWN_PROVIDERS = { "esy", "opam", "global" }

---Validate the sandbox section of a merged config.
---@param sandbox table
---@return string|nil err
local function validate_sandbox(sandbox)
  local ok, err = pcall(function()
    vim.validate("sandbox.providers", sandbox.providers, "table")
    vim.validate("sandbox.opam", sandbox.opam, "table")
    vim.validate("sandbox.opam.binary", sandbox.opam.binary, "string")
    vim.validate("sandbox.opam.root", sandbox.opam.root, "string", true)
    vim.validate("sandbox.esy", sandbox.esy, "table")
    vim.validate("sandbox.esy.binary", sandbox.esy.binary, "string")
    vim.validate("sandbox.resolve", sandbox.resolve, "function", true)
  end)
  if not ok then
    return tostring(err)
  end

  local seen = {}
  for i, name in ipairs(sandbox.providers) do
    if not vim.tbl_contains(KNOWN_PROVIDERS, name) then
      return ("sandbox.providers[%d]: unknown provider %s (expected one of: %s)"):format(
        i,
        vim.inspect(name),
        table.concat(KNOWN_PROVIDERS, ", ")
      )
    end
    if seen[name] then
      return ("sandbox.providers[%d]: %s is listed twice"):format(i, name)
    end
    seen[name] = true
  end
end

---Merge user options into the defaults and validate them.
---Invalid sandbox options are reported and replaced by the defaults.
---@param opts ocaml.Opts|nil
---@return ocaml.Config
local function build(opts)
  local config = vim.tbl_deep_extend("force", OcamlDefaultConfig, opts or {})

  -- Lists are replaced, never merged by index (older Neovim versions merge them).
  local user_providers = vim.tbl_get(opts or {}, "sandbox", "providers")
  if user_providers ~= nil then
    config.sandbox.providers = user_providers
  end

  local err = validate_sandbox(config.sandbox)
  if err then
    -- Notify later: an error message raised while an ftplugin is being sourced
    -- becomes an exception that would abort loading the plugin.
    vim.schedule(function()
      vim.notify("[ocaml.nvim] Invalid configuration, using default sandbox options: " .. err, vim.log.levels.ERROR)
    end)
    config.sandbox = vim.deepcopy(OcamlDefaultConfig.sandbox)
  end
  return config
end

local ocamlnvim = vim.g.ocamlnvim or {}
---@type ocaml.Opts
local opts = type(ocamlnvim) == "function" and ocamlnvim() or ocamlnvim

---@type ocaml.Config
local M = build(opts)

return M
