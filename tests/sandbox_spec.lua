describe("ocaml.sandbox", function()
  local sandbox
  local saved = {}
  local provider_names = { "esy", "opam", "global" }

  ---@param name string
  ---@param candidates ocaml.sandbox.Sandbox[]
  local function stub_provider(name, candidates)
    package.loaded["ocaml.sandbox.providers." .. name] = {
      name = name,
      detect = function(_, cb)
        cb(candidates)
      end,
      wrap = function(_, cmd)
        local out = { name .. "-run" }
        vim.list_extend(out, cmd)
        return out
      end,
    }
  end

  local function candidate(name, root)
    return { id = name .. ":x", provider = name, label = name, root = root, data = {} }
  end

  before_each(function()
    for _, name in ipairs(provider_names) do
      saved[name] = package.loaded["ocaml.sandbox.providers." .. name]
    end
    package.loaded["ocaml.sandbox"] = nil
    sandbox = require("ocaml.sandbox")
  end)

  after_each(function()
    for _, name in ipairs(provider_names) do
      package.loaded["ocaml.sandbox.providers." .. name] = saved[name]
    end
  end)

  describe("resolve", function()
    it("prefers esy over opam", function()
      stub_provider("esy", { candidate("esy", "/proj") })
      stub_provider("opam", { candidate("opam", "/proj") })
      local result
      sandbox.resolve("/proj", function(sb)
        result = sb
      end)
      assert.are.equal("esy", result.provider)
    end)

    it("uses opam when esy finds nothing", function()
      stub_provider("esy", {})
      stub_provider("opam", { candidate("opam", "/proj") })
      local result
      sandbox.resolve("/proj", function(sb)
        result = sb
      end)
      assert.are.equal("opam", result.provider)
    end)

    it("falls back to the real global provider", function()
      stub_provider("esy", {})
      stub_provider("opam", {})
      package.loaded["ocaml.sandbox.providers.global"] = nil
      local result
      sandbox.resolve("/proj", function(sb)
        result = sb
      end)
      assert.are.same({ id = "global", provider = "global", label = "global", root = "/proj", data = {} }, result)
    end)
  end)

  describe("cache", function()
    ---A provider whose detection waits for `finish_all`.
    local deferred

    before_each(function()
      deferred = { calls = 0, pending = {}, resets = 0 }
      stub_provider("esy", {})
      package.loaded["ocaml.sandbox.providers.opam"] = {
        name = "opam",
        detect = function(root, cb)
          deferred.calls = deferred.calls + 1
          table.insert(deferred.pending, function()
            cb({ candidate("opam", root) })
          end)
        end,
        wrap = function(_, cmd)
          return cmd
        end,
        reset = function()
          deferred.resets = deferred.resets + 1
        end,
      }
    end)

    local function finish_all()
      local pending = deferred.pending
      deferred.pending = {}
      for _, f in ipairs(pending) do
        f()
      end
    end

    it("detects once and serves later calls from the cache", function()
      local first, second
      sandbox.resolve("/proj", function(sb)
        first = sb
      end)
      finish_all()
      sandbox.resolve("/proj", function(sb)
        second = sb
      end)
      assert.are.equal(1, deferred.calls)
      assert.are.equal("opam", first.provider)
      assert.are.equal(first, second)
      assert.are.equal(first, sandbox.get_cached("/proj"))
    end)

    it("shares a detection already in flight", function()
      local results = {}
      for _ = 1, 3 do
        sandbox.resolve("/proj", function(sb)
          table.insert(results, sb)
        end)
      end
      assert.are.equal(1, deferred.calls)
      assert.are.equal(0, #results)
      finish_all()
      assert.are.equal(3, #results)
      assert.are.equal(results[1], results[3])
    end)

    it("keeps roots separate", function()
      sandbox.resolve("/a", function() end)
      sandbox.resolve("/b", function() end)
      finish_all()
      assert.are.equal(2, deferred.calls)
      assert.are.equal("/a", sandbox.get_cached("/a").root)
      assert.are.equal("/b", sandbox.get_cached("/b").root)
    end)

    it("invalidate(root) forces detection again for that root only", function()
      sandbox.resolve("/a", function() end)
      sandbox.resolve("/b", function() end)
      finish_all()
      sandbox.invalidate("/a")
      assert.is_nil(sandbox.get_cached("/a"))
      assert.is_not_nil(sandbox.get_cached("/b"))
      sandbox.resolve("/a", function() end)
      assert.are.equal(3, deferred.calls)
      assert.are.equal(0, deferred.resets)
    end)

    it("invalidate() clears every root and resets providers", function()
      sandbox.resolve("/a", function() end)
      finish_all()
      sandbox.invalidate()
      assert.is_nil(sandbox.get_cached("/a"))
      assert.are.equal(1, deferred.resets)
    end)

    it("does not cache a detection that was invalidated while in flight", function()
      local stale
      sandbox.resolve("/proj", function(sb)
        stale = sb
      end)
      sandbox.invalidate("/proj")

      local fresh
      sandbox.resolve("/proj", function(sb)
        fresh = sb
      end)
      assert.are.equal(2, deferred.calls)

      -- The old detection calls its waiter without populating the cache.
      deferred.pending[1]()
      assert.is_not_nil(stale)
      assert.is_nil(sandbox.get_cached("/proj"))

      deferred.pending[2]()
      assert.is_not_nil(fresh)
      assert.are.equal(fresh, sandbox.get_cached("/proj"))
    end)
  end)

  describe("get_command", function()
    it("delegates to the owning provider", function()
      stub_provider("opam", {})
      local cmd = sandbox.get_command(candidate("opam", "/proj"), { "dune", "build" })
      assert.are.same({ "opam-run", "dune", "build" }, cmd)
    end)

    it("errors on an unknown provider", function()
      local cmd, err = sandbox.get_command(candidate("nope", "/proj"), { "dune" })
      assert.is_nil(cmd)
      assert.are.equal("unknown sandbox provider: nope", err)
    end)

    it("builds the ocamllsp command", function()
      stub_provider("esy", {})
      local cmd = sandbox.get_lsp_command(candidate("esy", "/proj"), { "--fallback-read-dot-merlin" })
      assert.are.same({ "esy-run", "ocamllsp", "--fallback-read-dot-merlin" }, cmd)
    end)
  end)
end)

describe("ocaml.sandbox.providers", function()
  it("global wraps nothing and copies the command", function()
    local global = require("ocaml.sandbox.providers.global")
    local cmd = { "ocamllsp" }
    local out = global.wrap({ id = "global", provider = "global", label = "global", root = "/proj", data = {} }, cmd)
    assert.are.same({ "ocamllsp" }, out)
    assert.are_not.equal(cmd, out)
  end)

  it("opam wraps with exec --switch", function()
    local opam = require("ocaml.sandbox.providers.opam")
    local out = opam.wrap({
      id = "opam:/proj",
      provider = "opam",
      label = "",
      root = "/proj",
      data = { binary = "opam", opam_root = "/home/u/.opam", switch = "/proj" },
    }, { "ocamllsp" })
    assert.are.same(
      { "opam", "exec", "--switch=/proj", "--set-switch", "--root", "/home/u/.opam", "--", "ocamllsp" },
      out
    )
  end)
end)

describe("ocaml.sandbox.providers.opam installation cache", function()
  local provider, opam_lib, saved_lib, original_executable
  local creates, pending_creates

  before_each(function()
    saved_lib = package.loaded["ocaml.sandbox.opam"]
    opam_lib = vim.deepcopy(require("ocaml.sandbox.opam"))
    creates, pending_creates = 0, {}
    opam_lib.create_sandbox = function(_, _, cb)
      creates = creates + 1
      table.insert(pending_creates, function()
        cb({ binary = "opam", root = "/home/u/.opam" })
      end)
    end
    opam_lib.get_local_switch = function(_, dir, cb)
      cb(dir)
    end
    package.loaded["ocaml.sandbox.opam"] = opam_lib
    package.loaded["ocaml.sandbox.providers.opam"] = nil
    provider = require("ocaml.sandbox.providers.opam")

    original_executable = vim.fn.executable
    vim.fn.executable = function()
      return 1
    end
  end)

  after_each(function()
    vim.fn.executable = original_executable
    package.loaded["ocaml.sandbox.opam"] = saved_lib
    package.loaded["ocaml.sandbox.providers.opam"] = nil
  end)

  local function finish_creates()
    local p = pending_creates
    pending_creates = {}
    for _, f in ipairs(p) do
      f()
    end
  end

  it("looks up the opam root once across project roots", function()
    local found = {}
    provider.detect("/a", function(c)
      found.a = c[1]
    end)
    provider.detect("/b", function(c)
      found.b = c[1]
    end)
    assert.are.equal(1, creates)
    finish_creates()
    provider.detect("/c", function(c)
      found.c = c[1]
    end)
    assert.are.equal(1, creates)
    assert.are.equal("/home/u/.opam", found.a.data.opam_root)
    assert.are.equal("/b", found.b.data.switch)
    assert.are.equal("/c", found.c.data.switch)
  end)

  it("looks the opam root up again after reset()", function()
    provider.detect("/a", function() end)
    finish_creates()
    provider.reset()
    provider.detect("/a", function() end)
    assert.are.equal(2, creates)
  end)
end)
