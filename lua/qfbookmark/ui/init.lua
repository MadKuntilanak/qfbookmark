local QfbookmarkUtils = require "qfbookmark.utils"
local QfbookmarkUIUtils = require "qfbookmark.ui.utils"
local QfbookmarkUIView = require "qfbookmark.ui.view"

---@alias WinSizeCfg { row: integer, col: integer, height: integer, width: integer, title: string, title_pos: string, buf?: integer}

--- Build two display lines per entry:
---   Line 1 (header): " N  BADGE  path/file.lua ●"
---   Line 2 (detail): "         :lnum  preview text"
---
---@param idx integer                     1-based display index
---@param mark QFbookBufferMarkEntry      mark entry to render
---@param path_width integer              column width for path alignment
---@return string line1                   header line
---@return string line2                   detail line
---@return string harpoon                 harpoon value for lookup
local function build_entry_lines(idx, mark, path_width)
  local badge = QfbookmarkUIUtils.get_mode_badge(mark.mark_mode)
  local path = QfbookmarkUIUtils.shorten_path(mark.filename, math.min(path_width, 20))
  local cur_marker = QfbookmarkUIUtils.is_current_file(mark.filename) and " ●" or ""
  local lnum = string.format(":%d", mark.line)
  local preview = QfbookmarkUIUtils.shorten_text(mark.text or "", path_width + 4)

  -- header: " N  BADGE  plugins/qf.lua ●"
  local line1 = string.format(" %d  %s  %s%s", idx, badge, path, cur_marker)

  -- detail: 9-space indent to align under path, then lnum + preview text
  local indent = string.rep(" ", 9)
  local line2 = string.format("%s%s  %s", indent, lnum, preview)

  return line1, line2, mark.harpoon
end

local function build_entry_line_buffers(buffer_opts, path_width)
  local badge = buffer_opts.flag
  local path = QfbookmarkUIUtils.shorten_path(buffer_opts.info.name, path_width)
  local lnum = string.format(":%d", buffer_opts.info.lnum)

  local line = " " .. badge .. " " .. path .. " " .. lnum
  return line, buffer_opts
end

--- Compute optimal path column width across all mark entries
---@param enter_lists QFbookBufferMarkEntry[] | QFBufferItem[]
---@param max_path integer
---@param is_buffers? boolean
---@return integer
local function calc_path_width(enter_lists, max_path, is_buffers)
  is_buffers = is_buffers or false
  max_path = max_path or 32
  local w = 10
  for _, m in ipairs(enter_lists) do
    local short
    if is_buffers then
      short = vim.fn.fnamemodify(m.info.name or "", ":~:.")
    else
      short = vim.fn.fnamemodify(m.filename or "", ":~:.")
    end
    -- keep only the last directory component + filename for display
    local parts
    if short:match "%/" then
      parts = vim.split(short, "/", { plain = true })
    end
    local display = parts and (#parts >= 2 and (parts[#parts - 1] .. "/" .. parts[#parts]) or parts[#parts]) or short

    local len = vim.fn.strdisplaywidth(display)
    if len > w then
      w = len
    end
  end
  return math.min(w, max_path)
end

--- Compute popup width from entry content
---@param mark_lists QFbookBufferMarkEntry[]
---@return integer
local function calc_popup_width(mark_lists)
  local min_w = 38
  local max_w = 60
  local path_w = calc_path_width(mark_lists, 32)

  -- " N  BADGE  path ●" → 1+1+2+4+2+path+2 = path + ~12
  local estimated = path_w + 25
  return math.max(min_w, math.min(estimated, max_w))
end

-- ╓─────────────────────────────────────────────────────────────────────────────╖
-- ║                                    POPUP                                    ║
-- ╙─────────────────────────────────────────────────────────────────────────────╜

---@param title string
---@param target_path string
---@param cb function
---@param is_loc boolean
---@param for_what "save" | "rename"
local function saveqf_popup(title, target_path, for_what, is_loc, cb)
  local editor = QfbookmarkUIUtils.get_editor_size()
  local height = 1
  local width = math.max(2, math.ceil(editor.width * 30 / 100))

  local col, row = QfbookmarkUIUtils.get_col_row(height, width, 0, true)

  local title_str = title .. (for_what == "save" and (is_loc and " LocationList" or " Quickfix") or "")

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
      title = QfbookmarkUIUtils.format_title(title_str),
      title_pos = "center",
      footer = " <C-q>/<Esc> Quit ",
      footer_pos = "center",
    },
  }

  local __opts = {
    contents = {},
    content_map = {},
    display_lines = {},
    win_opts = wincfg,
    save = {
      title = title,
      target_path = target_path,
      is_loc = is_loc,
      cb = cb,
      for_what = for_what,
    },
  }

  QfbookmarkUIView.build_popup("save", __opts, cb)
end

---@param mark_lists QFbookBufferMarkEntry[]
---@param cb function
local function mark_harpoon_popup(buffers, mark_lists, cb)
  if #mark_lists == 0 then
    QfbookmarkUtils.echo_emtpy_mark()
    return
  end

  local editor = QfbookmarkUIUtils.get_editor_size()

  local height = math.max(1, math.floor(editor.height / 5))
  local width = calc_popup_width(mark_lists)

  local col, row = QfbookmarkUIUtils.get_col_row(editor.height, editor.width, width)

  -- ── Build display lines dan harpoon_map ────────────────────────────────
  -- two lines per entry:
  --   odd  line_nr (1,3,5,...) → header line → harpoon_map[line_nr] = hval
  --   even line_nr (2,4,6,...) → detail line → harpoon_map[line_nr] = hval (same value)
  local display_lines = {}
  ---@type table<integer, string>
  local content_map = {}

  local path_width = math.max(calc_path_width(mark_lists, 100), 20)

  for idx, mark in ipairs(mark_lists) do
    local line1, line2, hval = build_entry_lines(idx, mark, path_width)
    display_lines[#display_lines + 1] = line1
    display_lines[#display_lines + 1] = line2

    local ln1 = (idx - 1) * 2 + 1 -- line number of the header row (1-based)
    local ln2 = ln1 + 1 -- line number of the detail row
    content_map[ln1] = hval
    content_map[ln2] = hval
  end

  -- ensure popup is tall enough to show all entries (2 lines each)
  height = math.max(height, #mark_lists * 2)

  -- total mark count shown in the popup title
  local total = #mark_lists
  local icon = "🔗 "
  local title_str = total > 0 and icon .. string.format("QFMarks (%d)", total) or icon .. "QFMarks"

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
      title = QfbookmarkUIUtils.format_title(title_str),
      title_pos = "center",
      footer = " dd del · <CR> open · <C-v/s/t> split · <C-q> quit ",
      footer_pos = "center",
    },
  }

  local __opts = {
    contents = mark_lists,
    content_map = content_map,
    display_lines = display_lines,
    win_opts = wincfg,
  }

  QfbookmarkUIView.build_popup("mark", __opts, cb)
end

---@param buffer_lists table
local function buffers_popup(buffer_lists)
  -- Build display lines
  local display_lines = {}
  local content_map = {}
  local path_width = calc_path_width(buffer_lists, 30, true)

  for idx, buffer in pairs(buffer_lists) do
    local line, hval = build_entry_line_buffers(buffer, path_width)
    display_lines[#display_lines + 1] = line

    content_map[idx] = hval
  end

  local editor = QfbookmarkUIUtils.get_editor_size()

  local height = math.max(2, #buffer_lists) + 1
  local width = calc_popup_width(buffer_lists)

  local col, row = QfbookmarkUIUtils.get_col_row(editor.height, editor.width, width)

  local total = #buffer_lists
  local icon = "📑 "
  local title_str = total > 0 and icon .. string.format("QFBuffers (%d)", total) or icon .. "QFBuffers"
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

      title = QfbookmarkUIUtils.format_title(title_str),
      title_pos = "center",

      footer = " <C-q> Quit | <C-y/v/s/t> Enter/V/Split/Tab ",
      footer_pos = "center",
    },
  }

  local __opts = {
    contents = buffer_lists,
    content_map = content_map,
    display_lines = display_lines,
    win_opts = wincfg,
  }

  QfbookmarkUIView.build_popup("buffer", __opts)
end

return {
  mark_harpoon_popup = mark_harpoon_popup,
  saveqf_popup = saveqf_popup,
  buffers_popup = buffers_popup,
}
