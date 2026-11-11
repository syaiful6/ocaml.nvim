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
    opam_lib.get_switches = function(_, cb)
      cb({ "/a", "/b", "/c", "default" })
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

describe("ocaml.sandbox.providers.opam switch selection", function()
  local provider, saved_lib, original_executable
  local switches, current, with_ocamllsp, current_calls

  before_each(function()
    saved_lib = package.loaded["ocaml.sandbox.opam"]
    local opam_lib = vim.deepcopy(require("ocaml.sandbox.opam"))
    switches, current, with_ocamllsp, current_calls = {}, nil, {}, 0
    opam_lib.create_sandbox = function(_, _, cb)
      cb({ binary = "opam", root = "/home/u/.opam" })
    end
    opam_lib.get_switches = function(_, cb)
      cb(switches)
    end
    opam_lib.get_current_switch = function(_, _, cb)
      current_calls = current_calls + 1
      cb(current)
    end
    package.loaded["ocaml.sandbox.opam"] = opam_lib
    package.loaded["ocaml.sandbox.providers.opam"] = nil
    provider = require("ocaml.sandbox.providers.opam")

    original_executable = vim.fn.executable
    vim.fn.executable = function(path)
      if path == "opam" then
        return 1
      end
      return with_ocamllsp[path] and 1 or 0
    end
  end)

  after_each(function()
    vim.fn.executable = original_executable
    package.loaded["ocaml.sandbox.opam"] = saved_lib
    package.loaded["ocaml.sandbox.providers.opam"] = nil
  end)

  local function detect(root)
    local result
    provider.detect(root, function(c)
      result = c
    end)
    return result
  end

  local function summary(candidates)
    return vim.tbl_map(function(c)
      return { c.data.switch, c.auto }
    end, candidates)
  end

  it("prefers the local switch at the root and lists globals as manual", function()
    switches = { "/work/other", "/work/proj", "4.14.2", "default" }
    local c = detect("/work/proj")
    assert.are.same({ { "/work/proj", true }, { "4.14.2", false }, { "default", false } }, summary(c))
    assert.are.equal(0, current_calls)
  end)

  it("finds local switches in parent directories, nearest first", function()
    switches = { "/work", "/work/mono", "/work/mono/pkg-other", "default" }
    local c = detect("/work/mono/pkg")
    assert.are.same({ { "/work/mono", true }, { "/work", true }, { "default", false } }, summary(c))
  end)

  it("does not treat a sibling with a common prefix as a parent", function()
    switches = { "/work/proj", "default" }
    current = "default"
    local c = detect("/work/project")
    assert.are.same({ { "default", false } }, summary(c))
  end)

  it("auto-selects the current global switch when it has ocamllsp", function()
    switches = { "4.14.2", "default" }
    current = "default"
    with_ocamllsp["/home/u/.opam/default/bin/ocamllsp"] = true
    local c = detect("/work/proj")
    assert.are.same({ { "default", true }, { "4.14.2", false } }, summary(c))
    assert.are.equal("opam default (current)", c[1].label)
  end)

  it("does not auto-select a current switch without ocamllsp", function()
    switches = { "default" }
    current = "default"
    local c = detect("/work/proj")
    assert.are.same({ { "default", false } }, summary(c))
  end)

  it("checks a local current switch for ocamllsp under _opam", function()
    switches = { "/elsewhere", "default" }
    current = "/elsewhere"
    with_ocamllsp["/elsewhere/_opam/bin/ocamllsp"] = true
    local c = detect("/work/proj")
    assert.are.same({ { "/elsewhere", true }, { "default", false } }, summary(c))
  end)

  it("still lists globals when opam cannot report the current switch", function()
    switches = { "default" }
    current = nil
    local c = detect("/work/proj")
    assert.are.same({ { "default", false } }, summary(c))
  end)
end)

describe("ocaml.sandbox resolve with auto = false", function()
  it("skips listed-only candidates and falls through to the next provider", function()
    local saved = {}
    for _, n in ipairs({ "esy", "opam" }) do
      saved[n] = package.loaded["ocaml.sandbox.providers." .. n]
    end
    package.loaded["ocaml.sandbox.providers.esy"] = {
      name = "esy",
      detect = function(_, cb)
        cb({})
      end,
      wrap = function(_, c)
        return c
      end,
    }
    package.loaded["ocaml.sandbox.providers.opam"] = {
      name = "opam",
      detect = function(root, cb)
        cb({ { id = "opam:default", provider = "opam", label = "", root = root, data = {}, auto = false } })
      end,
      wrap = function(_, c)
        return c
      end,
    }
    package.loaded["ocaml.sandbox"] = nil
    local result
    require("ocaml.sandbox").resolve("/proj", function(sb)
      result = sb
    end)
    for n, v in pairs(saved) do
      package.loaded["ocaml.sandbox.providers." .. n] = v
    end
    package.loaded["ocaml.sandbox"] = nil
    assert.are.equal("global", result.id)
  end)
end)
