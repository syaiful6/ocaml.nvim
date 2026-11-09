---@mod ocaml.sandbox
---
---@brief [[
---WARNING: This is not part of the public API. It may change without warning.
---Use at your own risk.
---
---A sandbox is an environment that provides the OCaml toolchain for a project
---(an opam switch, an esy project, ...). Each kind of sandbox is implemented by
---a provider. Providers detect candidate sandboxes for a project root and know
---how to wrap a command so it runs inside one of them.
---@brief ]]

---@class ocaml.sandbox.Sandbox
---Stable, serializable identifier, such as "opam:/path/to/proj", "esy:/path/esy.json", or "global".
---@field id string
---Name of the provider that detected this sandbox.
---@field provider string
---Human readable description, for pickers and messages.
---@field label string
---Project root where this sandbox was detected.
---@field root string
---Provider-specific data. Only the owning provider should read it.
---@field data table

---@class ocaml.sandbox.Provider
---Unique provider name; also the prefix of the sandbox ids it produces.
---@field name string
---Detect candidate sandboxes for a project root. Call `cb` exactly once with
---an empty list when nothing is found. Detection may finish synchronously.
---@field detect fun(root: string, cb: fun(candidates: ocaml.sandbox.Sandbox[]))
---Wrap `cmd` so it runs inside `sandbox`, or return nil if that is impossible.
---@field wrap fun(sandbox: ocaml.sandbox.Sandbox, cmd: string[]): string[]|nil
---Extra environment variables needed to use the sandbox's toolchain.
---@field env? fun(sandbox: ocaml.sandbox.Sandbox): table<string, string>|nil

---@class ocaml.Sandbox
local M = {}

---Provider priority. Resolution uses the first candidate found.
---@type string[]
local priority = { "esy", "opam", "global" }

---@param name string
---@return ocaml.sandbox.Provider|nil
function M.get_provider(name)
  local ok, provider = pcall(require, "ocaml.sandbox.providers." .. name)
  if ok then
    return provider
  end
end

---Resolve the sandbox to use for a project root.
---Providers are tried in priority order; the first candidate found is used.
---The "global" provider is last and always matches.
---@param root string The project root
---@param cb fun(sandbox: ocaml.sandbox.Sandbox)
function M.resolve(root, cb)
  local i = 0
  local function next_provider()
    i = i + 1
    local name = priority[i]
    if not name then
      -- Keep a fallback in case the priority list is changed.
      return M.get_provider("global").detect(root, function(candidates)
        cb(candidates[1])
      end)
    end

    local provider = M.get_provider(name)
    if not provider then
      return next_provider()
    end

    provider.detect(root, function(candidates)
      if candidates[1] then
        cb(candidates[1])
      else
        next_provider()
      end
    end)
  end
  next_provider()
end

---Wrap a command for the given sandbox.
---@param sandbox ocaml.sandbox.Sandbox
---@param cmd string[] e.g. { "dune", "build", "--watch" }
---@return string[]|nil cmd The wrapped command, or nil on failure
---@return string|nil err
function M.get_command(sandbox, cmd)
  local provider = M.get_provider(sandbox.provider)
  if not provider then
    return nil, "unknown sandbox provider: " .. sandbox.provider
  end
  local wrapped = provider.wrap(sandbox, cmd)
  if not wrapped then
    return nil, ("sandbox %s cannot run %s"):format(sandbox.id, table.concat(cmd, " "))
  end
  return wrapped
end

---Build the ocamllsp command for the given sandbox.
---@param sandbox ocaml.sandbox.Sandbox
---@param args? string[] Additional arguments for ocamllsp
---@return string[]|nil cmd
---@return string|nil err
function M.get_lsp_command(sandbox, args)
  local cmd = { "ocamllsp" }
  vim.list_extend(cmd, args or {})
  return M.get_command(sandbox, cmd)
end

return M
