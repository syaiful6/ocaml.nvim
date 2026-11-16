-- Detection and command wrapping per provider, against fixture projects in
-- tests/fixtures and a stubbed vim.system (tests/helpers/system.lua).

local system = require("tests.helpers.system")

local fixtures = vim.fs.normalize(assert(vim.uv.fs_realpath("tests/fixtures")))

---Install a sandbox configuration and reload the sandbox modules with it.
---@param sandbox_config table|nil merged over the defaults
local function configure(sandbox_config)
  package.loaded["ocaml.config.internal"] = {
    sandbox = vim.tbl_deep_extend("force", {
      providers = { "esy", "opam", "global" },
      opam = { binary = "opam" },
      esy = { binary = "esy" },
    }, sandbox_config or {}),
  }
  for _, name in ipairs({ "ocaml.sandbox", "ocaml.sandbox.providers.esy", "ocaml.sandbox.providers.opam" }) do
    package.loaded[name] = nil
  end
end

---Pretend `names` are executables; defer everything else to the real check.
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

---Run an async detect and wait for its single callback.
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
  vim.wait(20) -- let a second, wrong callback show up
  assert.are.equal(1, calls)
  return assert(result)
end

local saved_config

before_each(function()
  saved_config = package.loaded["ocaml.config.internal"]
end)

after_each(function()
  system.restore()
  package.loaded["ocaml.config.internal"] = saved_config
  for _, name in ipairs({ "ocaml.sandbox", "ocaml.sandbox.providers.esy", "ocaml.sandbox.providers.opam" }) do
    package.loaded[name] = nil
  end
end)

describe("global provider", function()
  it("always offers one automatic candidate for the root", function()
    configure()
    local candidates = detect(require("ocaml.sandbox.providers.global"), "/any/where")
    assert.are.equal(1, #candidates)
    assert.are.equal("global", candidates[1].id)
    assert.are.equal("global", candidates[1].provider)
    assert.are.equal("/any/where", candidates[1].root)
    assert.are_not.equal(false, candidates[1].auto)
  end)

  it("runs commands unchanged", function()
    configure()
    local Sandbox = require("ocaml.sandbox")
    local candidate = detect(require("ocaml.sandbox.providers.global"), "/p")[1]
    assert.are.same({ "dune", "build" }, Sandbox.get_command(candidate, { "dune", "build" }))
    assert.are.same({ "dune" }, Sandbox.get_tool_command(candidate, "dune"))
  end)
end)

describe("esy provider", function()
  local restore_executables, esy

  before_each(function()
    configure()
    restore_executables = fake_executables({ esy = true })
    -- Detection reads manifests only; it must never run esy.
    system.install({})
    esy = require("ocaml.sandbox.providers.esy")
  end)

  after_each(function()
    restore_executables()
  end)

  it("detects an esy.json project and prefers it over package.json", function()
    local root = fixtures .. "/esy/esy-json"
    local candidates = detect(esy, root)
    assert.are.equal(1, #candidates)
    local c = candidates[1]
    assert.are.equal("esy:" .. root .. "/esy.json", c.id)
    assert.are.equal("esy", c.provider)
    assert.are.equal(root, c.root)
    assert.are.same({ manifest = root .. "/esy.json", binary = "esy" }, c.data)
  end)

  it("detects a package.json with an esy field", function()
    local root = fixtures .. "/esy/package-json"
    local candidates = detect(esy, root)
    assert.are.equal("esy:" .. root .. "/package.json", candidates[1].id)
  end)

  it("finds the manifest from a subdirectory", function()
    local candidates = detect(esy, fixtures .. "/esy/package-json/src")
    assert.are.equal("esy:" .. fixtures .. "/esy/package-json/package.json", candidates[1].id)
  end)

  it("ignores a package.json without an esy field", function()
    assert.are.same({}, detect(esy, fixtures .. "/esy/npm-only"))
  end)

  it("ignores a manifest that is not valid JSON", function()
    assert.are.same({}, detect(esy, fixtures .. "/esy/broken"))
  end)

  it("ignores projects without a manifest", function()
    assert.are.same({}, detect(esy, fixtures .. "/opam/proj"))
  end)

  it("finds nothing when esy is not installed", function()
    restore_executables()
    restore_executables = fake_executables({ esy = false })
    assert.are.same({}, detect(esy, fixtures .. "/esy/esy-json"))
  end)

  it("uses the configured binary for detection and wrapping", function()
    restore_executables()
    configure({ esy = { binary = "/opt/esy/bin/esy" } })
    restore_executables = fake_executables({ ["/opt/esy/bin/esy"] = true, esy = false })
    esy = require("ocaml.sandbox.providers.esy")
    local root = fixtures .. "/esy/esy-json"
    local c = detect(esy, root)[1]
    assert.are.same({ "/opt/esy/bin/esy", "-P", root .. "/esy.json", "ocamllsp" }, esy.wrap(c, { "ocamllsp" }))
  end)

  it("wraps commands with esy -P <manifest>", function()
    local Sandbox = require("ocaml.sandbox")
    local root = fixtures .. "/esy/package-json"
    local c = detect(esy, root)[1]
    local manifest = root .. "/package.json"
    assert.are.same(
      { "esy", "-P", manifest, "ocamllsp", "--fallback-read-dot-merlin" },
      Sandbox.get_lsp_command(c, { "--fallback-read-dot-merlin" })
    )
    assert.are.same({ "esy", "-P", manifest, "ocamlformat" }, Sandbox.get_tool_command(c, "ocamlformat"))
  end)

  it("reports an error when the manifest disappeared", function()
    local Sandbox = require("ocaml.sandbox")
    local c = detect(esy, fixtures .. "/esy/package-json")[1]
    c.data.manifest = fixtures .. "/esy/package-json/gone.json"
    local cmd, err = Sandbox.get_command(c, { "dune" })
    assert.is_nil(cmd)
    assert.are.equal(("sandbox %s cannot run dune"):format(c.id), err)
  end)
end)

describe("opam provider", function()
  local restore_executables, opam, tmp, opam_root, proj

  ---Responses for an opam installation at `opam_root`.
  ---@param overrides table<string, tests.SystemResponse|false>|nil false removes a response
  local function responses(overrides)
    local r = {
      ["opam --version"] = { stdout = "2.3.0\n" },
      ["opam var --global"] = { stdout = "root " .. opam_root .. "  # Current opam root\nos linux\n" },
      ["opam switch list -s --root " .. opam_root] = { stdout = "default\n5.2.0\n\n" },
      ["opam switch show --root " .. opam_root] = { stdout = "5.2.0\n" },
    }
    for key, value in pairs(overrides or {}) do
      r[key] = value or nil
    end
    return r
  end

  ---Make `<opam_root>/<switch>/bin/ocamllsp` executable.
  local function install_ocamllsp(switch)
    local bin = vim.fs.joinpath(opam_root, switch, "bin")
    vim.fn.mkdir(bin, "p")
    vim.fn.writefile({ "#!/bin/sh" }, bin .. "/ocamllsp")
    vim.fn.setfperm(bin .. "/ocamllsp", "rwxr-xr-x")
  end

  local function ids(candidates)
    return vim.tbl_map(function(c)
      return c.id .. (c.auto == false and " (manual)" or "")
    end, candidates)
  end

  before_each(function()
    configure()
    restore_executables = fake_executables({ opam = true })
    tmp = vim.fn.tempname()
    vim.fn.mkdir(tmp .. "/opam-root", "p")
    tmp = vim.fs.normalize(assert(vim.uv.fs_realpath(tmp)))
    opam_root = tmp .. "/opam-root"
    proj = fixtures .. "/opam/proj"
    opam = require("ocaml.sandbox.providers.opam")
  end)

  after_each(function()
    restore_executables()
    vim.fn.delete(tmp, "rf")
  end)

  describe("finding the opam root", function()
    it("asks opam var --global on opam >= 2.1", function()
      local calls = system.install(responses())
      detect(opam, proj)
      assert.are.same({
        "opam --version",
        "opam var --global",
        "opam switch list -s --root " .. opam_root,
        "opam switch show --root " .. opam_root,
      }, system.lines(calls))
    end)

    it("uses plain opam var on opam 2.0", function()
      local calls = system.install(responses({
        ["opam --version"] = { stdout = "2.0.10\n" },
        ["opam var --global"] = false,
        ["opam var"] = { stdout = "root " .. opam_root .. "\n" },
      }))
      detect(opam, proj)
      assert.are.equal("opam var", system.lines(calls)[2])
    end)

    it("falls back to OPAMROOT when opam var fails", function()
      local saved = vim.env.OPAMROOT
      vim.env.OPAMROOT = opam_root
      system.install(responses({ ["opam var --global"] = { code = 1, stderr = "not initialised" } }))
      local candidates = detect(opam, proj)
      vim.env.OPAMROOT = saved
      assert.are.equal(opam_root, candidates[1].data.opam_root)
    end)

    it("skips the lookup when the root is configured", function()
      configure({ opam = { root = opam_root } })
      opam = require("ocaml.sandbox.providers.opam")
      local calls = system.install(responses())
      detect(opam, proj)
      assert.are.same({
        "opam switch list -s --root " .. opam_root,
        "opam switch show --root " .. opam_root,
      }, system.lines(calls))
    end)
  end)

  describe("switches", function()
    it("prefers a local switch at the root and does not ask for the current switch", function()
      local calls = system.install(responses({
        ["opam switch list -s --root " .. opam_root] = { stdout = "default\n" .. proj .. "\n" },
      }))
      local candidates = detect(opam, proj)
      assert.are.same({ "opam:" .. proj, "opam:default (manual)" }, ids(candidates))
      assert.are.same({ binary = "opam", opam_root = opam_root, switch = proj }, candidates[1].data)
      assert.is_false(vim.tbl_contains(system.lines(calls), "opam switch show --root " .. opam_root))
    end)

    it("uses a local switch of a parent directory", function()
      system.install(responses({
        ["opam switch list -s --root " .. opam_root] = { stdout = "default\n" .. proj .. "\n" },
      }))
      assert.are.equal("opam:" .. proj, detect(opam, proj .. "/lib")[1].id)
    end)

    it("asks opam for the current switch from the project directory", function()
      local calls = system.install(responses())
      detect(opam, proj)
      local show = calls[#calls]
      assert.are.equal("opam switch show --root " .. opam_root, table.concat(show.cmd, " "))
      assert.are.equal(proj, show.opts.cwd)
    end)

    it("auto-selects the current switch when it has ocamllsp", function()
      install_ocamllsp("5.2.0")
      system.install(responses())
      local candidates = detect(opam, proj)
      assert.are.same({ "opam:5.2.0", "opam:default (manual)" }, ids(candidates))
      assert.are.equal("opam 5.2.0 (current)", candidates[1].label)
    end)

    it("only lists a current switch without ocamllsp", function()
      system.install(responses())
      assert.are.same({ "opam:5.2.0 (manual)", "opam:default (manual)" }, ids(detect(opam, proj)))
    end)

    it("lists the global switches when opam switch show fails", function()
      system.install(responses({ ["opam switch show --root " .. opam_root] = { code = 5 } }))
      assert.are.same({ "opam:default (manual)", "opam:5.2.0 (manual)" }, ids(detect(opam, proj)))
    end)

    it("finds nothing when opam switch list fails", function()
      system.install(responses({ ["opam switch list -s --root " .. opam_root] = { code = 50, stderr = "boom" } }))
      assert.are.same({}, detect(opam, proj))
    end)

    it("finds nothing, without running opam, when opam is not installed", function()
      restore_executables()
      restore_executables = fake_executables({ opam = false })
      local calls = system.install({})
      assert.are.same({}, detect(opam, proj))
      assert.are.same({}, calls)
    end)
  end)

  describe("commands", function()
    it("runs the language server through opam exec with the switch and root", function()
      system.install(responses({
        ["opam switch list -s --root " .. opam_root] = { stdout = proj .. "\n" },
      }))
      local Sandbox = require("ocaml.sandbox")
      local c = detect(opam, proj)[1]
      assert.are.same({
        "opam",
        "exec",
        "--switch=" .. proj,
        "--set-switch",
        "--root",
        opam_root,
        "--",
        "ocamllsp",
      }, Sandbox.get_lsp_command(c))
    end)

    it("runs tools straight from the switch, or not at all when missing", function()
      install_ocamllsp("5.2.0")
      system.install(responses())
      local Sandbox = require("ocaml.sandbox")
      local c = detect(opam, proj)[1]
      assert.are.same({ opam_root .. "/5.2.0/bin/ocamllsp" }, Sandbox.get_tool_command(c, "ocamllsp"))
      assert.is_nil(Sandbox.get_tool_command(c, "ocamlformat"))
    end)
  end)

  describe("through resolve", function()
    it("falls back to global when opam has no usable switch", function()
      system.install(responses())
      local Sandbox = require("ocaml.sandbox")
      local chosen = assert(Sandbox.resolve_sync(proj, 5000))
      assert.are.equal("global", chosen.id)
    end)

    it("picks the opam switch over global", function()
      install_ocamllsp("5.2.0")
      system.install(responses())
      local Sandbox = require("ocaml.sandbox")
      assert.are.equal("opam:5.2.0", assert(Sandbox.resolve_sync(proj, 5000)).id)
    end)
  end)
end)
