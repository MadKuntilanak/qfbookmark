local Config = require("qfbookmark.config").defaults
local QfbookmarkUtils = require "qfbookmark.utils"

local loaded = false
local Trouble

local silent_notify = false

local function setup_trouble()
  if loaded then
    return Trouble
  end

  local ok, _ = pcall(require, "trouble")
  if not ok then
    if not silent_notify then
      QfbookmarkUtils.error "This integration requires `folke/trouble.nvim` (https://github.com/folke/trouble.nvim)"
      return
    end
  end

  Trouble = require "trouble"
  loaded = true

  return Trouble
end

local M = {}

---@return QFBookLists
local data_troubles = function()
  ---@type QFBookLists
  local list_items = {
    items = {},
    title = "",
  }

  if vim.bo.filetype == "trouble" then
    local items = Trouble.get_items()

    for _, item in pairs(items) do
      table.insert(list_items.items, {
        bufnr = item.buf,
        text = item.text,
        lnum = item.pos[1],
        col = item.pos[2],
        filename = item.filename,
      })

      list_items.title = "Trouble-" .. item.source
    end
  end

  return list_items
end

---@param list_type QFBookListType
---@param is_loc? boolean
local function toggle_trouble_window(list_type, is_loc)
  is_loc = is_loc or false

  local list_items = data_troubles()
  local qf_win = QfbookmarkUtils.windows_is_opened { "trouble" }
  if qf_win.found then
    Trouble.close()
  end

  local open_cmd
  if list_type == "loclist" then
    open_cmd = Config.window.layout.lopen
  elseif list_type == "quickfix" then
    open_cmd = Config.window.layout.copen
  end

  QfbookmarkUtils.save_to_qf_and_auto_open_qf(list_items, open_cmd, is_loc)
end

---@param list_type QFBookListType
---@param is_loc? boolean
local function toggle_qf_window(list_type, is_loc)
  is_loc = is_loc or QfbookmarkUtils.is_loclist()

  local qf_win = QfbookmarkUtils.windows_is_opened { "qf" }
  local close_win
  if qf_win.found then
    if is_loc then
      close_win = "lclose"
    else
      close_win = "cclose"
    end
  end

  vim.cmd(close_win)

  if list_type == "loclist" then
    vim.cmd.Trouble "loclist focus"
  else
    vim.cmd.Trouble "quickfix focus"
  end
end

---@param is_trouble_ft? boolean
---@param list_type QFBookListType
---@param is_loc? boolean
function M.handle_toggle_qf(is_trouble_ft, list_type, is_loc)
  Trouble = setup_trouble()
  if not Trouble then
    return
  end

  is_loc = is_loc or false
  is_trouble_ft = is_trouble_ft or false
  if is_trouble_ft then
    toggle_trouble_window(list_type, is_loc)
  else
    toggle_qf_window(list_type, is_loc)
  end
end

return M
