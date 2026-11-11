---@mod ocaml.api.sandbox Run commands inside a project's sandbox
---
---@brief [[
---Public API, available as `require("ocaml").sandbox`.
---
---Commands run in the same sandbox (opam switch, esy project, ...) as the
---project's language server, e.g. to call `ocamlformat` or `dune` with the
---project's toolchain:
--->lua
---  local sandbox = require("ocaml").sandbox
---
---  sandbox.run({ "dune", "build" }, {}, function(result, err)
---    if err then
---      return vim.notify(err, vim.log.levels.ERROR)
---    end
---    print(result.code, result.stdout)
---  end)
---<
---
---The project is found from `opts.root` when given, otherwise from
---`opts.bufnr` (default: the current buffer), using the same root markers as
---the language server. Sandbox detection is cached per project, shared with
---the language server.
---@brief ]]

---@class ocaml.api.sandbox
local M = {}

---@class ocaml.api.sandbox.Opts
---Buffer whose project to use. Default: the current buffer.
---@field bufnr? integer
---Project root to use instead of a buffer's.
---@field root? string

---@class ocaml.api.sandbox.Info
---Stable identifier, e.g. "opam:/path/to/project", "opam:5.2.0", "global".
---@field id string
---Provider name: "opam", "esy" or "global".
---@field provider string
---Human readable description.
---@field label string
---Project root the sandbox was resolved for.
---@field root string

---@param opts ocaml.api.sandbox.Opts|nil
---@return string root
local function project_root(opts)
  opts = opts or {}
  if opts.root then
    return vim.fs.normalize(opts.root)
  end
  local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
  if vim.api.nvim_buf_get_name(bufnr) == "" then
    -- Unnamed buffer: nothing to search from, use the working directory.
    return vim.fs.normalize(vim.fn.getcwd())
  end
  return (require("ocaml.lsp").find_root(bufnr))
end

---@param sandbox ocaml.sandbox.Sandbox
---@return ocaml.api.sandbox.Info
local function to_info(sandbox)
  return { id = sandbox.id, provider = sandbox.provider, label = sandbox.label, root = sandbox.root }
end

---@param cmd any
---@return string|nil err
local function check_cmd(cmd)
  if type(cmd) ~= "table" or #cmd == 0 then
    return "cmd must be a non-empty list of strings"
  end
  for i, arg in ipairs(cmd) do
    if type(arg) ~= "string" then
      return ("cmd[%d] must be a string, got %s"):format(i, type(arg))
    end
  end
end

---Get the sandbox used for a project.
---`cb` runs synchronously when the sandbox is already known.
---@param opts ocaml.api.sandbox.Opts|nil
---@param cb fun(info: ocaml.api.sandbox.Info)
function M.get(opts, cb)
  require("ocaml.sandbox").resolve(project_root(opts), function(sandbox)
    cb(to_info(sandbox))
  end)
end

---Wrap a command so it runs inside the project's sandbox, e.g.
---`{ "dune", "build" }` → `{ "opam", "exec", "--switch=...", "--", "dune", "build" }`.
---`cb` runs synchronously when the sandbox is already known.
---@param cmd string[]
---@param opts ocaml.api.sandbox.Opts|nil
---@param cb fun(cmd: string[]|nil, err: string|nil)
function M.get_command(cmd, opts, cb)
  local err = check_cmd(cmd)
  if err then
    return cb(nil, err)
  end
  local Sandbox = require("ocaml.sandbox")
  Sandbox.resolve(project_root(opts), function(sandbox)
    cb(Sandbox.get_command(sandbox, cmd))
  end)
end

---@class ocaml.api.sandbox.SyncOpts: ocaml.api.sandbox.Opts
---How long to wait for sandbox detection, in milliseconds. Default: 10000.
---@field timeout? integer

---Synchronous `get_command`, for callers that cannot take a callback (e.g. a
---formatter's `command` function). Returns at once when the sandbox is
---already known, which is the usual case once the language server started;
---otherwise blocks the editor until detection finishes or times out.
---Must not be called from a `vim.uv`/`vim.system` callback.
---@param cmd string[]
---@param opts ocaml.api.sandbox.SyncOpts|nil
---@return string[]|nil cmd
---@return string|nil err
function M.get_command_sync(cmd, opts)
  opts = opts or {}
  local done, result, err = false, nil, nil
  M.get_command(cmd, opts, function(c, e)
    done, result, err = true, c, e
  end)
  if not done then
    local timeout = opts.timeout or 10000
    if not vim.wait(timeout, function()
      return done
    end, 10) then
      return nil, ("sandbox detection did not finish within %d ms"):format(timeout)
    end
  end
  return result, err
end

---@class ocaml.api.sandbox.RunOpts: ocaml.api.sandbox.Opts, vim.SystemOpts
---Working directory. Default: the project root.
---@field cwd? string

---Run a command inside the project's sandbox with `vim.system`.
---All `vim.system` options are accepted. `on_exit` is called on the main
---loop, so it may use any API; it receives `nil` and an error message when
---the command could not be started.
---@param cmd string[]
---@param opts ocaml.api.sandbox.RunOpts|nil
---@param on_exit fun(result: vim.SystemCompleted|nil, err: string|nil)
function M.run(cmd, opts, on_exit)
  opts = opts or {}
  local cmd_err = check_cmd(cmd)
  if cmd_err then
    return vim.schedule(function()
      on_exit(nil, cmd_err)
    end)
  end

  local root = project_root(opts)
  local Sandbox = require("ocaml.sandbox")

  Sandbox.resolve(root, function(sandbox)
    local wrapped, err = Sandbox.get_command(sandbox, cmd)
    if not wrapped then
      return vim.schedule(function()
        on_exit(nil, err)
      end)
    end

    local system_opts = vim.tbl_extend("force", { text = true }, opts, { cwd = opts.cwd or root })
    system_opts.bufnr, system_opts.root = nil, nil
    system_opts.env = vim.tbl_extend("force", Sandbox.get_env(sandbox) or {}, opts.env or {})
    if vim.tbl_isempty(system_opts.env) then
      system_opts.env = nil
    end

    local ok, spawn_err = pcall(vim.system, wrapped, system_opts, function(result)
      vim.schedule(function()
        on_exit(result, nil)
      end)
    end)
    if not ok then
      vim.schedule(function()
        on_exit(nil, tostring(spawn_err))
      end)
    end
  end)
end

return M
