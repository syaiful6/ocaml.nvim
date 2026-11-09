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
