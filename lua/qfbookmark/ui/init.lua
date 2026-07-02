local QfbookmarkUtils = require "qfbookmark.utils"
local QfbookmarkUIUtils = require "qfbookmark.ui.utils"
local QfbookmarkUIView = require "qfbookmark.ui.view"

---@alias WinSizeCfg { row: integer, col: integer, height: integer, width: integer, title: string, title_pos: string, buf?: integer}

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
    QfbookmarkUtils.echo_empty_mark()
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

---@param mark_lists QFBookmarkBufferMark
---@param cb function
---@param load_chunk? {load_chunk: boolean, chunk: QFbookBufferMarkEntry}
local function place_mark_annotation(mark_lists, cb, load_chunk)
  load_chunk = load_chunk or {}

  local editor = QfbookmarkUIUtils.get_editor_size()

  local height = math.floor(editor.height / 5)
  local width = math.floor(editor.width / 2)

  -- local col, row = QfbookmarkUIUtils.get_center_col_row(height, width)
  -- local cursor = vim.api.nvim_win_get_cursor(0)

  -- row = row + 10
  local title_str = "📝 " .. "Mark Annotation"

  local row = QfbookmarkUIUtils.get_row_cursor_relative(height, 2)

  local win_buf = vim.api.nvim_create_buf(false, true)
  local wincfg = {
    buf = win_buf,
    enter = true,
    wincfg = {
      relative = "cursor",
      width = width,
      height = height,
      row = row,
      col = 0,
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

---@param bufnr integer
---@param key integer
---@param opts? QFbookPreviewOpts
local function preview_mark_annotation(bufnr, key, opts)
  opts = opts or {}

  local editor = QfbookmarkUIUtils.get_editor_size()

  local height = math.floor(editor.height / 1.5)
  local width = math.floor(editor.width / 1.5)

  local title_str = "  " .. "Sent context"

  local win_buf = vim.api.nvim_create_buf(false, true)
  local wincfg = {
    buf = win_buf,
    enter = true,
    wincfg = {
      relative = "editor",
      row = math.floor((vim.o.lines - height) / 2),
      col = math.floor((vim.o.columns - width) / 2),
      width = width,
      height = height,
      style = "minimal",
      border = "rounded",
      title = QfbookmarkUIUtils.format_title(title_str),
      title_pos = "center",
      footer = " <CR> send · <Tab> switch template · y copy only · <Esc> cancel ",
      footer_pos = "center",
    },
  }

  local __opts = {
    win_opts = wincfg,
    opts_mark_preview = opts,
    mark_preview_key = key,
    mark_preview_bufnr = bufnr,
    title_str = title_str,
  }

  QfbookmarkUIView.build_popup("preview_mark_annotation", __opts)
end

---Open a small floating input to capture the short note text for an annotation.
---@param category string
---@param on_submit fun(text: string)
---@param on_cancel? fun()
---@param load_chunk? {load_chunk: boolean, chunk: QFbookBufferMarkEntry}
---@param opts? { anchor?: "cursor"|"editor", keyword_def: QFBookSpec }
local function input_note(category, on_submit, on_cancel, load_chunk, opts)
  opts = opts or {}
  local anchor = opts.anchor or "cursor"

  local width = 44

  local win_config
  if anchor == "editor" then
    win_config = {
      relative = "editor",
      row = math.floor((vim.o.lines - 3) / 2),
      col = math.floor((vim.o.columns - 46) / 2),
      width = 44,
      height = 1,
    }
  else
    win_config = {
      relative = "cursor",
      row = 1,
      col = 0,
      width = width,
      height = 1,
    }
  end

  local buf = vim.api.nvim_create_buf(false, true)
  local wincfg = {
    buf = buf,
    enter = true,
    wincfg = vim.tbl_extend("force", win_config, {
      style = "minimal",
      border = "rounded",
      title = QfbookmarkUIUtils.format_title(category),
      title_pos = "center",
      footer = " <CR> save · <Esc> cancel ",
      noautocmd = true,
      footer_pos = "center",
    }),
  }

  vim.bo[buf].buftype = "prompt"
  vim.fn.prompt_setprompt(buf, "> ")

  local curbuf = vim.api.nvim_get_current_buf()
  local curline = vim.api.nvim_win_get_cursor(0)[1]

  local __opts = {
    win_opts = wincfg,
    content_map = {
      [1] = {
        hval = "mark_note",
        mark = {
          bufnr = vim.api.nvim_get_current_buf(),
          line = curline,
          col = vim.api.nvim_win_get_cursor(0)[2],
          filename = vim.api.nvim_buf_get_name(curbuf),
        },
      },
    },
    on_submit = on_submit,
    on_cancel = on_cancel,
    data_annotation = load_chunk,
    _opts = opts,
  }

  QfbookmarkUIView.build_popup("mark_annotation", __opts)
end

---Open a small floating dropdown near the cursor to pick an extmark category.
---@param on_select fun(category: string)
---@param on_cancel? fun()
local function select_category(on_select, on_cancel)
  local QfbookmarkMarkUtils = require "qfbookmark.mark.utils"
  local items = QfbookmarkMarkUtils.ordered_keywords()
  if #items == 0 then
    QfbookmarkUtils.warn "no extmark categories configured"
    return
  end

  local display_lines = {}
  local shortcuts = {}
  for _, item in ipairs(items) do
    local shortcut = item.def.shortcut or item.name:sub(1, 1)
    shortcut = shortcut:lower()
    shortcuts[shortcut] = item.name
    table.insert(display_lines, string.format("    %s  %-10s %s", "●", item.name, shortcut))
  end

  local width = 0
  for _, l in ipairs(display_lines) do
    width = math.max(width, vim.fn.strdisplaywidth(l))
  end
  width = width + 3
  local height = #display_lines

  local row, col = QfbookmarkUIUtils.get_position(width, height, "auto", "cursor")

  local buf = vim.api.nvim_create_buf(false, true)
  local wincfg = {
    buf = buf,
    enter = true,
    wincfg = {
      relative = "cursor",
      width = width,
      height = height,
      row = row,
      col = col,
      style = "minimal",
      border = "rounded",
      title = QfbookmarkUIUtils.format_title "annotation category",
      title_pos = "center",
      footer = " j/k select · <Esc> cancel ",
      footer_pos = "center",
      noautocmd = true,
    },
  }

  local __opts = {
    display_lines = display_lines,
    contents = items,
    win_opts = wincfg,
    keys_shortcuts = shortcuts,
    on_submit = on_select,
    on_cancel = on_cancel,
  }

  QfbookmarkUIView.build_popup("select_category", __opts)
end

local buffer_selected = {}

---@param buffer_lists table
local function buffers_popup(buffer_lists)
  local curbuf = vim.api.nvim_get_current_buf()

  -- Build display lines
  local display_lines = {}
  local entries = {}
  local path_width = calc_path_width(buffer_lists, true, 30)

  for idx, buffer in pairs(buffer_lists) do
    local line, hval = QfbookmarkUIUtils.build_entry_line_buffers(idx, buffer, path_width)
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
  local width = calc_popup_width(display_lines) + 10

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

      footer = " q quit · c-v/s/t open ",
      footer_pos = "center",
    },
  }

  local __opts = {
    contents = buffer_lists,
    buffer_selected = buffer_selected,
    content_map = entries,
    display_lines = display_lines,
    original_popup_buffer_width = path_width,
    win_opts = wincfg,
    last_buf = curbuf,
  }

  QfbookmarkUIView.build_popup("buffer", __opts)
end

---@param note_path string
---@param cfg_note QFBookWindowNotes
---@param is_global? boolean
local function open_note_in_float(note_path, cfg_note, is_global)
  is_global = is_global or false

  local editor = QfbookmarkUIUtils.get_editor_size()

  local cfg_width = cfg_note.width * 100
  local cfg_height = cfg_note.height * 100

  local width = math.floor(editor.width * cfg_width / 100)
  local height = math.floor(editor.height * cfg_height / 100)

  local row, col = QfbookmarkUIUtils.get_position(width, height, cfg_note.anchor, "editor")

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
    note_path = note_path,
    is_note = true,
  }

  QfbookmarkUIView.build_popup("note", __opts)
end

return {
  mark_harpoon_popup = mark_harpoon_popup,
  saveqf_popup = saveqf_popup,
  buffers_popup = buffers_popup,
  place_mark_annotation = place_mark_annotation,
  preview_mark_annotation = preview_mark_annotation,
  open_note_in_float = open_note_in_float,
  input_note = input_note,
  select_category = select_category,
}
