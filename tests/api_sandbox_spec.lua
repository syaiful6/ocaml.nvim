describe("require('ocaml').sandbox", function()
  local api, Sandbox, tmp, saved
  local names = { "esy", "opam", "global" }

  ---Stub a provider wrapping commands with `prefix`.
  local function stub(name, candidates, prefix, env)
    package.loaded["ocaml.sandbox.providers." .. name] = {
      name = name,
      detect = function(root, cb)
        cb(vim.tbl_map(function(id)
          return { id = id, provider = name, label = id, root = root, data = {} }
        end, candidates))
      end,
      wrap = function(_, cmd)
        local out = vim.deepcopy(prefix)
        vim.list_extend(out, cmd)
        return out
      end,
      env = env and function()
        return env
      end,
    }
  end

  ---Wait for an async callback.
  local function await(f)
    local done, a, b = false, nil, nil
    f(function(x, y)
      done, a, b = true, x, y
    end)
    assert.is_true(vim.wait(5000, function()
      return done
    end, 10))
    return a, b
  end

  before_each(function()
    saved = { config = package.loaded["ocaml.config.internal"] }
    for _, n in ipairs(names) do
      saved[n] = package.loaded["ocaml.sandbox.providers." .. n]
    end
    package.loaded["ocaml.config.internal"] = {
      sandbox = { providers = { "esy", "opam", "global" }, opam = { binary = "opam" }, esy = { binary = "esy" } },
    }
    stub("esy", {}, {})
    stub("opam", { "opam:/proj" }, { "env", "SANDBOXED=1" })
    package.loaded["ocaml.sandbox"] = nil
    package.loaded["ocaml.api.sandbox"] = nil
    package.loaded["ocaml"] = nil
    Sandbox = require("ocaml.sandbox")
    api = require("ocaml").sandbox

    tmp = vim.fn.tempname()
    vim.fn.mkdir(tmp .. "/proj/lib", "p")
    vim.fn.writefile({ "(lang dune 3.0)" }, tmp .. "/proj/dune-project")
    tmp = vim.fs.normalize(vim.uv.fs_realpath(tmp))
  end)

  after_each(function()
    for _, n in ipairs(names) do
      package.loaded["ocaml.sandbox.providers." .. n] = saved[n]
    end
    package.loaded["ocaml.config.internal"] = saved.config
    package.loaded["ocaml.sandbox"] = nil
    package.loaded["ocaml.api.sandbox"] = nil
    package.loaded["ocaml"] = nil
    vim.fn.delete(tmp, "rf")
  end)

  it("is loaded lazily from require('ocaml')", function()
    package.loaded["ocaml.api.sandbox"] = nil
    package.loaded["ocaml"] = nil
    local ocaml = require("ocaml")
    assert.is_nil(package.loaded["ocaml.api.sandbox"])
    assert.are.equal(require("ocaml.api.sandbox"), ocaml.sandbox)
  end)

  describe("get", function()
    it("returns public info only, for an explicit root", function()
      local info = await(function(cb)
        api.get({ root = "/proj" }, cb)
      end)
      assert.are.same({ id = "opam:/proj", provider = "opam", label = "opam:/proj", root = "/proj" }, info)
    end)

    it("finds the project root from a buffer, like the LSP", function()
      local buf = vim.fn.bufadd(tmp .. "/proj/lib/a.ml")
      local info = await(function(cb)
        api.get({ bufnr = buf }, cb)
      end)
      vim.api.nvim_buf_delete(buf, { force = true })
      assert.are.equal(tmp .. "/proj", info.root)
    end)

    it("shares the cache with the language server", function()
      api.get({ root = "/proj" }, function() end)
      assert.are.equal("opam:/proj", Sandbox.get_cached("/proj").id)
    end)
  end)

  describe("get_command", function()
    it("wraps the command with the project's sandbox", function()
      local cmd, err = await(function(cb)
        api.get_command({ "dune", "build" }, { root = "/proj" }, cb)
      end)
      assert.is_nil(err)
      assert.are.same({ "env", "SANDBOXED=1", "dune", "build" }, cmd)
    end)

    it("rejects an invalid command", function()
      local cmd, err = await(function(cb)
        api.get_command({ "dune", 1 }, { root = "/proj" }, cb)
      end)
      assert.is_nil(cmd)
      assert.are.equal("cmd[2] must be a string, got number", err)
    end)
  end)

  describe("get_command_sync", function()
    it("returns the wrapped command", function()
      local cmd = api.get_command_sync({ "ocamlformat", "--help" }, { root = "/proj" })
      assert.are.same({ "env", "SANDBOXED=1", "ocamlformat", "--help" }, cmd)
    end)

    it("waits for a detection still in flight", function()
      package.loaded["ocaml.sandbox.providers.opam"].detect = function(root, cb)
        vim.defer_fn(function()
          cb({ { id = "opam:slow", provider = "opam", label = "", root = root, data = {} } })
        end, 50)
      end
      local cmd = api.get_command_sync({ "dune" }, { root = "/slow" })
      assert.are.same({ "env", "SANDBOXED=1", "dune" }, cmd)
    end)

    it("gives up after the timeout", function()
      package.loaded["ocaml.sandbox.providers.opam"].detect = function() end
      local cmd, err = api.get_command_sync({ "dune" }, { root = "/never", timeout = 50 })
      assert.is_nil(cmd)
      assert.are.equal("sandbox detection did not finish within 50 ms", err)
    end)
  end)

  describe("run", function()
    it("runs inside the sandbox, in the project root by default", function()
      local result, err = await(function(cb)
        api.run({ "sh", "-c", 'echo "$SANDBOXED $(pwd)"' }, { root = tmp .. "/proj" }, cb)
      end)
      assert.is_nil(err)
      assert.are.equal(0, result.code)
      assert.are.equal("1 " .. tmp .. "/proj\n", result.stdout)
    end)

    it("passes vim.system options through, cwd and env included", function()
      stub("opam", { "opam:/proj" }, {}, { FROM_PROVIDER = "p", SHARED = "provider" })
      local result = await(function(cb)
        api.run({ "sh", "-c", 'echo "$FROM_PROVIDER $SHARED $(pwd)"; cat' }, {
          root = tmp .. "/proj",
          cwd = tmp .. "/proj/lib",
          env = { SHARED = "user" },
          stdin = "in",
        }, cb)
      end)
      assert.are.equal("p user " .. tmp .. "/proj/lib\nin", result.stdout)
    end)

    it("reports a command that cannot be started", function()
      stub("opam", { "opam:/proj" }, {})
      local result, err = await(function(cb)
        api.run({ "ocamlnvim-no-such-binary" }, { root = tmp .. "/proj" }, cb)
      end)
      assert.is_nil(result)
      assert.is_string(err)
    end)

    it("reports an invalid command without running anything", function()
      local result, err = await(function(cb)
        api.run({}, { root = tmp .. "/proj" }, cb)
      end)
      assert.is_nil(result)
      assert.are.equal("cmd must be a non-empty list of strings", err)
    end)

    it("calls on_exit on the main loop", function()
      local fast = await(function(cb)
        api.run({ "true" }, { root = tmp .. "/proj" }, function()
          cb(vim.in_fast_event())
        end)
      end)
      assert.is_false(fast)
    end)
  end)
end)
