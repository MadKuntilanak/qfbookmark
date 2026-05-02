local QfbookmarkUtils = require "qfbookmark.utils"
local QfbookmarkPath = require "qfbookmark.path"
local QfbookmarkPathUtils = require "qfbookmark.path.utils"

local M = {}

local last_winid = 0
local was_open = true

---@param path string
---@param ft_ext string
---@param first_close boolean
---@param window_command string
local function toggle_note(path, ft_ext, window_command, first_close)
  local current_buf = vim.api.nvim_get_current_buf()
  local filetype = vim.bo[current_buf].filetype
  if filetype ~= ft_ext then
    last_winid = vim.api.nvim_get_current_win()
  end

  local note_win = QfbookmarkUtils.windows_is_opened { ft_ext }

  -- close first
  if first_close and note_win.found then
    if vim.api.nvim_win_is_valid(note_win.winid) then
      vim.api.nvim_win_close(note_win.winid, true)
    else
      QfbookmarkUtils.delete_buffer_by_name(path)
    end
  end

  -- check again
  note_win = QfbookmarkUtils.windows_is_opened { ft_ext }
  if not note_win.found then
    vim.cmd(window_command)
    vim.cmd("edit " .. vim.fn.fnameescape(path))
    vim.api.nvim_set_option_value("winfixheight", true, { scope = "local", win = 0 })
    was_open = false
  else
    if vim.api.nvim_win_is_valid(note_win.winid) then
      vim.api.nvim_win_close(note_win.winid, true)
      was_open = true
    else
      QfbookmarkUtils.delete_buffer_by_name(path)
    end
  end

  if was_open and last_winid and vim.api.nvim_win_is_valid(last_winid) then
    pcall(vim.api.nvim_set_current_win, last_winid)
  end
end

---@param is_global boolean
---@param window_command string
---@param win_opts QFBookNotes
---@param first_close? boolean
function M.handle_open(is_global, window_command, win_opts, first_close)
  first_close = first_close or false

  QfbookmarkPath.setup_path(is_global)
  local path = QfbookmarkPath.get_target_path(is_global)
  local file_extension = "." .. win_opts.file_ext

  if is_global then
    path = path .. "/note" .. file_extension
  else
    path = QfbookmarkPathUtils.get_base_path_root(path, is_global) .. file_extension
  end
  ---
  toggle_note(path, win_opts.filetype, window_command, first_close)
end

return M
