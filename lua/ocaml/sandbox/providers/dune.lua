---@mod ocaml.sandbox.providers.dune Dune package management sandbox provider
---
---@brief [[
---WARNING: This is not part of the public API. It may change without warning.
---Use at your own risk.
---
---A project is a dune sandbox when its dune workspace has a lock dir
---(`dune.lock/` by default) or enables package management with
---`(pkg enabled)` in `dune-workspace`, unless `(pkg disabled)` turns it off.
---
---Tools such as ocamllsp and ocamlformat are dune "dev tools", installed with
---`dune tools install <tool>`. They run directly from the directories that
---`dune tools env` reports, which works while `dune build --watch` holds the
---build lock (unlike `dune tools exec`) and starts without running dune.
---@brief ]]

local Dune = require("ocaml.sandbox.dune")

---@class ocaml.sandbox.dune.Data
---@field binary string The dune binary
---@field workspace string The dune workspace root
---@field lock_dir string Absolute path of the default context's lock dir; it may not exist yet
---@field version string|nil `dune --version`
---Dev tool directories from `dune tools env`; nil when that command failed.
---@field dirs string[]|nil

---@class ocaml.sandbox.providers.Dune: ocaml.sandbox.Provider
local M = {
  name = "dune",
}

---`dune --version` per binary; `false` when it failed.
---@type table<string, string|false>
local versions = {}

---Ask a yes/no question. Replaceable in tests.
---@param prompt string
---@param cb fun(yes: boolean)
function M.confirm(prompt, cb)
  vim.ui.select({ "Yes", "No" }, { prompt = prompt }, function(choice)
    cb(choice == "Yes")
  end)
end

---@param binary string
---@param cb fun(version: string|nil)
local function get_version(binary, cb)
  if versions[binary] ~= nil then
    return cb(versions[binary] or nil)
  end
  Dune.get_version(binary, function(version)
    versions[binary] = version or false
    cb(version)
  end)
end

---Lock dir path for messages, relative to the workspace when inside it.
---@param data ocaml.sandbox.dune.Data
---@return string
local function lock_dir_name(data)
  local rel = vim.fs.relpath and vim.fs.relpath(data.workspace, data.lock_dir)
  return rel or vim.fn.fnamemodify(data.lock_dir, ":~")
end

---Set the label and note of a usable candidate from its lock dir's state.
---@param candidate ocaml.sandbox.Sandbox
local function describe(candidate)
  ---@type ocaml.sandbox.dune.Data
  local data = candidate.data
  local dune = "dune" .. (data.version and " " .. data.version or "")
  if vim.fn.isdirectory(data.lock_dir) == 1 then
    candidate.label = "dune pkg " .. lock_dir_name(data)
    candidate.note = ("dune package management, lock dir %s (%s)"):format(lock_dir_name(data), dune)
  else
    candidate.label = "dune pkg (not locked)"
    candidate.note = ("package management is enabled, but %s does not exist yet (%s)"):format(lock_dir_name(data), dune)
  end
end

function M.detect(root, cb)
  local binary = require("ocaml.config.internal").sandbox.dune.binary
  if vim.fn.executable(binary) == 0 then
    return cb({})
  end

  local workspace = Dune.workspace_root(root)
  local settings = Dune.read_workspace(workspace)
  if settings.pkg == "disabled" then
    return cb({})
  end
  local lock_dir = vim.fs.normalize(vim.fs.joinpath(workspace, settings.lock_dir))
  local locked = vim.fn.isdirectory(lock_dir) == 1
  if not locked and settings.pkg ~= "enabled" then
    return cb({})
  end

  get_version(binary, function(version)
    Dune.get_tools_env(binary, workspace, function(env)
      ---@type ocaml.sandbox.dune.Data
      local data = { binary = binary, workspace = workspace, lock_dir = lock_dir, version = version, dirs = env.dirs }
      ---@type ocaml.sandbox.Sandbox
      local candidate = { id = "dune:" .. workspace, provider = M.name, label = "", root = root, data = data }
      describe(candidate)
      if env.unsupported then
        candidate.auto = false
        candidate.note = ("dune%s has no `dune tools`; upgrade dune to use its package management"):format(
          version and " " .. version or ""
        )
      elseif not env.dirs then
        candidate.auto = false
        candidate.note = ("`dune tools env` failed: %s"):format(env.err or "unknown error")
      end

      if env.dirs then
        M.watch(data)
      end
      cb({ candidate })
    end)
  end)
end

function M.find_executable(sandbox, name)
  for _, dir in ipairs(sandbox.data.dirs or {}) do
    local path = vim.fs.joinpath(dir, name)
    if vim.fn.executable(path) == 1 then
      return path
    end
  end
end

---Dev tools run from their dune-installed path; other commands (dune
---itself, ocamlfind, ...) run unchanged with `env()` applied by the caller.
function M.wrap(sandbox, cmd)
  local path = M.find_executable(sandbox, cmd[1])
  if path then
    local wrapped = vim.deepcopy(cmd)
    wrapped[1] = path
    return wrapped
  end
  if Dune.INSTALLABLE[cmd[1]] then
    -- Falling back to PATH would mix toolchains; ensure_tool offers to install it.
    return nil
  end
  return vim.deepcopy(cmd)
end

---PATH with the dev tool directories first, so that ocamllsp finds the
---project's ocamlformat and commands find the project's tools.
function M.env(sandbox)
  local dirs = sandbox.data.dirs
  if not dirs or #dirs == 0 then
    return nil
  end
  local sep = vim.fn.has("win32") == 1 and ";" or ":"
  local path = table.concat(dirs, sep)
  if vim.env.PATH and vim.env.PATH ~= "" then
    path = path .. sep .. vim.env.PATH
  end
  return { PATH = path }
end

---Offers made this session, by workspace and action. A declined or failed
---offer is not repeated until `reset()` (`:OCaml sandbox refresh`).
---@type table<string, { state: "pending"|"declined", waiters: fun(ok: boolean)[] }>
local offers = {}

---Ask once whether to run an action, and run it if accepted. Concurrent
---calls with the same key share one question and one run.
---@param key string
---@param prompt string
---@param run fun(done: fun(ok: boolean))
---@param cb fun(ok: boolean)
local function offer(key, prompt, run, cb)
  local current = offers[key]
  if current then
    if current.state == "declined" then
      return cb(false)
    end
    table.insert(current.waiters, cb)
    return
  end

  local entry = { state = "pending", waiters = { cb } }
  offers[key] = entry
  local function finish(ok)
    if offers[key] == entry then
      offers[key] = not ok and { state = "declined", waiters = {} } or nil
    end
    for _, waiter in ipairs(entry.waiters) do
      waiter(ok)
    end
  end

  vim.schedule(function()
    M.confirm(prompt, function(yes)
      if yes then
        run(finish)
      else
        finish(false)
      end
    end)
  end)
end

---@param data ocaml.sandbox.dune.Data
---@param name string
---@return string
local function not_installed(data, name)
  return ("%s is not installed for %s. Run `dune tools install %s` there, then :OCaml lsp restart (or :OCaml sandbox refresh to be asked again)"):format(
    name,
    vim.fn.fnamemodify(data.workspace, ":~"),
    name
  )
end

---Make `name` available: offer `dune pkg lock` when the lock dir is
---missing, then `dune tools install <name>` when the tool is missing.
---@param sandbox ocaml.sandbox.Sandbox
---@param name string
---@param cb fun(ok: boolean, err: string|nil)
function M.ensure_tool(sandbox, name, cb)
  ---@type ocaml.sandbox.dune.Data
  local data = sandbox.data
  if not data.dirs then
    return cb(false, ("%s cannot run %s: %s"):format(sandbox.label, name, sandbox.note or "dune tools are unavailable"))
  end

  local function check_tool()
    if M.find_executable(sandbox, name) then
      return cb(true)
    end
    if not Dune.INSTALLABLE[name] then
      return cb(false, ("%s is not a dune dev tool"):format(name))
    end
    offer(
      data.workspace .. "\0install:" .. name,
      ("%s is not installed for this project (%s). Run `dune tools install %s`?"):format(
        name,
        vim.fn.fnamemodify(data.workspace, ":~"),
        name
      ),
      function(done)
        Dune.run_job(data.binary, data.workspace, { "tools", "install", name }, function(ok)
          done(ok and M.find_executable(sandbox, name) ~= nil)
        end)
      end,
      function(ok)
        cb(ok, not ok and not_installed(data, name) or nil)
      end
    )
  end

  if vim.fn.isdirectory(data.lock_dir) == 1 then
    return check_tool()
  end
  offer(
    data.workspace .. "\0lock",
    ("Package management is enabled in %s, but %s does not exist. Run `dune pkg lock`?"):format(
      vim.fn.fnamemodify(data.workspace, ":~"),
      lock_dir_name(data)
    ),
    function(done)
      Dune.run_job(data.binary, data.workspace, { "pkg", "lock" }, function(ok)
        done(ok and vim.fn.isdirectory(data.lock_dir) == 1)
      end)
    end,
    function(ok)
      if ok then
        -- The cached candidate is shown by :OCaml sandbox info.
        describe(sandbox)
        return check_tool()
      end
      cb(false, ("%s has no lock dir; run `dune pkg lock` there"):format(vim.fn.fnamemodify(data.workspace, ":~")))
    end
  )
end

---How long to wait for the lock dir to settle after a change, in ms.
M.WATCH_DEBOUNCE = 500

---@class ocaml.sandbox.dune.Watcher
---@field data ocaml.sandbox.dune.Data
---@field outer uv.uv_fs_event_t|nil Watches the lock dir's parent; dune replaces the lock dir
---@field inner uv.uv_fs_event_t|nil Watches inside the lock dir, for in-place edits (e.g. git checkout)
---@field timer uv.uv_timer_t|nil
---@field stamp string|nil
---@field prompting boolean

---Lock dir watchers by workspace.
---@type table<string, ocaml.sandbox.dune.Watcher>
local watchers = {}

---Identity of the lock file's current contents.
---@param lock_dir string
---@return string|nil
local function lock_stamp(lock_dir)
  local stat = vim.uv.fs_stat(vim.fs.joinpath(lock_dir, "lock.dune"))
  if not stat then
    return nil
  end
  return ("%d:%d:%d:%d"):format(stat.ino, stat.mtime.sec, stat.mtime.nsec, stat.size)
end

---@param handle uv.uv_fs_event_t|uv.uv_timer_t|nil
local function close(handle)
  if handle and not handle:is_closing() then
    handle:close()
  end
end

---Running ocamllsp clients whose root is inside a workspace.
---@param workspace string
---@return vim.lsp.Client[]
local function clients_in(workspace)
  return vim.tbl_filter(function(client)
    local root = vim.fs.normalize(client.config.root_dir or "")
    return not client:is_stopped() and (root == workspace or vim.startswith(root, workspace .. "/"))
  end, require("ocaml.lsp.helpers").get_active_lsp_clients())
end

---Rebuild installed dev tools against the new lock dir, then restart the
---workspace's ocamllsp clients.
---@param watcher ocaml.sandbox.dune.Watcher
local function rebuild_and_restart(watcher)
  local data = watcher.data
  local sandbox = { data = data }
  local tools = {}
  for _, name in ipairs({ "ocamllsp", "ocamlformat" }) do
    if M.find_executable(sandbox, name) then
      table.insert(tools, name)
    end
  end

  local i = 0
  local function next_tool()
    i = i + 1
    if tools[i] then
      -- `dune tools install` re-locks and rebuilds a tool whose compiler changed.
      return Dune.run_job(data.binary, data.workspace, { "tools", "install", tools[i] }, function(ok)
        if ok then
          next_tool()
        end
      end)
    end
    for _, client in ipairs(clients_in(data.workspace)) do
      local buf = next(client.attached_buffers)
      if buf then
        require("ocaml.lsp").restart(buf)
      end
    end
  end
  next_tool()
end

---React to a (settled) change of a workspace's lock dir.
---@param workspace string
function M.on_lock_changed(workspace)
  local watcher = watchers[workspace]
  if not watcher then
    return
  end
  M.watch_inner(watcher)

  local stamp = lock_stamp(watcher.data.lock_dir)
  if stamp == watcher.stamp then
    return
  end
  watcher.stamp = stamp
  if stamp == nil or watcher.prompting or #clients_in(workspace) == 0 then
    return
  end

  watcher.prompting = true
  M.confirm(
    ("%s changed in %s. Rebuild dev tools and restart ocamllsp?"):format(
      lock_dir_name(watcher.data),
      vim.fn.fnamemodify(workspace, ":~")
    ),
    function(yes)
      watcher.prompting = false
      if yes then
        rebuild_and_restart(watcher)
      end
    end
  )
end

---@param watcher ocaml.sandbox.dune.Watcher
local function schedule_check(watcher)
  local workspace = watcher.data.workspace
  if not watcher.timer then
    watcher.timer = vim.uv.new_timer()
  end
  if not watcher.timer then
    return
  end
  watcher.timer:stop()
  watcher.timer:start(
    M.WATCH_DEBOUNCE,
    0,
    vim.schedule_wrap(function()
      M.on_lock_changed(workspace)
    end)
  )
end

---(Re)start watching the inside of the lock dir. dune replaces the directory
---when it re-locks, so the handle is renewed after every change.
---@param watcher ocaml.sandbox.dune.Watcher
function M.watch_inner(watcher)
  close(watcher.inner)
  watcher.inner = nil
  if vim.fn.isdirectory(watcher.data.lock_dir) == 0 then
    return
  end
  local handle = vim.uv.new_fs_event()
  if handle and handle:start(watcher.data.lock_dir, {}, function()
    schedule_check(watcher)
  end) then
    watcher.inner = handle
  else
    close(handle)
  end
end

---Watch a workspace's lock dir, once per workspace. When it changes while
---ocamllsp runs there, offer to rebuild the dev tools and restart it.
---@param data ocaml.sandbox.dune.Data
function M.watch(data)
  if watchers[data.workspace] then
    -- Keep the newest data (e.g. dev tool directories).
    watchers[data.workspace].data = data
    return
  end
  ---@type ocaml.sandbox.dune.Watcher
  local watcher = { data = data, stamp = lock_stamp(data.lock_dir), prompting = false }
  watchers[data.workspace] = watcher

  local parent = vim.fs.dirname(data.lock_dir)
  local base = vim.fs.basename(data.lock_dir)
  local handle = vim.uv.new_fs_event()
  if
    handle
    and vim.fn.isdirectory(parent) == 1
    and handle:start(parent, {}, function(_, filename)
      if filename == base then
        schedule_check(watcher)
      end
    end)
  then
    watcher.outer = handle
  else
    close(handle)
  end
  M.watch_inner(watcher)
end

---Workspaces whose lock dir is watched, for tests and diagnostics.
---@return string[]
function M.watched()
  return vim.tbl_keys(watchers)
end

function M.reset()
  versions = {}
  offers = {}
  for _, watcher in pairs(watchers) do
    close(watcher.outer)
    close(watcher.inner)
    close(watcher.timer)
  end
  watchers = {}
end

return M
