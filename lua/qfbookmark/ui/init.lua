local QfbookmarkUtils = require "qfbookmark.utils"
local QfbookmarkUIUtils = require "qfbookmark.ui.utils"
local QfbookmarkUIView = require "qfbookmark.ui.view"

---@alias WinSizeCfg { row: integer, col: integer, height: integer, width: integer, title: string, title_pos: string, buf?: integer}

---@param buffer_opts QFBookBufferItem
---@param path_width integer
---@return string line
---@return QFBookBufferItem buffer_opts
local function build_entry_line_buffers(buffer_opts, path_width)
  local badge = buffer_opts.flag
  local path = QfbookmarkUIUtils.shorten_path(buffer_opts.info.name, path_width)
  local lnum = string.format(":%d", buffer_opts.info.lnum)

  local line = " " .. badge .. " " .. path .. " " .. lnum
  return line, buffer_opts
end

--- Compute optimal path column width across all mark entries
---@param mark_lists QFbookBufferMarkEntry[] | QFBookBufferItem[]
---@param max_path? integer
---@param is_buffers boolean
---@return integer
local function calc_path_width(mark_lists, is_buffers, max_path)
  max_path = max_path or 32
  local w = 15
  for _, m in ipairs(mark_lists) do
    local short
    if is_buffers then
      short = vim.fn.fnamemodify(m.info.name or "", ":~:.")
    else
      short = vim.fn.fnamemodify(m.filename or "", ":~:.")
    end
    -- keep only the last directory component + filename for display
    local parts = vim.split(short, "/", { plain = true })
    local display = #parts >= 2 and (parts[#parts - 1] .. "/" .. parts[#parts]) or parts[#parts] or short
    local len = vim.fn.strdisplaywidth(display)
    if len > w then
      w = len
    end
  end
  return math.min(w, max_path)
end

--- Compute popup width from entry content
---@param mark_lists QFbookBufferMarkEntry[]
---@param is_buffers? boolean
---@return integer
local function calc_popup_width(mark_lists, is_buffers)
  is_buffers = is_buffers or false
  local path_w = calc_path_width(mark_lists, is_buffers, 32)
  -- " N  BADGE  path ●" → 1+1+2+4+2+path+2 = path + ~12
  local estimated = path_w + 14

  local min_w = 38
  local max_w = 60
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

-- Selection state
local selected = {}
local active_cursor_selection = ""

---@param mark_lists QFbookBufferMarkEntry[]
---@param cb function
local function mark_harpoon_popup(mark_lists, cb)
  if #mark_lists == 0 then
    QfbookmarkUtils.echo_emtpy_mark()
    return
  end

  local editor = QfbookmarkUIUtils.get_editor_size()

  local height = math.max(2, math.floor(editor.height / 2))
  local original_width = calc_popup_width(mark_lists)
  local width = math.max(original_width + 20, 20)

  local col, row = QfbookmarkUIUtils.get_col_row(editor.height, editor.width, width)

  -- ── Build display lines dan harpoon_map ────────────────────────────────
  -- entries are 2 or 3 lines depending on whether symbol context exists:
  --   line 1 (header)  → harpoon_map[line_nr] = hval
  --   line 2 (detail)  → harpoon_map[line_nr] = hval
  --   line 3 (symbol)  → harpoon_map[line_nr] = hval  (only when chain != "")
  local display_lines = {}
  local entries = {}

  for idx, mark in ipairs(mark_lists) do
    local symbol = QfbookmarkUIUtils.resolve_fn_name(mark)
    local line1, line2, line3, hval = QfbookmarkUIUtils.build_entry_lines(idx, mark, original_width, symbol)

    local start_line = #display_lines + 1

    local entry = {
      id = idx,
      start_line = start_line,
      hval = hval,
      mark = mark,
      line_count = 2,
    }

    entries[idx] = entry

    display_lines[#display_lines + 1] = line1
    display_lines[#display_lines + 1] = line2
    if line3 then
      display_lines[#display_lines + 1] = line3
      entry.line_count = 3
    end
  end

  -- Ensure popup is tall enough to show all entries
  height = math.min(height, #display_lines) + 2

  -- Total mark count shown in the popup title
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
    content_map = entries,
    display_lines = display_lines,
    original_popup_mark_width = original_width,
    win_opts = wincfg,
    selected = selected,
    active = active_cursor_selection,
  }

  QfbookmarkUIView.build_popup("mark", __opts, cb)
end

---@param mark_lists QFbookBufferMark
---@param cb function
---@param load_chunk? {load_chunk: boolean, chunk: QFbookBufferMarkEntry}
local function place_mark_annotation(mark_lists, cb, load_chunk)
  load_chunk = load_chunk or {}

  local editor = QfbookmarkUIUtils.get_editor_size()

  local height = math.floor(editor.height / 5)
  local width = math.floor(editor.width / 2)

  local col, row = QfbookmarkUIUtils.get_center_col_row(height, width)

  row = row + 10

  local title_str = "📝 " .. "Mark Annotation"

  local win_buf = vim.api.nvim_create_buf(false, true)
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
      footer = "",
      footer_pos = "center",
    },
  }

  local buf = vim.api.nvim_get_current_buf()
  local curline = vim.api.nvim_win_get_cursor(0)[1]

  local __opts = {
    contents = mark_lists,
    content_map = {
      [1] = {
        hval = "mark_note",
        mark = {
          bufnr = vim.api.nvim_get_current_buf(),
          line = curline,
          col = vim.api.nvim_win_get_cursor(0)[2],
          filename = vim.api.nvim_buf_get_name(buf),
        },
      },
    },
    win_opts = wincfg,
    harpoon = "mark_note",
    is_mark_annotation = true,
    data_annotation = load_chunk,
    cb = cb,
  }

  QfbookmarkUIView.build_popup("mark_annotation", __opts, cb)
end

---@param buffer_lists table
local function buffers_popup(buffer_lists)
  -- Build display lines
  local display_lines = {}
  local entries = {}
  local path_width = calc_path_width(buffer_lists, true, 30)

  for idx, buffer in pairs(buffer_lists) do
    local line, hval = build_entry_line_buffers(buffer, path_width)
    display_lines[#display_lines + 1] = line

    local start_line = idx

    local entry = {
      id = idx,
      start_line = start_line,
      hval = hval,
      line_count = 1,
    }

    entries[idx] = entry
  end

  local editor = QfbookmarkUIUtils.get_editor_size()

  local height = math.max(2, #buffer_lists) + 1
  local width = calc_popup_width(buffer_lists)

  local col, row = QfbookmarkUIUtils.get_col_row(editor.height, editor.width, width)

  -- Total mark buffer
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
    content_map = entries,
    display_lines = display_lines,
    win_opts = wincfg,
  }

  QfbookmarkUIView.build_popup("buffer", __opts)
end

---@param note_path string
---@param cfg_note QFBookNotes
---@param is_global? boolean
local function open_note_in_float(note_path, cfg_note, is_global)
  is_global = is_global or false

  local editor = QfbookmarkUIUtils.get_editor_size()

  local resnum = tonumber(cfg_note.size:match "%d+") or 60
  local width = math.floor(editor.width * resnum / 100)
  local height = editor.height

  local row, col = QfbookmarkUIUtils.get_position(cfg_note.open_cmd.anchor, width, height)

  local shorten_path = QfbookmarkUIUtils.shorten_path(note_path, 40)
  local title_str = "📝 " .. (is_global and "Global " or "") .. "Note: " .. shorten_path

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
      footer = " Auto-save enabled ",
      footer_pos = "center",
    },
  }

  local __opts = {
    contents = {},
    win_opts = wincfg,
    is_note = true,
  }

  QfbookmarkUIView.build_popup("note", __opts)

  vim.cmd("edit " .. vim.fn.fnameescape(note_path))
end

return {
  mark_harpoon_popup = mark_harpoon_popup,
  saveqf_popup = saveqf_popup,
  buffers_popup = buffers_popup,
  place_mark_annotation = place_mark_annotation,
  open_note_in_float = open_note_in_float,
}
