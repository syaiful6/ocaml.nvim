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

---Build an opam command for the given root.
---@param sandbox ocaml.sandbox.opam.Sandbox
---@param args string[]
---@return string[]
local function get_opam_command_util(sandbox, args)
  local cmd = { sandbox.binary }
  local found_separator = false

  -- opam options must precede the command executed after "--".
  for _, arg in ipairs(args or {}) do
    if arg == "--" then
      table.insert(cmd, "--root")
      table.insert(cmd, sandbox.root)
      found_separator = true
    end
    table.insert(cmd, arg)
  end

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

---Return whether a switch name refers to a path.
---@param switch_name string
---@return boolean
function M.is_local_switch(switch_name)
  if vim.fs.is_absolute and vim.fs.is_absolute(switch_name) then
    return true
  end

  if switch_name:match("^%.") or switch_name:match("/") then
    return true
  end

  return false
end

---Parse an opam version string.
---@param version_string string
---@return ocaml.sandbox.opam.Version|nil
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

---Read the installed opam version.
---@param opam_binary string|nil Defaults to "opam"
---@param cb fun(version: ocaml.sandbox.opam.Version|nil, err: string|nil)
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

---Return whether this version supports `opam var --global`.
---@param version ocaml.sandbox.opam.Version
---@return boolean
function M.supports_global_flag(version)
  return version.major > 2 or (version.major == 2 and version.minor >= 1)
end

---Parse `opam var` output.
---@param lines string[]
---@return ocaml.sandbox.opam.Variables
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

---Read opam's global variables.
---@param opam_binary string|nil Defaults to "opam"
---@param cb fun(vars: ocaml.sandbox.opam.Variables|nil, err: string|nil)
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

---Find the nearest local switch at `dir` or one of its parents.
---@param switches string[] Output from `opam switch list -s`
---@param dir string
---@return string|nil
function M.find_local_switch(switches, dir)
  return M.find_local_switches(switches, dir)[1]
end

---Find local switches at `dir` or its ancestors, nearest first.
---@param switches string[] Output from `opam switch list -s`
---@param dir string
---@return string[] switches
function M.find_local_switches(switches, dir)
  local found = {}
  for _, switch in ipairs(switches) do
    if M.is_local_switch(switch) then
      local base = (switch:gsub("/+$", ""))
      if dir == switch or dir == base or vim.startswith(dir, base .. "/") then
        table.insert(found, switch)
      end
    end
  end
  table.sort(found, function(a, b)
    return #a > #b
  end)
  return found
end

---Read the switch opam would use in `dir`.
---This follows opam's precedence: `OPAMSWITCH`, a local `_opam` switch, then
---the selected global switch.
---@param sandbox ocaml.sandbox.opam.Sandbox
---@param dir string
---@param cb fun(switch: string|nil, err: string|nil)
function M.get_current_switch(sandbox, dir, cb)
  local command = get_opam_command_util(sandbox, { "switch", "show" })
  Helpers.system_lines(command, function(lines, err)
    if not lines then
      return cb(nil, err)
    end
    local switch = lines[1] and vim.trim(lines[1]) or ""
    if switch == "" then
      return cb(nil, "`opam switch show` printed nothing")
    end
    cb(switch, nil)
  end, { cwd = dir })
end

---Return the switch directory containing `bin`, `lib`, and other prefixes.
---@param sandbox ocaml.sandbox.opam.Sandbox
---@param switch string
---@return string prefix
function M.switch_prefix(sandbox, switch)
  if M.is_local_switch(switch) then
    return vim.fs.joinpath(switch, "_opam")
  end
  return vim.fs.joinpath(sandbox.root, switch)
end

---Find the local switch for `dir`.
---@param sandbox ocaml.sandbox.opam.Sandbox
---@param dir string
---@param cb fun(switch: string|nil, err: string|nil)
function M.get_local_switch(sandbox, dir, cb)
  M.get_switches(sandbox, function(switches, err)
    if not switches then
      return cb(nil, err)
    end
    cb(M.find_local_switch(switches, dir), nil)
  end)
end

---Create an opam sandbox, discovering the binary and root when omitted.
---The callback may run synchronously when discovery is unnecessary.
---@param opam_binary string|nil Defaults to "opam"
---@param opam_root string|nil Defaults to opam's configured root
---@param cb fun(sandbox: ocaml.sandbox.opam.Sandbox|nil) Receives nil if opam is unavailable
function M.create_sandbox(opam_binary, opam_root, cb)
  local binary = opam_binary or "opam"

  if vim.fn.executable(binary) == 0 then
    return cb(nil)
  end

  if opam_root then
    return cb({ binary = binary, root = opam_root })
  end

  M.get_variables(binary, function(vars)
    -- `opam var` can fail before opam is initialized.
    local root = (vars and vars.root) or vim.env.OPAMROOT or vim.fs.joinpath(vim.env.HOME, ".opam")
    cb({ binary = binary, root = root })
  end)
end

---Wrap a command with `opam exec` for the selected switch.
---@param sandbox ocaml.sandbox.opam.Sandbox
---@param switch string
---@param args string[]
---@return string[]
function M.get_command(sandbox, switch, args)
  local arguments = { "exec", "--switch=" .. switch, "--set-switch", "--" }
  for _, arg in ipairs(args or {}) do
    table.insert(arguments, arg)
  end

  return get_opam_command_util(sandbox, arguments)
end

return M
