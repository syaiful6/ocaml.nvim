---
---@brief [[
---
---WARNING: This is not part of the public API. It may change without warning.
---Use at your own risk.

---@brief ]]

----@class ocaml.Helpers
local M = {}

---@param path string
---@return string stripped_path For zipfile: or tarfile: virtual paths, returns the path to the archive. Other paths are returned unaltered.
--- Taken from nvim-lspconfig
local function strip_archive_subpath(path)
  -- Matches regex from zip.vim / tar.vim
  path = vim.fn.substitute(path, "zipfile://\\(.\\{-}\\)::[^\\\\].*$", "\\1", "") or path
  path = vim.fn.substitute(path, "tarfile:\\(.\\{-}\\)::.*$", "\\1", "") or path
  return path
end

---@param path string the file path to search in
---@param ... string Search patterns (can be globs)
---@return string|nil The first file that matches the globs
local function find_file(path, ...)
  for _, search_term in ipairs(vim.iter({ ... }):flatten():totable()) do
    local results = vim.fn.glob(vim.fs.joinpath(path, search_term), true, true)
    if #results > 0 then
      return results[1]
    end
  end
end

---Iterate the path until we find the rootdir.
---@param startpath string The start path
---@return fun(_:any,path:string):(string?,string?)
---@return string startpath
---@return string startpath
local function iterate_parents(startpath)
  ---@param _ any Ignored
  ---@param path string file path
  ---@return string|nil path
  ---@return string|nil startpath
  local function it(_, path)
    local next = vim.fn.fnamemodify(path, ":h")
    if not next or vim.fn.isdirectory(next) == 0 or next == path or next == "/nix/store" then
      return
    end
    if vim.uv.fs_realpath(next) then
      return next, startpath
    end
  end
  return it, startpath, startpath
end

---@param startpath string The start path to search upward from
---@param matcher fun(path:string):string|nil
---@return string|nil
local function search_ancestors(startpath, matcher)
  if matcher(startpath) then
    return startpath
  end
  local max_iterations = 100
  for path in iterate_parents(startpath) do
    max_iterations = max_iterations - 1
    if max_iterations == 0 then
      return
    end
    if not path then
      return
    end
    if matcher(path) then
      return path
    end
  end
end

---@param ... string Globs to match in the root directory
---@return fun(path:string):(string|nil)
function M.root_pattern(...)
  local args = vim.iter({ ... }):flatten():totable()
  local function matcher(path)
    return find_file(path, unpack(args))
  end
  return function(path)
    local startpath = strip_archive_subpath(path)
    return search_ancestors(startpath, matcher)
  end
end

---@param path string
---@return string escaped_path
function M.escape_glob_wildcards(path)
  local escaped_path = path:gsub("([%[%]%?%*])", "\\%1")
  return escaped_path
end

---Default timeout for external commands, in milliseconds.
M.SYSTEM_TIMEOUT = 10000

---Run a command asynchronously and return its stdout split into lines.
---`cb` always runs on the main loop, so it may call any API.
---@param cmd string[]
---@param cb fun(lines: string[]|nil, err: string|nil)
---@param opts? { timeout?: integer, cwd?: string }
function M.system_lines(cmd, cb, opts)
  opts = opts or {}
  local ok, err = pcall(vim.system, cmd, {
    text = true,
    cwd = opts.cwd,
    timeout = opts.timeout or M.SYSTEM_TIMEOUT,
  }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        local reason = result.signal ~= 0 and ("killed by signal " .. result.signal) or ("exit code " .. result.code)
        local stderr = vim.trim(result.stderr or "")
        return cb(
          nil,
          ("`%s` failed (%s)%s"):format(table.concat(cmd, " "), reason, stderr ~= "" and ": " .. stderr or "")
        )
      end
      cb(vim.split(result.stdout or "", "\n", { trimempty = true }), nil)
    end)
  end)
  -- vim.system throws synchronously when the executable cannot be spawned
  if not ok then
    vim.schedule(function()
      cb(nil, tostring(err))
    end)
  end
end

return M
