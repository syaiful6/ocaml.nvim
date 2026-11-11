describe("ocaml.config.internal", function()
  local saved_g, original_notify, notified

  ---Load the config module as if the user had set `vim.g.ocamlnvim = opts`.
  local function load(opts)
    vim.g.ocamlnvim = opts
    package.loaded["ocaml.config.internal"] = nil
    local config = require("ocaml.config.internal")
    -- Errors are reported with vim.schedule; let them run.
    vim.wait(20)
    return config
  end

  before_each(function()
    saved_g = vim.g.ocamlnvim
    notified = {}
    original_notify = vim.notify
    vim.notify = function(msg, level)
      table.insert(notified, { msg = msg, level = level })
    end
  end)

  after_each(function()
    vim.notify = original_notify
    vim.g.ocamlnvim = saved_g
    package.loaded["ocaml.config.internal"] = nil
  end)

  it("provides sandbox defaults", function()
    local config = load(nil)
    assert.are.same({ "esy", "opam", "global" }, config.sandbox.providers)
    assert.are.equal("opam", config.sandbox.opam.binary)
    assert.is_nil(config.sandbox.opam.root)
    assert.are.equal("esy", config.sandbox.esy.binary)
    assert.is_nil(config.sandbox.resolve)
    assert.are.same({}, notified)
  end)

  it("replaces the providers list instead of merging it by index", function()
    local config = load({ sandbox = { providers = { "opam" } } })
    assert.are.same({ "opam" }, config.sandbox.providers)
  end)

  it("merges nested options with the defaults", function()
    local config = load({ sandbox = { opam = { root = "/srv/opam" } } })
    assert.are.equal("/srv/opam", config.sandbox.opam.root)
    assert.are.equal("opam", config.sandbox.opam.binary)
    assert.are.same({ "esy", "opam", "global" }, config.sandbox.providers)
  end)

  it("accepts options given as a function", function()
    local config = load(function()
      return { sandbox = { esy = { binary = "/opt/esy" } } }
    end)
    assert.are.equal("/opt/esy", config.sandbox.esy.binary)
  end)

  it("keeps a resolve hook", function()
    local hook = function() end
    local config = load({ sandbox = { resolve = hook } })
    assert.are.equal(hook, config.sandbox.resolve)
  end)

  it("does not notify while the module is being required", function()
    vim.g.ocamlnvim = { sandbox = { providers = { "nix" } } }
    package.loaded["ocaml.config.internal"] = nil
    require("ocaml.config.internal")
    assert.are.same({}, notified)
    vim.wait(20)
    assert.are.equal(1, #notified)
  end)

  local invalid = {
    ["an unknown provider"] = { { providers = { "opam", "nix" } }, "unknown provider" },
    ["a duplicate provider"] = { { providers = { "opam", "opam" } }, "listed twice" },
    ["a non-string binary"] = { { opam = { binary = 42 } }, "sandbox.opam.binary" },
    ["a non-function resolve"] = { { resolve = "opam:default" }, "sandbox.resolve" },
  }
  for name, case in pairs(invalid) do
    it("reports " .. name .. " and falls back to the defaults", function()
      local config = load({ sandbox = case[1] })
      -- The error must not be raised while the module is being required
      -- (that would abort sourcing an ftplugin); it is reported afterwards.
      assert.are.equal(1, #notified)
      assert.are.equal(vim.log.levels.ERROR, notified[1].level)
      assert.truthy(notified[1].msg:find(case[2], 1, true), notified[1].msg)
      assert.are.same({ "esy", "opam", "global" }, config.sandbox.providers)
      assert.are.equal("opam", config.sandbox.opam.binary)
    end)
  end
end)
