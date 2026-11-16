describe("ocaml.formatter", function()
  local formatter, saved, tmp, buf, conform
  local names = { "esy", "opam", "global" }

  ---Make `name` the only provider with a candidate for every root.
  ---@param name string
  ---@param provider table detect is filled in; set wrap and/or find_executable.
  local function use_provider(name, provider)
    provider.name = name
    provider.detect = function(root, cb)
      cb({ { id = name .. ":x", provider = name, label = name, root = root, data = {} } })
    end
    package.loaded["ocaml.sandbox.providers." .. name] = provider
    package.loaded["ocaml.config.internal"] = {
      sandbox = { providers = { name }, opam = { binary = "opam" }, esy = { binary = "esy" } },
    }
  end

  ---Resolve the formatter override conform would get for the buffer.
  local function config(name)
    return conform.formatters[name](buf)
  end

  before_each(function()
    saved = { config = package.loaded["ocaml.config.internal"] }
    for _, n in ipairs(names) do
      saved[n] = package.loaded["ocaml.sandbox.providers." .. n]
    end
    package.loaded["ocaml.sandbox"] = nil
    package.loaded["ocaml.formatter"] = nil
    formatter = require("ocaml.formatter")

    tmp = vim.fn.tempname()
    vim.fn.mkdir(tmp .. "/proj", "p")
    vim.fn.writefile({ "(lang dune 3.0)" }, tmp .. "/proj/dune-project")
    buf = vim.fn.bufadd(tmp .. "/proj/a.ml")
    conform = { formatters = {} }
  end)

  after_each(function()
    for _, n in ipairs(names) do
      package.loaded["ocaml.sandbox.providers." .. n] = saved[n]
    end
    package.loaded["ocaml.config.internal"] = saved.config
    package.loaded["ocaml.sandbox"] = nil
    package.loaded["ocaml.formatter"] = nil
    vim.api.nvim_buf_delete(buf, { force = true })
    vim.fn.delete(tmp, "rf")
  end)

  describe("with a provider that finds executables (opam)", function()
    local found

    before_each(function()
      found = { ocamlformat = "/sw/bin/ocamlformat", ["ocamlformat-mlx"] = "/sw/bin/ocamlformat-mlx" }
      use_provider("opam", {
        find_executable = function(_, name)
          return found[name]
        end,
        wrap = function()
          error("tools with a path must not be wrapped")
        end,
      })
      formatter.setup(conform)
    end)

    it("runs ocamlformat from the sandbox", function()
      assert.are.same({ command = "/sw/bin/ocamlformat" }, config("ocamlformat"))
    end)

    it("runs ocamlformat-mlx from the sandbox", function()
      local c = config("ocamlformat_mlx")
      assert.are.equal("/sw/bin/ocamlformat-mlx", c.command)
      assert.are.same({ "--name", "$FILENAME", "--impl", "-" }, c.args)
      assert.is_false(c.inherit)
    end)

    it("falls back to PATH when the sandbox lacks the formatter", function()
      found = {}
      assert.are.same({ command = "ocamlformat" }, config("ocamlformat"))
      assert.are.equal("ocamlformat-mlx", config("ocamlformat_mlx").command)
    end)
  end)

  describe("with a provider that wraps commands (esy)", function()
    before_each(function()
      use_provider("esy", {
        wrap = function(_, cmd)
          return vim.list_extend({ "esy", "-P", "/proj/esy.json" }, cmd)
        end,
      })
    end)

    it("prepends the wrapper to the built-in formatter's args", function()
      formatter.setup(conform)
      local c = config("ocamlformat")
      assert.are.equal("esy", c.command)
      assert.are.same({ "-P", "/proj/esy.json", "ocamlformat" }, c.prepend_args)
    end)

    it("keeps the user's prepend_args after the wrapper", function()
      conform.formatters.ocamlformat = { prepend_args = { "--profile=janestreet" } }
      formatter.setup(conform)
      assert.are.same(
        { "-P", "/proj/esy.json", "ocamlformat", "--profile=janestreet" },
        config("ocamlformat").prepend_args
      )
    end)

    it("keeps prepend_args given as a function", function()
      conform.formatters.ocamlformat = {
        prepend_args = function()
          return { "--profile=janestreet" }
        end,
      }
      formatter.setup(conform)
      assert.are.same(
        { "-P", "/proj/esy.json", "ocamlformat", "--profile=janestreet" },
        config("ocamlformat").prepend_args({}, {})
      )
    end)

    it("prefixes args of a complete definition", function()
      formatter.setup(conform)
      assert.are.same(
        { "-P", "/proj/esy.json", "ocamlformat-mlx", "--name", "$FILENAME", "--impl", "-" },
        config("ocamlformat_mlx").args
      )
    end)
  end)

  describe("user settings", function()
    before_each(function()
      use_provider("opam", {
        find_executable = function(_, name)
          return "/sw/bin/" .. name
        end,
      })
    end)

    it("calls a user override given as a function with the buffer", function()
      local got
      conform.formatters.ocamlformat = function(bufnr)
        got = bufnr
        return { append_args = { "--margin=100" } }
      end
      formatter.setup(conform)
      assert.are.same({ command = "/sw/bin/ocamlformat", append_args = { "--margin=100" } }, config("ocamlformat"))
      assert.are.equal(buf, got)
    end)

    it("leaves a formatter with the user's own command alone", function()
      local own = { command = "/opt/ocamlformat" }
      conform.formatters.ocamlformat = own
      formatter.setup(conform)
      assert.are.equal(own, config("ocamlformat"))
    end)

    it("uses the user's ocamlformat_mlx definition", function()
      conform.formatters.ocamlformat_mlx = { command = "ocamlformat-mlx", args = { "-" } }
      formatter.setup(conform)
      assert.are.same({ command = "/sw/bin/ocamlformat-mlx", args = { "-" } }, config("ocamlformat_mlx"))
    end)
  end)
end)

describe("ocaml.sandbox.providers.opam find_executable", function()
  local tmp

  before_each(function()
    tmp = vim.fn.tempname()
    vim.fn.mkdir(tmp .. "/proj/_opam/bin", "p")
    vim.fn.writefile({ "#!/bin/sh" }, tmp .. "/proj/_opam/bin/ocamlformat")
    vim.fn.setfperm(tmp .. "/proj/_opam/bin/ocamlformat", "rwxr-xr-x")
  end)

  after_each(function()
    vim.fn.delete(tmp, "rf")
  end)

  local function sandbox()
    return {
      id = "opam:" .. tmp .. "/proj",
      provider = "opam",
      label = "",
      root = tmp .. "/proj",
      data = { binary = "opam", opam_root = tmp .. "/root", switch = tmp .. "/proj" },
    }
  end

  it("returns the tool in the switch's bin directory", function()
    local opam = require("ocaml.sandbox.providers.opam")
    assert.are.equal(tmp .. "/proj/_opam/bin/ocamlformat", opam.find_executable(sandbox(), "ocamlformat"))
  end)

  it("returns nil when the switch lacks the tool", function()
    local opam = require("ocaml.sandbox.providers.opam")
    assert.is_nil(opam.find_executable(sandbox(), "ocamlformat-mlx"))
  end)
end)
