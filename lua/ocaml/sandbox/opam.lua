---@mod ocaml.sandbox.opam Opam sandbox operations
---
---@brief [[
---WARNING: This is not part of the public API. It may change without warning.
---Use at your own risk.

---@brief ]]

local Helpers = require("ocaml.helpers")

---@class ocaml.sandbox.Opam
local M = {}

---@class ocaml.sandbox.opam.Sandbox
---@field binary string The path to the opam binary
---@field root string The path to the opam root

--- Get the opam command to run in the sandbox
--- @param sandbox ocaml.sandbox.opam.Sandbox The opam sandbox
--- @param args string[] Additional arguments to pass to opam
--- @return string[]|nil The opam command, or nil if the sandbox is not valid
local function get_opam_command_util(sandbox, args)
  local cmd = { sandbox.binary }
  local found_separator = false

  -- Look for "--" separator and insert root flag before it
  for _, arg in ipairs(args or {}) do
    if arg == "--" then
      table.insert(cmd, "--root")
      table.insert(cmd, sandbox.root)
      found_separator = true
    end
    table.insert(cmd, arg)
  end

  -- If no "--" separator found, append root flag at the end
  if not found_separator then
    table.insert(cmd, "--root")
    table.insert(cmd, sandbox.root)
  end

  return cmd
end

---@class ocaml.sandbox.opam.Version
---@field major number The major version number
---@field minor number The minor version number
---@field patch number|nil The patch version number

---@class ocaml.sandbox.opam.Variables
---@field arch string|nil Target architecture
---@field exe string|nil Suffix needed for executable filenames
---@field jobs string|nil Number of parallel jobs
---@field make string|nil The 'make' command to use
---@field opam_version string|nil Currently running opam version
---@field os string|nil Operating system
---@field os_distribution string|nil OS distribution
---@field os_family string|nil OS family
---@field os_version string|nil OS version
---@field root string|nil Current opam root directory
---@field switch string|nil Current switch identifier

--- Get the list of switches in the sandbox
--- @param sandbox ocaml.sandbox.opam.Sandbox The opam sandbox
--- @param cb fun(switches: string[]|nil, err: string|nil)
function M.get_switches(sandbox, cb)
  local command = get_opam_command_util(sandbox, { "switch", "list", "-s" })
  Helpers.system_lines(command, function(lines, err)
    if not lines then
      return cb(nil, err)
    end
    local switches = {}
    for _, line in ipairs(lines) do
      local trimmed = vim.trim(line)
      if trimmed ~= "" then
        table.insert(switches, trimmed)
      end
    end
    cb(switches, nil)
  end)
end

--- Check if a switch is local (is an absolute or relative path)
--- This follows the same logic as VSCode OCaml plugin's Path.is_absolute approach
--- @param switch_name string The switch name to check
--- @return boolean True if the switch appears to be local
function M.is_local_switch(switch_name)
  if vim.fs.is_absolute and vim.fs.is_absolute(switch_name) then
    return true
  end

  -- Check for relative paths (starts with . or contains /)
  -- This covers cases like ".", "./project", "../other-project", "relative/path"
  if switch_name:match("^%.") or switch_name:match("/") then
    return true
  end

  -- Everything else (like "4.14.0", "default", "ocaml-base-compiler") is a global switch
  return false
end

--- Parse opam version string into components
--- @param version_string string The version string from opam --version
--- @return ocaml.sandbox.opam.Version|nil Parsed version, or nil if parsing failed
function M.parse_version(version_string)
  local trimmed = vim.trim(version_string)
  local major, minor, patch = trimmed:match("(%d+)%.(%d+)%.?(%d*)")

  if not major or not minor then
    return nil
  end

  return {
    major = tonumber(major),
    minor = tonumber(minor),
    patch = patch and patch ~= "" and tonumber(patch) or nil,
  }
end

--- Get opam version
--- @param opam_binary string|nil The opam binary path (defaults to "opam")
--- @param cb fun(version: ocaml.sandbox.opam.Version|nil, err: string|nil)
function M.get_version(opam_binary, cb)
  Helpers.system_lines({ opam_binary or "opam", "--version" }, function(lines, err)
    if not lines then
      return cb(nil, err)
    end
    if #lines == 0 then
      return cb(nil, "No version output")
    end
    local version = M.parse_version(lines[1])
    if not version then
      return cb(nil, "Cannot parse opam version: " .. lines[1])
    end
    cb(version, nil)
  end)
end

--- Check if opam version supports --global flag (>= 2.1)
--- @param version ocaml.sandbox.opam.Version The version to check
--- @return boolean True if version supports --global flag
function M.supports_global_flag(version)
  return version.major > 2 or (version.major == 2 and version.minor >= 1)
end

--- Parse opam var output into a table
--- @param lines string[] Lines from opam var command output
--- @return ocaml.sandbox.opam.Variables Parsed variables
function M.parse_variables(lines)
  local vars = {}

  for _, line in ipairs(lines) do
    local trimmed = vim.trim(line)
    if trimmed ~= "" and not trimmed:match("^#") then
      local key, value = trimmed:match("^([%w%-_]+)%s+([^#]*)")
      if key and value then
        key = key:gsub("-", "_")
        value = vim.trim(value)
        if value ~= "" then
          vars[key] = value
        end
      end
    end
  end

  return vars
end

--- Get opam variables using opam var command
--- @param opam_binary string|nil The opam binary path (defaults to "opam")
--- @param cb fun(vars: ocaml.sandbox.opam.Variables|nil, err: string|nil)
function M.get_variables(opam_binary, cb)
  M.get_version(opam_binary, function(version, err)
    if not version then
      return cb(nil, err)
    end

    local command = { opam_binary or "opam", "var" }
    if M.supports_global_flag(version) then
      table.insert(command, "--global")
    end

    Helpers.system_lines(command, function(lines, var_err)
      if not lines then
        return cb(nil, var_err)
      end
      cb(M.parse_variables(lines), nil)
    end)
  end)
end

--- Find the local switch for a directory among a list of switches
--- @param switches string[] Switch names, as listed by `opam switch list -s`
--- @param dir string The directory to check
--- @return string|nil The local switch name, or nil if none found
function M.find_local_switch(switches, dir)
  for _, switch in ipairs(switches) do
    if M.is_local_switch(switch) and switch == dir then
      return switch
    end
  end
end

--- Get the local switch for a directory, if any
--- @param sandbox ocaml.sandbox.opam.Sandbox The opam sandbox
--- @param dir string The directory to check
--- @param cb fun(switch: string|nil, err: string|nil)
function M.get_local_switch(sandbox, dir, cb)
  M.get_switches(sandbox, function(switches, err)
    if not switches then
      return cb(nil, err)
    end
    cb(M.find_local_switch(switches, dir), nil)
  end)
end

--- Create an opam sandbox, detecting opam binary and root automatically
--- This mimics the VSCode OCaml Platform approach.
--- `cb` is called synchronously when no detection is needed.
--- @param opam_binary string|nil The opam binary path (defaults to "opam")
--- @param opam_root string|nil The opam root directory (defaults to auto-detected root)
--- @param cb fun(sandbox: ocaml.sandbox.opam.Sandbox|nil) nil when opam is not available
function M.create_sandbox(opam_binary, opam_root, cb)
  local binary = opam_binary or "opam"

  if vim.fn.executable(binary) == 0 then
    return cb(nil)
  end

  if opam_root then
    return cb({ binary = binary, root = opam_root })
  end

  M.get_variables(binary, function(vars)
    -- Fall back to the environment variable or the default location
    local root = (vars and vars.root) or vim.env.OPAMROOT or vim.fs.joinpath(vim.env.HOME, ".opam")
    cb({ binary = binary, root = root })
  end)
end

--- Get the opam command to run in the sandbox
--- @param sandbox ocaml.sandbox.opam.Sandbox The opam sandbox
--- @param switch string The opam switch to use
--- @param args string[] Additional arguments to pass to opam
--- @return string[]|nil The opam command, or nil if the sandbox is not valid
function M.get_command(sandbox, switch, args)
  local arguments = { "exec", "--switch=" .. switch, "--set-switch", "--" }
  -- append user args after the "--" separator
  for _, arg in ipairs(args or {}) do
    table.insert(arguments, arg)
  end

  return get_opam_command_util(sandbox, arguments)
end

return M
