local PickerUtils = require "qfbookmark.pickers.utils"
local QfbookmarkUtils = require "qfbookmark.utils"

local M = {}

local function default_picker()
  return "default"
end

local silent_warn_notify = false

---@param picker_name string?
local function get_picker(picker_name)
  picker_name = picker_name or ""

  if PickerUtils.is_blank(picker_name) or silent_warn_notify then
    picker_name = default_picker()
  end

  local ok, picker = pcall(require, string.format("qfbookmark.pickers.%s", picker_name))

  if not ok then
    if not silent_warn_notify then
      QfbookmarkUtils.warn(
        string.format(
          "The picker `%s` has not been implemented yet.\nFalling back to the default `vim.ui.select`.",
          picker_name
        )
      )

      silent_warn_notify = true
    end

    return get_picker "default"
  end

  return picker
end

---@param config QFBookmarkConfig
function M.handle_state(config)
  local picker_name = config.picker
  local picker = get_picker(picker_name)

  local contents = {}

  if vim.tbl_isempty(contents) then
    contents = { "Load" }

    local data_loclists = QfbookmarkUtils.get_list_qf(true)
    local data_qflists = QfbookmarkUtils.get_list_qf(false)

    if #data_loclists.items > 0 then
      contents[#contents + 1] = "Save Loclist"
    end

    if #data_qflists.items > 0 then
      contents[#contents + 1] = "Save Qflist"
    end

    table.sort(contents)
  end

  picker.set_state(config, contents)
end

return M
