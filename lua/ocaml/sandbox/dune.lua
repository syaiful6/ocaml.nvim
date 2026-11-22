---@mod ocaml.sandbox.dune Dune package management operations
---
---@brief [[
---WARNING: This is not part of the public API. It may change without warning.
---Use at your own risk.
---
---Helpers for projects that use dune's package management (`dune pkg`):
---finding the workspace and its lock dir, reading the dev tool directories
---from `dune tools env`, and running dune jobs one at a time per workspace.
---
---Only commands that do not take dune's build lock are used for detection:
---`dune pkg enabled` reports "disabled" while `dune build --watch` runs, and
---`dune tools exec` fails then, so neither is used.
---@brief ]]

local Helpers = require("ocaml.helpers")

local M = {}

---How long detection commands may run, in milliseconds.
M.TIMEOUT = 10000

---Dev tools that `dune tools install <name>` can install, by executable name.
M.INSTALLABLE = {
  ocamllsp = true,
  ocamlformat = true,
  ocamlmerlin = true,
  ["ocaml-index"] = true,
  odoc = true,
  odig = true,
  utop = true,
  ocamlearlybird = true,
  ["dune-release"] = true,
  ["opam-publish"] = true,
}

---Default lock dir of the default build context.
M.DEFAULT_LOCK_DIR = "dune.lock"

---Outermost ancestor of `dir` (or `dir` itself) containing `file`.
---`Helpers.root_pattern` stops at the nearest match, so keep searching
---from the parent of each match.
---@param dir string
---@param file string
---@return string|nil
local function outermost(dir, file)
  local match = Helpers.root_pattern(file)
  local found
  local current = match(dir)
  while current do
    found = current
    local parent = vim.fs.dirname(current)
    if parent == current then
      break
    end
    current = match(parent)
  end
  return found
end

---Find the root dune would use for `dir`: the outermost directory containing
---a `dune-workspace`, otherwise the outermost one containing a
---`dune-project`, otherwise `dir` itself.
---@param dir string
---@return string
function M.workspace_root(dir)
  dir = vim.fs.normalize(dir)
  return outermost(dir, "dune-workspace") or outermost(dir, "dune-project") or dir
end

---Remove `;` line comments from dune file contents.
---@param text string
---@return string
local function strip_comments(text)
  local lines = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do
    -- A ";" inside a string would be cut too; acceptable for the stanzas read here.
    table.insert(lines, (line:gsub(";.*$", "")))
  end
  return table.concat(lines, "\n")
end

---@class ocaml.sandbox.dune.Workspace
---`(pkg enabled)` / `(pkg disabled)` in `dune-workspace`, if present.
---@field pkg "enabled"|"disabled"|nil
---Lock dir of the default context, relative to the workspace root.
---@field lock_dir string

---Parse the parts of a `dune-workspace` file that matter for detection.
---This is a best-effort reader, not a full s-expression parser.
---@param text string
---@return ocaml.sandbox.dune.Workspace
function M.parse_workspace(text)
  text = strip_comments(text)
  local pkg = text:match("%(%s*pkg%s+(%a+)%s*%)")
  if pkg ~= "enabled" and pkg ~= "disabled" then
    pkg = nil
  end
  -- `(context (default (lock_dir foo.lock)))` names the lock dir with an
  -- atom. The top-level `(lock_dir (path ...) ...)` stanza configures a lock
  -- dir but does not make the default context use it, so it is skipped.
  local lock_dir = text:match('%(%s*lock_dir%s+"([^"]+)"%s*%)') or text:match('%(%s*lock_dir%s+([^%s%(%)"]+)%s*%)')
  return { pkg = pkg, lock_dir = lock_dir or M.DEFAULT_LOCK_DIR }
end

---Read the `dune-workspace` of a workspace root, if it has one.
---@param workspace string
---@return ocaml.sandbox.dune.Workspace
function M.read_workspace(workspace)
  local path = vim.fs.joinpath(workspace, "dune-workspace")
  local fd = io.open(path, "r")
  if not fd then
    return { lock_dir = M.DEFAULT_LOCK_DIR }
  end
  local text = fd:read("*a") or ""
  fd:close()
  return M.parse_workspace(text)
end

---Parse the output of `dune tools env` (POSIX shell form) into the
---directories it adds to PATH, i.e. the entries not already in `path`.
---@param output string e.g. "export PATH=/a/bin:/b/bin:$PATH-at-call-time"
---@param path? string The PATH dune was started with. Default: `vim.env.PATH`.
---@return string[]|nil dirs nil when the output has no PATH export
function M.parse_tools_env(output, path)
  local value
  for line in (output .. "\n"):gmatch("(.-)\n") do
    value = line:match("^%s*export%s+PATH=(.*)$") or value
  end
  if not value then
    return nil
  end
  value = vim.trim(value)
  local quote = value:sub(1, 1)
  if (quote == "'" or quote == '"') and value:sub(-1) == quote then
    value = value:sub(2, -2)
  end

  local sep = vim.fn.has("win32") == 1 and ";" or ":"
  local existing = {}
  for _, entry in ipairs(vim.split(path or vim.env.PATH or "", sep, { plain = true })) do
    existing[entry] = true
  end

  local dirs = {}
  for _, entry in ipairs(vim.split(value, sep, { plain = true, trimempty = true })) do
    if not existing[entry] and not vim.tbl_contains(dirs, entry) then
      table.insert(dirs, entry)
    end
  end
  return dirs
end

---Whether dune's stderr says a subcommand does not exist.
---@param stderr string
---@return boolean
function M.is_unknown_command(stderr)
  return stderr:lower():find("unknown command", 1, true) ~= nil
end

---Last non-empty lines of a command's output, for error messages.
---@param text string|nil
---@param n? integer Default: 5.
---@return string
function M.tail(text, n)
  local lines = vim.split(text or "", "\n", { trimempty = true })
  return table.concat(vim.list_slice(lines, math.max(1, #lines - (n or 5) + 1)), "\n")
end

---Run a command, calling `cb` on the main loop. Never throws.
---@param cmd string[]
---@param opts vim.SystemOpts
---@param cb fun(result: vim.SystemCompleted)
function M.system(cmd, opts, cb)
  local ok, err = pcall(vim.system, cmd, vim.tbl_extend("force", { text = true }, opts), function(result)
    vim.schedule(function()
      cb(result)
    end)
  end)
  if not ok then
    vim.schedule(function()
      cb({ code = -1, signal = 0, stdout = "", stderr = tostring(err) })
    end)
  end
end

---`dune --version`, e.g. "3.24.2" (any "+suffix" kept), or nil.
---@param binary string
---@param cb fun(version: string|nil)
function M.get_version(binary, cb)
  M.system({ binary, "--version" }, { timeout = M.TIMEOUT }, function(result)
    local version = result.code == 0 and vim.trim(result.stdout or "") or ""
    cb(version ~= "" and version or nil)
  end)
end

---@class ocaml.sandbox.dune.ToolsEnv
---@field dirs string[]|nil Dev tool directories; nil on failure
---@field unsupported? boolean This dune has no `dune tools env`
---@field err? string Why the command failed

---Run `dune tools env` in a workspace. It does not take the build lock.
---@param binary string
---@param workspace string
---@param cb fun(env: ocaml.sandbox.dune.ToolsEnv)
function M.get_tools_env(binary, workspace, cb)
  M.system({ binary, "tools", "env" }, { cwd = workspace, timeout = M.TIMEOUT }, function(result)
    local stderr = result.stderr or ""
    if result.code ~= 0 then
      return cb({ unsupported = M.is_unknown_command(stderr), err = M.tail(stderr, 3) })
    end
    local dirs = M.parse_tools_env(result.stdout or "")
    if not dirs then
      return cb({ err = "unexpected output from `dune tools env`" })
    end
    cb({ dirs = dirs })
  end)
end

---Show progress for a long-running job. Uses Neovim 0.12 progress messages
---when available, plain notifications otherwise.
---@param title string
---@return fun(msg: string, status: "running"|"success"|"failed")
function M.progress(title)
  local id
  return function(msg, status)
    if vim.fn.has("nvim-0.12") == 1 then
      local ok, new_id = pcall(vim.api.nvim_echo, { { msg } }, true, {
        id = id,
        kind = "progress",
        status = status,
        title = title,
        source = "ocaml.nvim",
      })
      if ok then
        id = new_id
        if status == "failed" then
          -- Progress messages are easy to miss; make failures stand out.
          vim.notify("[ocaml.nvim] " .. msg, vim.log.levels.ERROR)
        end
        return
      end
    end
    local level = status == "failed" and vim.log.levels.ERROR or vim.log.levels.INFO
    vim.notify(("[ocaml.nvim] %s: %s"):format(title, msg), level)
  end
end

---Queued jobs per workspace. dune holds a lock on the build directory, so
---jobs in one workspace must not overlap.
---@type table<string, { running: boolean, jobs: fun(done: fun())[] }>
local queues = {}

---Run `dune <args>` in a workspace after any job already queued there,
---reporting progress. `cb` runs on the main loop.
---@param binary string
---@param workspace string
---@param args string[] e.g. { "tools", "install", "ocamllsp" }
---@param cb fun(ok: boolean, result: vim.SystemCompleted)
function M.run_job(binary, workspace, args, cb)
  local queue = queues[workspace] or { running = false, jobs = {} }
  queues[workspace] = queue

  local function next_job()
    local job = table.remove(queue.jobs, 1)
    if not job then
      queue.running = false
      return
    end
    queue.running = true
    job(next_job)
  end

  table.insert(queue.jobs, function(done)
    local cmd = vim.list_extend({ binary }, args)
    local line = table.concat(cmd, " ")
    local report = M.progress("dune")
    report(("running `%s` in %s"):format(line, vim.fn.fnamemodify(workspace, ":~")), "running")
    M.system(cmd, { cwd = workspace }, function(result)
      if result.code == 0 then
        report(("`%s` finished"):format(line), "success")
      else
        local output = M.tail(result.stderr ~= "" and result.stderr or result.stdout)
        report(
          ("`%s` failed (exit code %d)%s"):format(line, result.code, output ~= "" and ":\n" .. output or ""),
          "failed"
        )
      end
      cb(result.code == 0, result)
      done()
    end)
  end)

  if not queue.running then
    next_job()
  end
end

return M
