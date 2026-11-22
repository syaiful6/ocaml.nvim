---Fake `vim.system` for specs.
---
---Responses are keyed by the full command line (`table.concat(cmd, " ")`), so
---a spec states exactly which commands it expects. A command without a
---response fails to spawn, like a missing executable does.
---
---  local system = require("tests.helpers.system")
---  local calls = system.install({
---    ["opam --version"] = { stdout = "2.3.0\n" },
---    ["opam var --global"] = { code = 1, stderr = "boom" },
---  })
---  ...
---  system.restore()
local M = {}

---@class tests.SystemResponse
---@field code? integer Default 0.
---@field stdout? string
---@field stderr? string
---Side effect of the command, such as creating a file, run when it "exits".
---@field effect? fun(cmd: string[], opts: table)

---@class tests.SystemCall
---@field cmd string[]
---@field opts table

local original = nil

---Replace `vim.system`. Returns the list that records each call.
---@param responses table<string, tests.SystemResponse>
---@return tests.SystemCall[]
function M.install(responses)
  original = original or vim.system
  local calls = {}
  ---@param cmd string[]
  ---@param opts table|nil
  ---@param on_exit fun(result: table)|nil
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.system = function(cmd, opts, on_exit)
    table.insert(calls, { cmd = vim.deepcopy(cmd), opts = vim.deepcopy(opts or {}) })
    local response = responses[table.concat(cmd, " ")]
    if not response then
      error("ENOENT: no stubbed response for `" .. table.concat(cmd, " ") .. "`")
    end
    local result = {
      code = response.code or 0,
      signal = 0,
      stdout = response.stdout or "",
      stderr = response.stderr or "",
    }
    -- The real vim.system calls on_exit later, from the event loop.
    vim.schedule(function()
      if response.effect then
        response.effect(cmd, opts or {})
      end
      if on_exit then
        on_exit(result)
      end
    end)
    return {
      pid = 0,
      wait = function()
        return result
      end,
      kill = function() end,
    }
  end
  return calls
end

---Put the real `vim.system` back.
function M.restore()
  if original then
    vim.system = original
    original = nil
  end
end

---Command lines of the recorded calls, for compact assertions.
---@param calls tests.SystemCall[]
---@return string[]
function M.lines(calls)
  return vim.tbl_map(function(call)
    return table.concat(call.cmd, " ")
  end, calls)
end

return M
