---@mod ocaml.sandbox.opam Opam sandbox operations
---
---@brief [[
---WARNING: This is not part of the public API. It may change without warning.
---Use at your own risk.

---@brief ]]

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
--- @return string[]|nil switches The list of switch names, or nil on error
--- @return string|nil error The error message if any
function M.get_switches(sandbox)
  local args = { "switch", "list", "-s" }
  local command = get_opam_command_util(sandbox, args)
  if not command then
    return nil, "Invalid sandbox"
  end

  local output = vim.fn.systemlist(command)
  if vim.v.shell_error ~= 0 then
    return nil, "Error executing opam command: " .. table.concat(command, " ")
  end

  local switches = {}
  for _, line in ipairs(output) do
    local trimmed = vim.trim(line)
    if trimmed ~= "" then
      table.insert(switches, trimmed)
    end
  end

  return switches, nil
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
--- @return ocaml.sandbox.opam.Version|nil Version info, or nil on error
--- @return string|nil error The error message if any
function M.get_version(opam_binary)
  local command = { opam_binary or "opam", "--version" }
  local output = vim.fn.systemlist(command)

  if vim.v.shell_error ~= 0 then
    return nil, "Error executing opam --version"
  end

  if #output == 0 then
    return nil, "No version output"
  end

  return M.parse_version(output[1]), nil
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
--- @return ocaml.sandbox.opam.Variables|nil Variables or nil on error
--- @return string|nil error The error message if any
function M.get_variables(opam_binary)
  local version, err = M.get_version(opam_binary)
  if not version then
    return nil, err
  end

  local command = { opam_binary or "opam", "var" }
  if M.supports_global_flag(version) then
    table.insert(command, "--global")
  end

  local output = vim.fn.systemlist(command)

  if vim.v.shell_error ~= 0 then
    return nil, "Error executing opam var command"
  end

  return M.parse_variables(output), nil
end

--- Get the local switch for a directory, if any
--- @param sandbox ocaml.sandbox.opam.Sandbox|nil The opam sandbox
--- @param dir string The directory to check
--- @return string|nil The local switch name, or nil if none found
function M.get_local_switch(sandbox, dir)
  sandbox = sandbox or M.create_sandbox()
  if not sandbox then
    return nil
  end
  local switches = M.get_switches(sandbox)
  if switches == nil then
    return nil
  end
  -- then check for a local switch
  for _, switch in ipairs(switches) do
    --- check if the switch is local and equals the given directory
    if M.is_local_switch(switch) and switch == dir then
      return switch
    end
  end
end

--- Create an opam sandbox, detecting opam binary and root automatically
--- This mimics the VSCode OCaml Platform approach
--- @param opam_binary string|nil The opam binary path (defaults to detected opam)
--- @param opam_root string|nil The opam root directory (defaults to auto-detected root)
--- @return ocaml.sandbox.opam.Sandbox|nil The sandbox, or nil if opam is not available
function M.create_sandbox(opam_binary, opam_root)
  local binary = opam_binary or "opam"

  -- Check if opam binary is available
  if vim.fn.executable(binary) == 0 then
    return nil
  end

  local root = opam_root
  if not root then
    -- Try to detect opam root using opam var root command
    local vars, _ = M.get_variables(opam_binary)

    if vars and vars.root then
      root = vars.root
    else
      -- Fallback to environment variable or default
      root = vim.env.OPAMROOT or (vim.env.HOME .. "/.opam")
    end
  end

  return {
    binary = binary,
    root = root,
  }
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
