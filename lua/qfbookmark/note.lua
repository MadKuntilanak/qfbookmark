local QfbookmarkUtils = require "qfbookmark.utils"
local QfbookmarkPath = require "qfbookmark.path"
local QfbookmarkPathUtils = require "qfbookmark.path.utils"
local QfbookmarkUiUtils = require "qfbookmark.ui.utils"

local M = {}

local last_position = nil

local function get_position(anchor, width, height)
  local lines = vim.o.lines
  local cols = vim.o.columns

  if anchor == "NW" then
    return 0, 0
  elseif anchor == "NE" then
    return 0, cols - width
  elseif anchor == "SW" then
    return lines - height - 2, 0
  elseif anchor == "SE" then
    return lines - height - 2, cols - width
  end
end

---@param note_path string
---@param cfg_note QFBookNotes
local function open_in_float(note_path, cfg_note)
  local QfbookmarkUIView = require "qfbookmark.ui.view"

  local editor = QfbookmarkUiUtils.get_editor_size()

  local resnum = tonumber(cfg_note.size:match "%d+") or 60
  local width = math.floor(editor.width * resnum / 100)
  local height = editor.height

  local row, col = get_position(cfg_note.open_cmd.anchor, width, height)

  local shorten_path = QfbookmarkUiUtils.shorten_path(note_path, 40)
  local title_str = "📝 Note: " .. shorten_path

  local win_buf = vim.api.nvim_create_buf(false, true)

  ---@type WinCfg
  local wincfg = {
    buf = win_buf,
    enter = true,
    wincfg = {
      relative = "editor",
      width = width,
      height = height,
      row = row,
      col = col,
      style = "minimal",
      border = "rounded",
      title = QfbookmarkUiUtils.format_title(title_str),
      title_pos = "center",
      footer = " Auto-save enabled ",
      footer_pos = "center",
    },
  }

  local __opts = {
    contents = {},
    win_opts = wincfg,
    entry_start_line = {},
  }

  QfbookmarkUIView.build_popup("note", __opts)

  vim.cmd("edit " .. vim.fn.fnameescape(note_path))

  vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave" }, {
    buffer = win_buf,
    callback = function()
      if vim.bo[win_buf].modified then
        vim.cmd "silent write"
      end
    end,
  })
end

---@param note_path string
---@param window_command string
---@param cfg_note QFBookNotes
local function toggle_note(note_path, window_command, cfg_note)
  local buf_note = QfbookmarkUtils.windows_is_opened_by_name(note_path)

  if not buf_note then
    if type(cfg_note) ~= "table" then
      vim.cmd(window_command)
      vim.cmd("edit " .. vim.fn.fnameescape(note_path))
    else
      open_in_float(note_path, cfg_note)
    end

    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_call(win, function()
      local editor = QfbookmarkUiUtils.get_editor_size()
      local resnum = tonumber(cfg_note.size:match "%d+")
      local resize = math.floor(editor.width * resnum / 100)

      vim.api.nvim_win_set_width(win, resize)
      vim.api.nvim_set_option_value("winfixheight", true, { scope = "local", win = win })
    end)

    vim.schedule(function()
      local line = vim.api.nvim_win_get_cursor(0)[1]
      if not line then
        return
      end
      local fold_start = vim.fn.foldclosed(line)
      if fold_start ~= -1 then
        vim.cmd "silent! foldopen!"
      end

      local mark
      if last_position then
        mark = last_position
      else
        -- Fallback: go to last known cursor position (mark ")
        mark = vim.api.nvim_buf_get_mark(0, '"')
      end
      local line_count = vim.api.nvim_buf_line_count(0)

      if mark[1] > 0 and mark[1] <= line_count then
        pcall(vim.api.nvim_win_set_cursor, 0, mark)
      end
    end)
  else
    local wins = vim.fn.win_findbuf(buf_note)
    for _, winid in ipairs(wins) do
      if winid and vim.api.nvim_win_is_valid(winid) then
        vim.api.nvim_set_current_win(winid)
        local row = vim.api.nvim_win_get_cursor(0)[1]
        local col = vim.api.nvim_win_get_cursor(0)[2]
        last_position = { row, col }
      end
    end

    QfbookmarkUtils.delete_buffer_by_name(note_path)
  end
end

---@param is_global boolean
---@param window_command string
---@param cfg_note QFBookNotes
function M.handle_open(is_global, window_command, cfg_note)
  local note_path

  local file_extension = "." .. cfg_note.filetype

  if is_global then
    QfbookmarkPath.setup_path(is_global)
    note_path = QfbookmarkPath.get_target_path(is_global)
    note_path = note_path .. "/note" .. file_extension
  else
    if cfg_note.current_project.enabled then
      note_path = cfg_note.current_project.filename
      note_path = vim.uv.cwd() .. "/" .. note_path
    else
      QfbookmarkPath.setup_path(is_global)
      note_path = QfbookmarkPathUtils.get_base_path_root(note_path, is_global) .. file_extension
    end
  end

  if not QfbookmarkPathUtils.is_file(note_path) then
    QfbookmarkPathUtils.create_file(note_path)
  end

  toggle_note(note_path, window_command, cfg_note)
end

return M
