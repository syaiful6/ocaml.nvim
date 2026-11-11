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
---Whether resolution may pick this candidate automatically (default true).
---Candidates with `auto = false` are only listed, e.g. for a picker.
---@field auto? boolean

---@class ocaml.sandbox.Provider
---Unique provider name; also the prefix of the sandbox ids it produces.
---@field name string
---Detect candidate sandboxes for a project root, most preferred first. Call
---`cb` exactly once, with an empty list when nothing is found. Detection may
---finish synchronously.
---@field detect fun(root: string, cb: fun(candidates: ocaml.sandbox.Sandbox[]))
---Wrap `cmd` so it runs inside `sandbox`, or return nil if that is impossible.
---@field wrap fun(sandbox: ocaml.sandbox.Sandbox, cmd: string[]): string[]|nil
---Extra environment variables needed to use the sandbox's toolchain.
---@field env? fun(sandbox: ocaml.sandbox.Sandbox): table<string, string>|nil
---Drop any state the provider caches across project roots.
---@field reset? fun()

---@class ocaml.Sandbox
local M = {}

---The sandbox section of the plugin configuration.
---@return ocaml.sandbox.Config
function M.config()
  return require("ocaml.config.internal").sandbox
end

---Enabled providers in priority order, always ending with "global".
---@return string[]
function M.priority()
  local names = vim.deepcopy(M.config().providers)
  if not vim.tbl_contains(names, "global") then
    table.insert(names, "global")
  end
  return names
end

---Return the first candidate that resolution may pick automatically.
---@param candidates ocaml.sandbox.Sandbox[]
---@return ocaml.sandbox.Sandbox|nil
function M.first_auto(candidates)
  for _, candidate in ipairs(candidates) do
    if candidate.auto ~= false then
      return candidate
    end
  end
end

---@param name string
---@return ocaml.sandbox.Provider|nil
function M.get_provider(name)
  local ok, provider = pcall(require, "ocaml.sandbox.providers." .. name)
  if ok then
    return provider
  end
end

---Run providers in priority order and return the first automatic candidate.
---Stops at the first provider that has one; "global" always does.
---@param root string
---@param cb fun(sandbox: ocaml.sandbox.Sandbox)
local function detect_first(root, cb)
  local names = M.priority()
  local i = 0
  local function next_provider()
    i = i + 1
    local name = names[i]
    local provider = name and M.get_provider(name)
    if not name then
      -- Unreachable while "global" ends the list; never leave cb uncalled.
      return M.get_provider("global").detect(root, function(candidates)
        cb(candidates[1])
      end)
    elseif not provider then
      return next_provider()
    end

    provider.detect(root, function(candidates)
      local chosen = M.first_auto(candidates)
      if chosen then
        cb(chosen)
      else
        next_provider()
      end
    end)
  end
  next_provider()
end

---List every candidate sandbox for a project root, from every enabled
---provider, in priority order. Unlike `resolve`, this always runs all
---providers and is not cached.
---@param root string
---@param cb fun(candidates: ocaml.sandbox.Sandbox[])
function M.list(root, cb)
  local names = M.priority()
  local all = {}
  local i = 0
  local function next_provider()
    i = i + 1
    local name = names[i]
    if not name then
      return cb(all)
    end
    local provider = M.get_provider(name)
    if not provider then
      return next_provider()
    end
    provider.detect(root, function(candidates)
      vim.list_extend(all, candidates)
      next_provider()
    end)
  end
  next_provider()
end

---Apply the user's `resolve` hook to the candidates of a root.
---@param hook fun(root: string, candidates: ocaml.sandbox.Sandbox[]): ocaml.sandbox.Sandbox|string|nil
---@param root string
---@param candidates ocaml.sandbox.Sandbox[]
---@return ocaml.sandbox.Sandbox|nil chosen nil to keep the default choice
local function apply_hook(hook, root, candidates)
  local ok, choice = pcall(hook, root, vim.deepcopy(candidates))
  if not ok then
    vim.notify("[ocaml.nvim] sandbox.resolve failed: " .. tostring(choice), vim.log.levels.ERROR)
    return nil
  end
  if choice == nil then
    return nil
  end

  local id = type(choice) == "table" and choice.id or choice
  for _, candidate in ipairs(candidates) do
    if candidate.id == id then
      return candidate
    end
  end
  vim.notify(
    ("[ocaml.nvim] sandbox.resolve returned %s, which is not a candidate for %s; using the default"):format(
      vim.inspect(id),
      root
    ),
    vim.log.levels.WARN
  )
end

---Pick the sandbox for a root: the user's hook if it chooses one, otherwise
---the first automatic candidate in priority order.
---@param root string
---@param cb fun(sandbox: ocaml.sandbox.Sandbox)
local function detect(root, cb)
  local hook = M.config().resolve
  if not hook then
    return detect_first(root, cb)
  end

  M.list(root, function(candidates)
    -- "global" is always listed, so a default always exists.
    cb(apply_hook(hook, root, candidates) or M.first_auto(candidates) or candidates[#candidates])
  end)
end

---Resolved sandbox by project root.
---@type table<string, ocaml.sandbox.Sandbox>
local cache = {}

---Callbacks waiting for detection, by project root.
---@type table<string, fun(sandbox: ocaml.sandbox.Sandbox)[]>
local pending = {}

---Resolve and cache the sandbox for a project root.
---Concurrent calls for the same root share one detection. Cache hits invoke
---the callback synchronously.
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

---Clear cached state for `root`, or clear all sandbox and provider caches.
---In-flight detections still invoke their callbacks, but their results are not
---cached.
---@param root? string
function M.invalidate(root)
  if root then
    cache[root] = nil
    pending[root] = nil
    return
  end

  cache = {}
  pending = {}
  for _, name in ipairs(M.priority()) do
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
