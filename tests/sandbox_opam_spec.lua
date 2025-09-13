describe("ocaml.sandbox.opam", function()
  local opam

  before_each(function()
    opam = require("ocaml.sandbox.opam")
  end)

  describe("get_command", function()
    local sandbox = {
      binary = "/usr/bin/opam",
      root = "/home/user/.opam",
    }

    it("should format command with switch and args", function()
      local result = opam.get_command(sandbox, "4.14.0", { "ocamlc", "-v" })

      assert.are.same({
        "/usr/bin/opam",
        "exec",
        "--switch=4.14.0",
        "--set-switch",
        "--root",
        "/home/user/.opam",
        "--",
        "ocamlc",
        "-v",
      }, result)
    end)

    it("should handle nil args", function()
      local result = opam.get_command(sandbox, "4.14.0", { "ocamllsp" })

      assert.are.same({
        "/usr/bin/opam",
        "exec",
        "--switch=4.14.0",
        "--set-switch",
        "--root",
        "/home/user/.opam",
        "--",
        "ocamllsp",
      }, result)
    end)

    it("should handle local switch paths", function()
      local result = opam.get_command(sandbox, "/path/to/project", { "dune", "build" })

      assert.are.same({
        "/usr/bin/opam",
        "exec",
        "--switch=/path/to/project",
        "--set-switch",
        "--root",
        "/home/user/.opam",
        "--",
        "dune",
        "build",
      }, result)
    end)
  end)

  describe("is_local_switch", function()
    it("should detect local switches with dots", function()
      assert.is_true(opam.is_local_switch("."))
      assert.is_true(opam.is_local_switch("./project"))
      assert.is_true(opam.is_local_switch("../other-project"))
    end)

    it("should detect local switches with slashes", function()
      assert.is_true(opam.is_local_switch("/absolute/path"))
      assert.is_true(opam.is_local_switch("relative/path"))
    end)

    it("should not detect global switches", function()
      assert.is_false(opam.is_local_switch("4.14.0"))
      assert.is_false(opam.is_local_switch("ocaml-base-compiler"))
      assert.is_false(opam.is_local_switch("default"))
    end)
  end)

  describe("parse_version", function()
    it("should parse major.minor.patch version", function()
      local version = opam.parse_version("2.1.3")
      assert.are.same({
        major = 2,
        minor = 1,
        patch = 3,
      }, version)
    end)

    it("should parse major.minor version", function()
      local version = opam.parse_version("2.0")
      assert.are.same({
        major = 2,
        minor = 0,
        patch = nil,
      }, version)
    end)

    it("should handle whitespace", function()
      local version = opam.parse_version("  2.1.3  ")
      assert.are.same({
        major = 2,
        minor = 1,
        patch = 3,
      }, version)
    end)

    it("should return nil for invalid version", function()
      assert.is_nil(opam.parse_version("invalid"))
      assert.is_nil(opam.parse_version("2"))
      assert.is_nil(opam.parse_version(""))
    end)
  end)

  describe("supports_global_flag", function()
    it("should support global flag for version >= 2.1", function()
      assert.is_true(opam.supports_global_flag({ major = 2, minor = 1, patch = 0 }))
      assert.is_true(opam.supports_global_flag({ major = 2, minor = 2, patch = nil }))
      assert.is_true(opam.supports_global_flag({ major = 3, minor = 0, patch = 0 }))
    end)

    it("should not support global flag for version < 2.1", function()
      assert.is_false(opam.supports_global_flag({ major = 2, minor = 0, patch = 5 }))
      assert.is_false(opam.supports_global_flag({ major = 1, minor = 9, patch = nil }))
    end)
  end)

  describe("parse_variables", function()
    it("should parse opam var output", function()
      local lines = {
        "arch            x86_64",
        "os              linux",
        "opam-version    2.1.3",
        "root            /home/user/.opam",
        "",
        "# Comment line",
        "jobs            4",
      }

      local vars = opam.parse_variables(lines)
      assert.are.same({
        arch = "x86_64",
        os = "linux",
        opam_version = "2.1.3",
        root = "/home/user/.opam",
        jobs = "4",
      }, vars)
    end)

    it("should handle empty values", function()
      local lines = {
        "arch            x86_64",
        "empty-var       ",
        "os              linux",
      }

      local vars = opam.parse_variables(lines)
      assert.are.same({
        arch = "x86_64",
        os = "linux",
      }, vars)
    end)

    it("should convert hyphens to underscores in keys", function()
      local lines = {
        "opam-version    2.1.3",
        "os-distribution ubuntu",
      }

      local vars = opam.parse_variables(lines)
      assert.are.same({
        opam_version = "2.1.3",
        os_distribution = "ubuntu",
      }, vars)
    end)
  end)

  describe("create_sandbox", function()
    it("should use provided binary and root", function()
      -- Mock vim.fn.executable
      local original_executable = vim.fn.executable
      vim.fn.executable = function(cmd)
        if cmd == "/custom/opam" then
          return 1
        end
        return 0
      end

      local sandbox = opam.create_sandbox("/custom/opam", "/custom/root")

      assert.are.same({
        binary = "/custom/opam",
        root = "/custom/root",
      }, sandbox)

      -- Restore
      vim.fn.executable = original_executable
    end)

    it("should default to 'opam' binary when not provided", function()
      -- Mock vim.fn.executable
      local original_executable = vim.fn.executable
      vim.fn.executable = function(cmd)
        if cmd == "opam" then
          return 1
        end
        return 0
      end

      local sandbox = opam.create_sandbox(nil, "/custom/root")
      assert.are.equal("opam", sandbox.binary)
      assert.are.equal("/custom/root", sandbox.root)

      -- Restore
      vim.fn.executable = original_executable
    end)
  end)
end)
