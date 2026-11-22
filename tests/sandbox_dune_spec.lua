-- Dune package management provider: workspace parsing, detection against
-- fixture projects in tests/fixtures/dune, command building, the install /
-- lock offers, and the lock dir watcher. `vim.system` is stubbed
-- (tests/helpers/system.lua); file system state is real.

local system = require("tests.helpers.system")

local fixtures = vim.fs.normalize(assert(vim.uv.fs_realpath("tests/fixtures/dune")))

local MODULES = { "ocaml.sandbox", "ocaml.sandbox.dune", "ocaml.sandbox.providers.dune" }

---Dev tool directory reported by the stubbed `dune tools env`.
local DEV_BIN = "/fake/_build/_private/default/.dev-tool/ocaml-lsp-server/target/bin"

---@param sandbox_config table|nil merged over the defaults
local function configure(sandbox_config)
  package.loaded["ocaml.config.internal"] = {
    sandbox = vim.tbl_deep_extend("force", {
      providers = { "dune", "esy", "opam", "global" },
      opam = { binary = "opam" },
      esy = { binary = "esy" },
      dune = { binary = "dune" },
    }, sandbox_config or {}),
  }
  for _, name in ipairs(MODULES) do
    package.loaded[name] = nil
  end
end

---@param names table<string, boolean>
---@return fun() restore
local function fake_executables(names)
  local original = vim.fn.executable
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.fn.executable = function(path)
    if names[path] ~= nil then
      return names[path] and 1 or 0
    end
    return original(path)
  end
  return function()
    vim.fn.executable = original
  end
end

---Responses for a working dune 3.24.2 whose dev tools live in `dirs`.
---@param dirs? string[]
---@return table<string, tests.SystemResponse>
local function dune_responses(dirs)
  local path = table.concat(dirs or { DEV_BIN }, ":") .. ":" .. (vim.env.PATH or "")
  return {
    ["dune --version"] = { stdout = "3.24.2\n" },
    ["dune tools env"] = { stdout = "export PATH=" .. path .. "\n" },
  }
end

---@param provider ocaml.sandbox.Provider
---@param root string
---@return ocaml.sandbox.Sandbox[]
local function detect(provider, root)
  local calls, result = 0, nil
  provider.detect(root, function(candidates)
    calls = calls + 1
    result = candidates
  end)
  assert.is_true(vim.wait(5000, function()
    return calls > 0
  end, 10))
  vim.wait(20)
  assert.are.equal(1, calls)
  return assert(result)
end

---A fresh temporary directory.
---@return string
local function tempdir()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  return vim.fs.normalize(assert(vim.uv.fs_realpath(dir)))
end

---@param path string
---@param text string
local function write(path, text)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local fd = assert(io.open(path, "w"))
  fd:write(text)
  fd:close()
end

---Create an executable file.
---@param path string
local function make_executable(path)
  write(path, "#!/bin/sh\n")
  vim.uv.fs_chmod(path, 493) -- 0755
end

local saved_config
local saved_notify
local saved_select
local restore_executables
local temp = {}

before_each(function()
  saved_config = package.loaded["ocaml.config.internal"]
  -- Keep job progress and errors out of the test output.
  saved_notify = vim.notify
  vim.notify = function() end
  -- A real prompt would block the headless test run; decline anything a
  -- test did not stub `provider.confirm` for.
  saved_select = vim.ui.select
  vim.ui.select = function(_, _, on_choice)
    on_choice(nil)
  end
  configure()
  restore_executables = fake_executables({ dune = true })
end)

after_each(function()
  local loaded = package.loaded["ocaml.sandbox.providers.dune"]
  if loaded then
    loaded.reset()
  end
  system.restore()
  restore_executables()
  vim.notify = saved_notify
  vim.ui.select = saved_select
  package.loaded["ocaml.config.internal"] = saved_config
  for _, name in ipairs(MODULES) do
    package.loaded[name] = nil
  end
  for _, dir in ipairs(temp) do
    vim.fn.delete(dir, "rf")
  end
  temp = {}
end)

---@return string
local function new_workspace()
  local dir = tempdir()
  table.insert(temp, dir)
  write(vim.fs.joinpath(dir, "dune-project"), "(lang dune 3.20)\n")
  return dir
end

describe("ocaml.sandbox.dune", function()
  local Dune

  before_each(function()
    Dune = require("ocaml.sandbox.dune")
  end)

  describe("parse_workspace", function()
    it("defaults to dune.lock and no pkg setting", function()
      assert.are.same({ lock_dir = "dune.lock" }, Dune.parse_workspace("(lang dune 3.20)\n"))
    end)

    it("reads (pkg enabled) and (pkg disabled)", function()
      assert.are.equal("enabled", Dune.parse_workspace("(lang dune 3.20)\n(pkg enabled)").pkg)
      assert.are.equal("disabled", Dune.parse_workspace("(lang dune 3.20)\n( pkg  disabled )").pkg)
    end)

    it("ignores commented-out stanzas", function()
      assert.is_nil(Dune.parse_workspace("(lang dune 3.20)\n; (pkg enabled)\n").pkg)
    end)

    it("takes the default context's lock dir, not a lock_dir stanza's path", function()
      local text = "(lock_dir (path other.lock) (repositories upstream))\n(context (default (lock_dir dev.lock)))"
      assert.are.equal("dev.lock", Dune.parse_workspace(text).lock_dir)
      assert.are.equal("dune.lock", Dune.parse_workspace("(lock_dir (path other.lock))").lock_dir)
      assert.are.equal("my dir.lock", Dune.parse_workspace('(context (default (lock_dir "my dir.lock")))').lock_dir)
    end)
  end)

  describe("parse_tools_env", function()
    it("returns the directories dune adds in front of PATH", function()
      local out = "export PATH=/ws/_build/a/bin:/ws/_build/b/bin:/usr/bin:/bin\n"
      assert.are.same({ "/ws/_build/a/bin", "/ws/_build/b/bin" }, Dune.parse_tools_env(out, "/usr/bin:/bin"))
    end)

    it("accepts a quoted value", function()
      assert.are.same({ "/w s/bin" }, Dune.parse_tools_env("export PATH='/w s/bin:/usr/bin'", "/usr/bin"))
    end)

    it("returns nil without a PATH export", function()
      assert.is_nil(Dune.parse_tools_env("set -x PATH /a/bin\n", "/usr/bin"))
    end)
  end)

  describe("workspace_root", function()
    it("uses the outermost dune-project when there is no dune-workspace", function()
      local root = new_workspace()
      write(vim.fs.joinpath(root, "sub", "dune-project"), "(lang dune 3.20)\n")
      assert.are.equal(root, Dune.workspace_root(vim.fs.joinpath(root, "sub")))
    end)

    it("prefers the outermost dune-workspace", function()
      local root = new_workspace()
      local sub = vim.fs.joinpath(root, "sub")
      write(vim.fs.joinpath(sub, "dune-workspace"), "(lang dune 3.20)\n")
      assert.are.equal(sub, Dune.workspace_root(vim.fs.joinpath(sub, "lib")))
      write(vim.fs.joinpath(root, "dune-workspace"), "(lang dune 3.20)\n")
      assert.are.equal(root, Dune.workspace_root(vim.fs.joinpath(sub, "lib")))
    end)
  end)

  it("recognizes dune's unknown command error", function()
    assert.is_true(Dune.is_unknown_command("dune: unknown command 'env', must be one of 'exec'"))
    assert.is_false(Dune.is_unknown_command("Error: I cannot find the root of the current workspace"))
  end)
end)

describe("dune provider", function()
  local provider

  before_each(function()
    provider = require("ocaml.sandbox.providers.dune")
  end)

  describe("detect", function()
    it("finds nothing when dune is not installed", function()
      restore_executables()
      restore_executables = fake_executables({ dune = false })
      local calls = system.install({})
      assert.are.same({}, detect(provider, fixtures .. "/locked"))
      assert.are.same({}, calls)
    end)

    it("finds nothing in a project without package management, without running dune", function()
      local calls = system.install({})
      assert.are.same({}, detect(provider, fixtures .. "/plain"))
      assert.are.same({}, calls)
    end)

    it("offers a locked project, with the dune version and dev tool directories", function()
      local calls = system.install(dune_responses())
      local root = fixtures .. "/locked"
      local candidates = detect(provider, root)
      assert.are.equal(1, #candidates)
      local c = candidates[1]
      assert.are.equal("dune:" .. root, c.id)
      assert.are.equal("dune", c.provider)
      assert.are.equal("dune pkg dune.lock", c.label)
      assert.are.equal(root, c.root)
      assert.are_not.equal(false, c.auto)
      assert.are.equal("3.24.2", c.data.version)
      assert.are.equal(root .. "/dune.lock", c.data.lock_dir)
      assert.are.same({ DEV_BIN }, c.data.dirs)
      assert.matches("dune 3.24.2", c.note, 1, true)
      assert.are.same({ "dune --version", "dune tools env" }, system.lines(calls))
      assert.are.equal(root, calls[2].opts.cwd)
    end)

    it("uses the workspace root when detecting from a subdirectory", function()
      system.install(dune_responses())
      local c = detect(provider, fixtures .. "/locked/lib")[1]
      assert.are.equal("dune:" .. fixtures .. "/locked", c.id)
      assert.are.equal(fixtures .. "/locked/lib", c.root)
    end)

    it("offers a project with (pkg enabled) but no lock dir", function()
      system.install(dune_responses())
      local c = detect(provider, fixtures .. "/enabled")[1]
      assert.are.equal("dune pkg (not locked)", c.label)
      assert.are_not.equal(false, c.auto)
      assert.matches("does not exist yet", c.note, 1, true)
    end)

    it("respects (pkg disabled) even with a lock dir", function()
      local calls = system.install({})
      assert.are.same({}, detect(provider, fixtures .. "/disabled"))
      assert.are.same({}, calls)
    end)

    it("uses the default context's lock dir from dune-workspace", function()
      system.install(dune_responses())
      local c = detect(provider, fixtures .. "/custom")[1]
      assert.are.equal(fixtures .. "/custom/locks/dev.lock", c.data.lock_dir)
      assert.are.equal("dune pkg locks/dev.lock", c.label)
    end)

    it("lists but does not pick a project when dune has no `dune tools`", function()
      system.install({
        ["dune --version"] = { stdout = "3.16.0\n" },
        ["dune tools env"] = { code = 1, stderr = "dune: unknown command 'tools'.\n" },
      })
      local c = detect(provider, fixtures .. "/locked")[1]
      assert.are.equal(false, c.auto)
      assert.is_nil(c.data.dirs)
      assert.matches("upgrade dune", c.note, 1, true)
    end)

    it("lists but does not pick a project when `dune tools env` fails", function()
      system.install({
        ["dune --version"] = { stdout = "3.24.2\n" },
        ["dune tools env"] = { code = 1, stderr = 'File "dune-project", line 1:\nError: Invalid syntax\n' },
      })
      local c = detect(provider, fixtures .. "/locked")[1]
      assert.are.equal(false, c.auto)
      assert.matches("Invalid syntax", c.note, 1, true)
    end)

    it("uses the configured binary", function()
      configure({ dune = { binary = "/opt/dune/bin/dune" } })
      provider = require("ocaml.sandbox.providers.dune")
      restore_executables()
      restore_executables = fake_executables({ ["/opt/dune/bin/dune"] = true })
      local calls = system.install({
        ["/opt/dune/bin/dune --version"] = { stdout = "3.24.2\n" },
        ["/opt/dune/bin/dune tools env"] = { stdout = "export PATH=" .. DEV_BIN .. "\n" },
      })
      local c = detect(provider, fixtures .. "/locked")[1]
      assert.are.equal("/opt/dune/bin/dune", c.data.binary)
      assert.are.equal(2, #calls)
    end)

    it("runs `dune --version` once per binary", function()
      local calls = system.install(dune_responses())
      detect(provider, fixtures .. "/locked")
      detect(provider, fixtures .. "/custom")
      assert.are.same({ "dune --version", "dune tools env", "dune tools env" }, system.lines(calls))
    end)
  end)

  describe("commands", function()
    local bin, sandbox

    before_each(function()
      bin = tempdir()
      table.insert(temp, bin)
      make_executable(bin .. "/ocamllsp")
      sandbox = {
        id = "dune:/ws",
        provider = "dune",
        label = "dune pkg dune.lock",
        root = "/ws",
        data = { binary = "dune", workspace = "/ws", lock_dir = "/ws/dune.lock", dirs = { bin } },
      }
    end)

    it("runs an installed dev tool from its directory", function()
      assert.are.same({ bin .. "/ocamllsp", "--stdio" }, provider.wrap(sandbox, { "ocamllsp", "--stdio" }))
      assert.are.equal(bin .. "/ocamllsp", provider.find_executable(sandbox, "ocamllsp"))
    end)

    it("refuses a dev tool that is not installed", function()
      assert.is_nil(provider.wrap(sandbox, { "ocamlformat", "--version" }))
      assert.is_nil(provider.find_executable(sandbox, "ocamlformat"))
    end)

    it("runs other commands unchanged", function()
      assert.are.same({ "dune", "build" }, provider.wrap(sandbox, { "dune", "build" }))
    end)

    it("puts the dev tool directories first on PATH", function()
      local env = assert(provider.env(sandbox))
      assert.are.equal(1, env.PATH:find(bin .. ":", 1, true))
      sandbox.data.dirs = nil
      assert.is_nil(provider.env(sandbox))
    end)

    it("builds the LSP command through the sandbox module", function()
      local cmd = require("ocaml.sandbox").get_lsp_command(sandbox, {})
      assert.are.same({ bin .. "/ocamllsp" }, cmd)
    end)
  end)

  describe("ensure_tool", function()
    local workspace, bin, sandbox, prompts, answer

    ---@param name string
    ---@return { ok: boolean, err: string|nil }
    local function ensure(name)
      local result
      provider.ensure_tool(sandbox, name, function(ok, err)
        result = { ok = ok, err = err }
      end)
      assert.is_true(vim.wait(2000, function()
        return result ~= nil
      end, 10))
      return result
    end

    before_each(function()
      workspace = new_workspace()
      vim.fn.mkdir(workspace .. "/dune.lock", "p")
      bin = workspace .. "/_build/dev-tools/bin"
      vim.fn.mkdir(bin, "p")
      sandbox = {
        id = "dune:" .. workspace,
        provider = "dune",
        label = "dune pkg dune.lock",
        root = workspace,
        data = { binary = "dune", workspace = workspace, lock_dir = workspace .. "/dune.lock", dirs = { bin } },
      }
      prompts, answer = {}, true
      provider.confirm = function(prompt, cb)
        table.insert(prompts, prompt)
        cb(answer)
      end
    end)

    it("succeeds at once when the tool is installed", function()
      make_executable(bin .. "/ocamllsp")
      local calls = system.install({})
      assert.is_true(ensure("ocamllsp").ok)
      assert.are.same({}, prompts)
      assert.are.same({}, calls)
    end)

    it("installs a missing tool when the user agrees", function()
      local calls = system.install({
        ["dune tools install ocamllsp"] = {
          effect = function()
            make_executable(bin .. "/ocamllsp")
          end,
        },
      })
      assert.is_true(ensure("ocamllsp").ok)
      assert.are.equal(1, #prompts)
      assert.matches("dune tools install ocamllsp", prompts[1], 1, true)
      assert.are.same({ "dune tools install ocamllsp" }, system.lines(calls))
      assert.are.equal(workspace, calls[1].opts.cwd)
    end)

    it("reports a failed install", function()
      system.install({ ["dune tools install ocamllsp"] = { code = 1, stderr = "Error: no solution\n" } })
      local result = ensure("ocamllsp")
      assert.is_false(result.ok)
      assert.matches("dune tools install ocamllsp", result.err, 1, true)
    end)

    it("does not ask again after the user declines, until reset", function()
      answer = false
      local calls = system.install({})
      assert.is_false(ensure("ocamllsp").ok)
      assert.is_false(ensure("ocamllsp").ok)
      assert.are.equal(1, #prompts)
      assert.are.same({}, calls)

      provider.reset()
      ensure("ocamllsp")
      assert.are.equal(2, #prompts)
    end)

    it("asks once for concurrent requests", function()
      local release
      provider.confirm = function(prompt, cb)
        table.insert(prompts, prompt)
        release = cb
      end
      system.install({
        ["dune tools install ocamllsp"] = {
          effect = function()
            make_executable(bin .. "/ocamllsp")
          end,
        },
      })
      local results = {}
      for _ = 1, 2 do
        provider.ensure_tool(sandbox, "ocamllsp", function(ok)
          table.insert(results, ok)
        end)
      end
      assert.is_true(vim.wait(1000, function()
        return release ~= nil
      end, 10))
      release(true)
      assert.is_true(vim.wait(1000, function()
        return #results == 2
      end, 10))
      assert.are.same({ true, true }, results)
      assert.are.equal(1, #prompts)
    end)

    it("does not offer to install tools dune cannot install", function()
      local result = ensure("ocamlformat-mlx")
      assert.is_false(result.ok)
      assert.are.same({}, prompts)
    end)

    it("offers `dune pkg lock` first when the lock dir is missing", function()
      vim.fn.delete(workspace .. "/dune.lock", "rf")
      sandbox.label = "dune pkg (not locked)"
      local calls = system.install({
        ["dune pkg lock"] = {
          effect = function()
            vim.fn.mkdir(workspace .. "/dune.lock", "p")
          end,
        },
        ["dune tools install ocamllsp"] = {
          effect = function()
            make_executable(bin .. "/ocamllsp")
          end,
        },
      })
      assert.is_true(ensure("ocamllsp").ok)
      assert.are.equal(2, #prompts)
      assert.matches("dune pkg lock", prompts[1], 1, true)
      assert.are.same({ "dune pkg lock", "dune tools install ocamllsp" }, system.lines(calls))
      assert.are.equal("dune pkg dune.lock", sandbox.label)
    end)

    it("fails when the user declines to lock", function()
      vim.fn.delete(workspace .. "/dune.lock", "rf")
      answer = false
      local result = ensure("ocamllsp")
      assert.is_false(result.ok)
      assert.matches("dune pkg lock", result.err, 1, true)
    end)

    it("fails without dev tool directories, without asking", function()
      sandbox.data.dirs = nil
      sandbox.note = "dune 3.16.0 has no `dune tools`; upgrade dune"
      local result = ensure("ocamllsp")
      assert.is_false(result.ok)
      assert.matches("upgrade dune", result.err, 1, true)
      assert.are.same({}, prompts)
    end)
  end)

  describe("lock dir watcher", function()
    local workspace, prompts, clients, restarted

    before_each(function()
      workspace = new_workspace()
      write(workspace .. "/dune.lock/lock.dune", "(lang package 0.1)\n")
      prompts, clients, restarted = {}, {}, {}
      provider.WATCH_DEBOUNCE = 20
      provider.confirm = function(prompt, cb)
        table.insert(prompts, prompt)
        cb(true)
      end
      package.loaded["ocaml.lsp.helpers"] = {
        get_active_lsp_clients = function()
          return clients
        end,
      }
      package.loaded["ocaml.lsp"] = {
        restart = function(buf)
          table.insert(restarted, buf)
        end,
      }
    end)

    after_each(function()
      package.loaded["ocaml.lsp.helpers"] = nil
      package.loaded["ocaml.lsp"] = nil
    end)

    ---@param root string
    local function add_client(root)
      table.insert(clients, {
        config = { root_dir = root },
        attached_buffers = { [7] = true },
        is_stopped = function()
          return false
        end,
      })
    end

    ---Replace the lock dir the way `dune pkg lock` does.
    local function relock()
      local tmp = workspace .. "/dune.lock.tmp"
      write(tmp .. "/lock.dune", "(lang package 0.1)\n(ocaml ocaml-base-compiler)\n")
      vim.fn.delete(workspace .. "/dune.lock", "rf")
      assert(vim.uv.fs_rename(tmp, workspace .. "/dune.lock"))
    end

    local function watch()
      provider.watch({ binary = "dune", workspace = workspace, lock_dir = workspace .. "/dune.lock", dirs = {} })
    end

    it("offers to restart ocamllsp when the lock dir is replaced", function()
      add_client(workspace .. "/lib")
      system.install({})
      watch()
      relock()
      assert.is_true(vim.wait(2000, function()
        return #restarted > 0
      end, 10))
      assert.are.equal(1, #prompts)
      assert.matches("dune.lock changed", prompts[1], 1, true)
      assert.are.same({ 7 }, restarted)
    end)

    it("rebuilds installed dev tools before restarting", function()
      local bin = workspace .. "/_build/bin"
      make_executable(bin .. "/ocamllsp")
      provider.watch({ binary = "dune", workspace = workspace, lock_dir = workspace .. "/dune.lock", dirs = { bin } })
      add_client(workspace)
      local calls = system.install({ ["dune tools install ocamllsp"] = {} })
      relock()
      assert.is_true(vim.wait(2000, function()
        return #restarted > 0
      end, 10))
      assert.are.same({ "dune tools install ocamllsp" }, system.lines(calls))
    end)

    it("notices in-place edits of the lock file", function()
      add_client(workspace)
      system.install({})
      watch()
      vim.wait(50)
      write(workspace .. "/dune.lock/lock.dune", "(lang package 0.1)\n(ocaml ocaml-system)\n")
      assert.is_true(vim.wait(2000, function()
        return #prompts > 0
      end, 10))
    end)

    it("stays quiet when no ocamllsp runs in the workspace", function()
      add_client("/elsewhere")
      watch()
      relock()
      vim.wait(300)
      assert.are.same({}, prompts)
    end)

    it("watches each workspace once, and stops on reset", function()
      watch()
      watch()
      assert.are.same({ workspace }, provider.watched())
      provider.reset()
      assert.are.same({}, provider.watched())
    end)
  end)
end)

describe("sandbox resolution with dune", function()
  before_each(function()
    restore_executables()
    restore_executables = fake_executables({ dune = true, opam = false, esy = false })
  end)

  it("prefers dune over opam for a locked project by default", function()
    system.install(dune_responses())
    local sandbox = assert(require("ocaml.sandbox").resolve_sync(fixtures .. "/locked", 2000))
    assert.are.equal("dune:" .. fixtures .. "/locked", sandbox.id)
  end)

  it("falls through to the next provider for a project without package management", function()
    system.install({})
    local sandbox = assert(require("ocaml.sandbox").resolve_sync(fixtures .. "/plain", 2000))
    assert.are.equal("global", sandbox.id)
  end)
end)
