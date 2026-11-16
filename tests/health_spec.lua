describe("ocaml.health", function()
  local health, reported, saved
  local exepaths, executables, versions, report, buffer

  ---Messages reported at `level`, e.g. "ok", "warn", "error", "info".
  local function messages(level)
    return vim.tbl_map(
      function(r)
        return r.msg
      end,
      vim.tbl_filter(function(r)
        return r.level == level
      end, reported)
    )
  end

  ---The report entry whose message contains `text`.
  local function find(text)
    for _, r in ipairs(reported) do
      if r.msg:find(text, 1, true) then
        return r
      end
    end
  end

  local function sandbox(provider, extra)
    return vim.tbl_extend("force", {
      id = provider,
      provider = provider,
      label = provider,
      root = "/proj",
      data = {},
    }, extra or {})
  end

  before_each(function()
    saved = {
      health = vim.health,
      exepath = vim.fn.exepath,
      executable = vim.fn.executable,
      filereadable = vim.fn.filereadable,
      sandbox = package.loaded["ocaml.sandbox"],
      info = package.loaded["ocaml.commands.sandbox"],
      status = package.loaded["ocaml.config.status"],
    }
    reported = {}
    local stub = {}
    for _, level in ipairs({ "start", "ok", "warn", "error", "info" }) do
      stub[level] = function(msg, advice)
        table.insert(reported, { level = level, msg = msg, advice = advice })
      end
    end
    vim.health = stub

    exepaths = { opam = "/usr/bin/opam", dune = "/usr/bin/dune", ocamllsp = "/usr/bin/ocamllsp" }
    executables = {}
    versions = { ["/usr/bin/opam"] = "2.3.0", ["/usr/bin/dune"] = "3.19.1", ["/usr/bin/ocamllsp"] = "1.21.0" }
    vim.fn.exepath = function(name)
      return exepaths[name] or ""
    end
    vim.fn.executable = function(name)
      return (executables[name] or exepaths[name]) and 1 or 0
    end
    vim.fn.filereadable = function()
      return 0
    end

    package.loaded["ocaml.config.status"] = {}
    local tools = {}
    package.loaded["ocaml.sandbox"] = {
      priority = function()
        return { "esy", "opam", "global" }
      end,
      config = function()
        return { opam = { binary = "opam" }, esy = { binary = "esy" } }
      end,
      buffer_root = function()
        return "/proj"
      end,
      get_tool_command = function(_, name)
        return tools[name]
      end,
      _tools = tools,
    }
    report = {
      root = "/proj",
      active = sandbox("global"),
      chosen_by = "priority",
      has_hook = false,
      priority = { "esy", "opam", "global" },
      candidates = { sandbox("global") },
      lsp_cmd = { "ocamllsp" },
    }
    package.loaded["ocaml.commands.sandbox"] = {
      collect = function(_, cb)
        cb(report)
      end,
      explain = function()
        return { "because" }
      end,
      format_cmd = function(cmd)
        return table.concat(cmd, " ")
      end,
    }

    package.loaded["ocaml.health"] = nil
    health = require("ocaml.health")
    health.version = function(path)
      if versions[path] then
        return versions[path]
      end
      return nil, "exit code 1"
    end
    buffer = 1
    health.find_buffer = function()
      return buffer
    end
  end)

  after_each(function()
    vim.health = saved.health
    vim.fn.exepath = saved.exepath
    vim.fn.executable = saved.executable
    vim.fn.filereadable = saved.filereadable
    package.loaded["ocaml.sandbox"] = saved.sandbox
    package.loaded["ocaml.commands.sandbox"] = saved.info
    package.loaded["ocaml.config.status"] = saved.status
    package.loaded["ocaml.health"] = nil
  end)

  local function tools(t)
    for k, v in pairs(t) do
      package.loaded["ocaml.sandbox"]._tools[k] = v
    end
  end

  it("reports executables with their version and path", function()
    health.check()
    assert.truthy(vim.tbl_contains(messages("ok"), "opam: 2.3.0 (/usr/bin/opam)"))
    assert.truthy(vim.tbl_contains(messages("ok"), "dune: 3.19.1 (/usr/bin/dune)"))
    assert.matches("esy: `esy` not found", find("esy:").msg, 1, true)
    assert.are.equal("info", find("esy:").level)
  end)

  it("warns when a binary is found but --version fails", function()
    exepaths.dune = "/broken/dune"
    health.check()
    local r = find("dune: found at /broken/dune")
    assert.are.equal("warn", r.level)
  end)

  it("reports an invalid sandbox configuration", function()
    package.loaded["ocaml.config.status"].sandbox_error = "sandbox.providers[1]: unknown provider"
    health.check()
    assert.are.equal("error", find("Invalid sandbox options").level)
  end)

  it("explains how to check a sandbox when no OCaml buffer is open", function()
    buffer = nil
    health.check()
    assert.are.equal("info", find("No OCaml buffer is open").level)
  end)

  it("reports the active sandbox and why it was chosen", function()
    tools({ ocamllsp = { "ocamllsp" }, ocamlformat = { "ocamlformat" } })
    exepaths.ocamlformat = "/usr/bin/ocamlformat"
    health.check()
    assert.truthy(vim.tbl_contains(messages("ok"), "Active sandbox: global (global)"))
    assert.truthy(vim.tbl_contains(messages("info"), "Why: because"))
    assert.truthy(vim.tbl_contains(messages("ok"), "ocamllsp: ocamllsp (/usr/bin/ocamllsp)"))
    assert.truthy(vim.tbl_contains(messages("ok"), "ocamlformat: ocamlformat (/usr/bin/ocamlformat)"))
  end)

  it("errors when ocamllsp is not installed in the opam switch", function()
    report.active = sandbox("opam:5.2.0", { provider = "opam", label = "opam 5.2.0", data = { switch = "5.2.0" } })
    health.check()
    local r = find("ocamllsp is not installed in opam 5.2.0")
    assert.are.equal("error", r.level)
    assert.are.same({ "Run `opam install ocaml-lsp-server --switch=5.2.0`" }, r.advice)
  end)

  it("only warns about ocamlformat when the project has .ocamlformat", function()
    tools({ ocamllsp = { "ocamllsp" } })
    health.check()
    assert.are.equal("info", find("ocamlformat is not installed").level)

    reported = {}
    vim.fn.filereadable = function(path)
      return path == "/proj/.ocamlformat" and 1 or 0
    end
    health.check()
    assert.are.equal("warn", find("ocamlformat is not installed").level)
  end)

  it("warns when ocamllsp is not running and reports it when it is", function()
    tools({ ocamllsp = { "ocamllsp" } })
    health.check()
    assert.are.equal("warn", find("ocamllsp is not running").level)

    reported = {}
    report.lsp_client_id = 3
    health.check()
    assert.are.equal("ok", find("ocamllsp is running (client 3): ocamllsp").level)
  end)

  it("errors when no ocamllsp command can be built", function()
    report.lsp_cmd, report.lsp_err = nil, "sandbox x cannot run ocamllsp"
    health.check()
    assert.are.equal("error", find("Cannot build the ocamllsp command: sandbox x cannot run ocamllsp").level)
  end)
end)
