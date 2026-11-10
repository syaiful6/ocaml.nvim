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
---Drop any state the provider caches across project roots.
---@field reset? fun()

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

---Run providers in priority order and return the first candidate.
---The "global" provider runs last and always matches.
---@param root string
---@param cb fun(sandbox: ocaml.sandbox.Sandbox)
local function detect(root, cb)
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

---Resolved sandbox by project root.
---@type table<string, ocaml.sandbox.Sandbox>
local cache = {}

---Callbacks waiting for detection, by project root.
---@type table<string, fun(sandbox: ocaml.sandbox.Sandbox)[]>
local pending = {}

---Resolve the sandbox to use for a project root.
---Cache the result until `invalidate` is called. Calls for the same root share
---one detection. `cb` runs synchronously on a cache hit.
---@param root string The project root
---@param cb fun(sandbox: ocaml.sandbox.Sandbox)
function M.resolve(root, cb)
  if cache[root] then
    return cb(cache[root])
  end

  if pending[root] then
    table.insert(pending[root], cb)
    return
  end

  local waiters = { cb }
  pending[root] = waiters
  detect(root, function(sandbox)
    -- Do not cache a result invalidated while detection was running.
    if pending[root] == waiters then
      pending[root] = nil
      cache[root] = sandbox
    end
    for _, waiter in ipairs(waiters) do
      waiter(sandbox)
    end
  end)
end

---Return the cached sandbox for a root without running detection.
---@param root string
---@return ocaml.sandbox.Sandbox|nil
function M.get_cached(root)
  return cache[root]
end

---Clear the cached sandbox for `root`. Without `root`, clear all sandboxes and
---provider caches. In-flight detections still call their waiters, but their
---results are not cached.
---@param root? string
function M.invalidate(root)
  if root then
    cache[root] = nil
    pending[root] = nil
    return
  end

  cache = {}
  pending = {}
  for _, name in ipairs(priority) do
    local provider = M.get_provider(name)
    if provider and provider.reset then
      provider.reset()
    end
  end
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
