---@mod ocaml.commands.dune
---@brief [[
---Dune build commands for OCaml development
---]]

local M = {}

local dune_job_id = nil

local function get_project_root()
  local helpers = require("ocaml.helpers")
  local root_pattern = helpers.root_pattern("dune-project", "dune-workspace", "*.opam", "_build")
  return root_pattern(vim.fn.getcwd()) or vim.fn.getcwd()
end

function M.start_watch()
  if dune_job_id then
    vim.notify("[ocaml.nvim] Dune build watch is already running", vim.log.levels.WARN)
    return
  end

  local project_root = get_project_root()
  local sandbox = require("ocaml.sandbox")
  local sandboxed_cmd = sandbox.get_command(project_root, { "dune", "build", "--watch" })

  dune_job_id = vim.fn.jobstart(sandboxed_cmd, {
    cwd = project_root,
    on_stdout = function(_, data)
      if data and #data > 1 then
        for _, line in ipairs(data) do
          if line ~= "" then
            vim.notify("[dune] " .. line, vim.log.levels.INFO)
          end
        end
      end
    end,
    on_stderr = function(_, data)
      if data and #data > 1 then
        for _, line in ipairs(data) do
          if line ~= "" then
            vim.notify("[dune] " .. line, vim.log.levels.ERROR)
          end
        end
      end
    end,
    on_exit = function(_, exit_code)
      dune_job_id = nil
      if exit_code == 0 then
        vim.notify("[ocaml.nvim] Dune build watch stopped", vim.log.levels.INFO)
      else
        vim.notify("[ocaml.nvim] Dune build watch exited with code " .. exit_code, vim.log.levels.ERROR)
      end
    end,
  })

  if dune_job_id > 0 then
    vim.notify("[ocaml.nvim] Started dune build --watch in " .. project_root, vim.log.levels.INFO)
  else
    vim.notify("[ocaml.nvim] Failed to start dune build --watch", vim.log.levels.ERROR)
    dune_job_id = nil
  end
end

function M.stop_watch()
  if not dune_job_id then
    vim.notify("[ocaml.nvim] No dune build watch process running", vim.log.levels.WARN)
    return
  end

  vim.fn.jobstop(dune_job_id)
  dune_job_id = nil
  vim.notify("[ocaml.nvim] Stopped dune build watch", vim.log.levels.INFO)
end

function M.status()
  if dune_job_id then
    vim.notify("[ocaml.nvim] Dune build watch is running (job ID: " .. dune_job_id .. ")", vim.log.levels.INFO)
  else
    vim.notify("[ocaml.nvim] Dune build watch is not running", vim.log.levels.INFO)
  end
end

return M
