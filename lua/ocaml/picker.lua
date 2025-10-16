---@mod ocaml.picker
---@brief [[
--- Abstraction layer for fuzzy pickers (fzf-lua, telescope, vim.ui.select)
---]]

local M = {}

---@class ocaml.picker.SelectOpts
---@field prompt string Prompt text
---@field format_item fun(item: any): string Format function for display
---@field on_choice fun(item: any) Callback when item is selected

---Check if a plugin is available
---@param plugin_name string
---@return boolean
local function has_plugin(plugin_name)
  local ok, _ = pcall(require, plugin_name)
  return ok
end

---Create fallback vim.ui.select picker
---@param items any[]
---@param opts ocaml.picker.SelectOpts
local function fallback_picker(items, opts)
  vim.ui.select(items, {
    prompt = opts.prompt,
    format_item = opts.format_item,
  }, function(choice)
    if choice then
      opts.on_choice(choice)
    end
  end)
end

---Show a picker for selecting from items
---@param items any[]
---@param opts ocaml.picker.SelectOpts
function M.select(items, opts)
  if has_plugin("fzf-lua") then
    local fzf = require("fzf-lua")
    local items_map = {}
    local entries = {}

    for _, item in ipairs(items) do
      local display = opts.format_item(item)
      items_map[display] = item
      table.insert(entries, display)
    end

    fzf.fzf_exec(entries, {
      prompt = opts.prompt,
      actions = {
        ["default"] = function(selected)
          if selected and #selected > 0 then
            local item = items_map[selected[1]]
            if item then
              opts.on_choice(item)
            end
          end
        end,
      },
    })
  elseif has_plugin("telescope") then
    local pickers = require("telescope.pickers")
    local finders = require("telescope.finders")
    local conf = require("telescope.config").values
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")

    pickers
      .new({}, {
        prompt_title = opts.prompt,
        finder = finders.new_table({
          results = items,
          entry_maker = function(item)
            return {
              value = item,
              display = opts.format_item(item),
              ordinal = opts.format_item(item),
            }
          end,
        }),
        sorter = conf.generic_sorter({}),
        attach_mappings = function(prompt_bufnr, _)
          actions.select_default:replace(function()
            local selection = action_state.get_selected_entry()
            actions.close(prompt_bufnr)
            if selection then
              opts.on_choice(selection.value)
            end
          end)
          return true
        end,
      })
      :find()
  else
    fallback_picker(items, opts)
  end
end

return M
