local Config = require("qfbookmark.config").defaults

local QfbookmarkUtils = require "qfbookmark.utils"

local M = {}

---@param direction "above" | "bottom"
---@param fn fun(list_type: QFBookListType, is_loc?:boolean)
function M.move_to(direction, fn)
  if vim.bo.filetype ~= "qf" then
    return
  end

  local cmd_open
  local list_type

  if QfbookmarkUtils.is_loclist() then
    cmd_open = direction == "above" and "aboveleft lopen" or "belowright lopen"
    Config.window.quickfix.lopen = cmd_open
    list_type = "loclist"
  else
    cmd_open = direction == "above" and "aboveleft copen" or "belowright copen"
    Config.window.quickfix.copen = cmd_open
    list_type = "quickfix"
  end

  fn(list_type, true)
  vim.cmd(cmd_open)
end

local note_window_layouts
local window_open_vim_cmds = { "botright", "aboveleft", "belowright", "topleft" }

---@return table
local function get_wins_note_layouts()
  if note_window_layouts then
    return note_window_layouts
  end

  local wins_layouts = {}

  for _, win_cmd in pairs(window_open_vim_cmds) do
    wins_layouts[#wins_layouts + 1] = win_cmd .. " split"
    wins_layouts[#wins_layouts + 1] = win_cmd .. " vsplit"
  end

  if #wins_layouts > 0 then
    note_window_layouts = wins_layouts
  end

  return note_window_layouts
end

local current_idx_win_layout = 0

---@return string
function M.get_next_rotate_note_window()
  local win_layouts = get_wins_note_layouts()

  current_idx_win_layout = current_idx_win_layout + 1

  if current_idx_win_layout > #win_layouts then
    current_idx_win_layout = 1
  end

  return win_layouts[current_idx_win_layout]
end

---@param cfg_note QFBookWindowNotes
function M.get_size_note_window(cfg_note)
  if type(cfg_note.open_cmd) == "table" then
    QfbookmarkUtils.warn "Invalid configuration: `open_cmd` should be something like 'botright vsplit'"
    return
  end

  local wins_layouts = {}

  for _, win_cmd in pairs(window_open_vim_cmds) do
    wins_layouts[#wins_layouts + 1] = win_cmd .. " " .. "split"
    wins_layouts[#wins_layouts + 1] = win_cmd .. " " .. "vsplit"
  end

  local win_split_wsize, win_vsplit_wsize

  local open_cmd = tostring(cfg_note.open_cmd)
  local str_win_cmd = vim.split(open_cmd, " ")
  local str_first = str_win_cmd[1]

  local str_second = ""
  local str_third = ""

  if str_win_cmd[2] then
    str_second = str_win_cmd[2]
    str_third = "v" .. str_win_cmd[2]
  else
    str_second = "split"
    str_third = "vsplit"
  end

  win_split_wsize = str_first .. " " .. str_second
  win_vsplit_wsize = str_first .. " " .. str_third

  local win_cmd

  for _, win in pairs(wins_layouts) do
    if win == win_split_wsize then
      win_cmd = win
      break
    end
    if win == win_vsplit_wsize then
      win_cmd = win
      break
    end
  end

  str_win_cmd = vim.split(win_cmd, " ")

  if str_win_cmd[2] == "split" then
    win_cmd = str_win_cmd[1] .. " " .. str_win_cmd[2]
  else
    win_cmd = str_win_cmd[1] .. " " .. str_win_cmd[2]
  end

  return win_cmd
end

return M
