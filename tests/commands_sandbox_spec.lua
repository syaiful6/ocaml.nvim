describe("ocaml.commands.sandbox", function()
  local info, saved
  local names = { "esy", "opam", "global" }
  local clients

  local function stub(name, candidates)
    package.loaded["ocaml.sandbox.providers." .. name] = {
      name = name,
      detect = function(root, cb)
        cb(vim.tbl_map(function(c)
          return vim.tbl_extend("force", { provider = name, label = c.id, root = root, data = {} }, c)
        end, candidates))
      end,
      wrap = function(_, cmd)
        local out = { name .. "-run" }
        vim.list_extend(out, cmd)
        return out
      end,
    }
  end

  local function configure(sandbox_config)
    package.loaded["ocaml.config.internal"] = {
      sandbox = vim.tbl_extend("force", { providers = { "esy", "opam", "global" } }, sandbox_config or {}),
    }
    package.loaded["ocaml.sandbox"] = nil
  end

  local function report(root)
    local result
    info.collect(root or "/proj", function(r)
      result = r
    end)
    return result
  end

  local function text(r)
    return table.concat(info.to_text(info.format(r)), "\n")
  end

  before_each(function()
    saved = { config = package.loaded["ocaml.config.internal"], helpers = package.loaded["ocaml.lsp.helpers"] }
    for _, n in ipairs(names) do
      saved[n] = package.loaded["ocaml.sandbox.providers." .. n]
    end
    clients = {}
    package.loaded["ocaml.lsp.helpers"] = {
      get_active_lsp_clients = function()
        return clients
      end,
    }
    configure()
    stub("esy", {})
    stub("opam", {
      { id = "opam:4.14.1", label = "opam 4.14.1 (current)", note = "opam's current switch, with ocamllsp installed" },
      { id = "opam:default", label = "opam default", auto = false },
    })
    stub("global", { { id = "global", note = "no sandbox; tools run from PATH" } })
    package.loaded["ocaml.commands.sandbox"] = nil
    info = require("ocaml.commands.sandbox")
  end)

  after_each(function()
    package.loaded["ocaml.config.internal"] = saved.config
    package.loaded["ocaml.lsp.helpers"] = saved.helpers
    for _, n in ipairs(names) do
      package.loaded["ocaml.sandbox.providers." .. n] = saved[n]
    end
    package.loaded["ocaml.sandbox"] = nil
    package.loaded["ocaml.commands.sandbox"] = nil
  end)

  it("reports the active sandbox, every candidate and the LSP command", function()
    local r = report()
    assert.are.equal("opam:4.14.1", r.active.id)
    assert.are.equal("priority", r.chosen_by)
    assert.are.same(
      { "opam:4.14.1", "opam:default", "global" },
      vim.tbl_map(function(c)
        return c.id
      end, r.candidates)
    )
    assert.are.same({ "opam-run", "ocamllsp" }, r.lsp_cmd)
    assert.is_nil(r.lsp_client_id)
  end)

  it("explains a choice made by priority", function()
    assert.are.same({
      "selected the first automatic candidate in provider order: esy > opam > global",
      "esy: nothing found",
      "opam: opam's current switch, with ocamllsp installed",
    }, info.explain(report()))
  end)

  it("explains providers skipped because they had only manual candidates", function()
    stub(
      "opam",
      { { id = "opam:default", auto = false, note = "opam's current switch, but ocamllsp is not installed in it" } }
    )
    local r = report()
    assert.are.equal("global", r.active.id)
    assert.are.same({
      "selected the first automatic candidate in provider order: esy > opam > global",
      "esy: nothing found",
      "opam: found 1, but none was eligible for automatic selection: opam:default (opam's current switch, but ocamllsp is not installed in it)",
      "global: no sandbox; tools run from PATH",
    }, info.explain(r))
  end)

  it("explains a choice made by the resolve hook", function()
    configure({
      resolve = function()
        return "opam:default"
      end,
    })
    local r = report()
    assert.are.equal("opam:default", r.active.id)
    assert.are.same({ "chosen by your sandbox.resolve hook" }, info.explain(r))
  end)

  it("says when the resolve hook did not override the default", function()
    configure({
      resolve = function()
        return nil
      end,
    })
    local why = info.explain(report())
    assert.matches("sandbox.resolve did not override it", why[1], 1, true)
  end)

  it("shows the command of a running client for the root", function()
    clients = {
      {
        id = 7,
        config = { root_dir = "/proj", cmd = { "opam", "exec", "--switch=4.14.1", "--", "ocamllsp" } },
        is_stopped = function()
          return false
        end,
      },
      {
        id = 8,
        config = { root_dir = "/other", cmd = { "ocamllsp" } },
        is_stopped = function()
          return false
        end,
      },
    }
    local r = report()
    assert.are.equal(7, r.lsp_client_id)
    assert.matches("opam exec --switch=4.14.1 -- ocamllsp (running, client 7)", text(r), 1, true)
  end)

  it("marks the active candidate and manual ones", function()
    local out = info.to_text(info.format(report()))
    assert.are.equal("OCaml sandbox for /proj", out[1])
    assert.truthy(
      vim.tbl_contains(out, "  ● opam:4.14.1   opam 4.14.1 (current)  opam's current switch, with ocamllsp installed")
    )
    assert.truthy(vim.tbl_contains(out, "    opam:default  opam default  manual"))
    assert.truthy(vim.tbl_contains(out, "    global        global  no sandbox; tools run from PATH"))
    assert.matches("opam-run ocamllsp (not running)", text(report()), 1, true)
  end)

  it("warns when the cached sandbox is no longer detected", function()
    local r = report()
    r.candidates = vim.tbl_filter(function(c)
      return c.id ~= r.active.id
    end, r.candidates)
    assert.matches("no longer detected", text(r), 1, true)
  end)

  it("shows why no LSP command could be built", function()
    package.loaded["ocaml.sandbox.providers.opam"].wrap = function()
      return nil
    end
    local r = report()
    assert.is_nil(r.lsp_cmd)
    assert.matches("lsp       sandbox opam:4.14.1 cannot run ocamllsp", text(r), 1, true)
  end)
end)
