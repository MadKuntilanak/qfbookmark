local Config = require("qfbookmark.config").defaults

local QfbookmarkTreesitter = require "qfbookmark.treesitter"
local QfbookmarkUtils = require "qfbookmark.utils"

local M = {}

M.PADDING = 10
M.PADDING_PREVIEW = 2
M.FILETYPE = "qfbookmark"

local prefix_msg = "QFBookmark Ui"

function M.warn(msg)
  QfbookmarkUtils.warn(msg, prefix_msg)
end

function M.info(msg)
  QfbookmarkUtils.info(msg, prefix_msg)
end

---@param title string
function M.format_title(title)
  return " " .. title .. " "
end

function M.get_editor_size()
  local ui = vim.api.nvim_list_uis()[1]
  return {
    width = ui.width,
    height = ui.height,
  }
end

---@param is_input? boolean
---@param lines? table
---@return WinSizeCfg
function M.get_win_width(is_input, lines)
  is_input = is_input or false

  lines = lines or vim.api.nvim_get_option_value("lines", { scope = "global" })
  local columns = vim.api.nvim_get_option_value("columns", { scope = "global" })

  local win_height = math.ceil((lines / 2) - 8)
  local win_width = math.ceil(columns / 2)
  local row_base = 2

  -- The `is_input` flag is used for `input_popup`,
  -- and `input_popup` requires a small width.
  if is_input then
    row_base = 3
    win_height = 1
    win_width = win_width - 5
  end

  local ui = vim.api.nvim_list_uis()[1]
  local row = math.floor((ui.height - win_height) / row_base)
  local col = math.floor((ui.width - win_width) / 2)

  return { row = row, col = col, width = win_width, height = win_height }
end

function M.get_position(anchor, width, height)
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

---@param height_editor integer
---@param width_editor integer
function M.get_center_col_row(height_editor, width_editor)
  local editor = M.get_editor_size()
  local row = math.ceil((editor.height - height_editor) / 2) - 5
  local col = math.ceil((editor.width - width_editor) / 2)
  return col, row
end

--- Compute the general row and the row that will be implemented for marks,
--- buffers, and input popups.
---@param width_editor integer
---@param height_editor integer
---@param width_main_popup integer
---@return integer, integer
function M.get_col_row(height_editor, width_editor, width_main_popup, is_center)
  is_center = is_center or false

  if is_center then
    local col, row = M.get_center_col_row(height_editor, width_editor)
    return col, row
  end

  local row = math.floor(height_editor * 15 / 100)

  local _col = width_editor - width_main_popup - M.PADDING
  local col_minus = 5
  local col = Config.window.mark.anchor == "NW" and col_minus or _col

  return col, row
end

--- Shorten a path by trimming from the left, keeping the meaningful tail.
--- Example: "nvim/.config/nvim/lua/r/plugins/qf.lua" → "r/plugins/qf.lua"
---@param path string
---@param max_len integer
---@return string
function M.shorten_path(path, max_len)
  local short = vim.fn.fnamemodify(path, ":~:.")
  if vim.fn.strdisplaywidth(short) <= max_len then
    return short
  end
  local parts = vim.split(short, "/", { plain = true })
  local result = parts[#parts]
  for i = #parts - 1, 1, -1 do
    local candidate = parts[i] .. "/" .. result
    if vim.fn.strdisplaywidth(candidate) > max_len - 2 then
      return "…/" .. result
    end
    result = candidate
  end
  return result
end

--- Truncate line text so it does not overflow the popup width
---@param text string
---@param max_len integer
---@return string
function M.shorten_text(text, max_len)
  -- strip leading whitespace
  text = text:match "^%s*(.-)%s*$" or text
  if vim.fn.strdisplaywidth(text) <= max_len then
    return text
  end
  -- truncate and append ellipsis
  local result = ""
  local i = 0
  for _, char in
    ---@diagnostic disable-next-line: undefined-global
    utf8 and utf8.codes(text) or (function()
      local idx = 0
      return function()
        idx = idx + 1
        if idx <= #text then
          return idx, text:byte(idx)
        end
      end
    end)()
  do
    if vim.fn.strdisplaywidth(result) >= max_len - 1 then
      break
    end
    ---@diagnostic disable-next-line: undefined-global
    result = result .. (utf8 and utf8.char(char) or string.char(char))
    i = i + 1
  end
  return result .. "…"
end

--- Badge label per mark_mode
---@param mark_mode QFBookMarkMode
---@return string
function M.get_mode_badge(mark_mode)
  local badges = {}
  for key_, val_ in pairs(Config.extmarks.keywords) do
    badges[key_] = val_.icon
  end

  return badges[mark_mode] or mark_mode:sub(1, 4)
end

--- Cek apakah mark entry ini adalah file yang sedang aktif
---@param filename string
---@return boolean
function M.is_current_file(filename)
  local cur = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
  return filename == cur
end

---@param windows QFBookUiCfg
function M.clean_up(windows)
  local wins = {}
  local bufs = {}
  local augroups = {}

  -- Must check first!
  -- if window entries use win/buf fields rather than M.windows format
  if windows.win and windows.buf then
    if vim.api.nvim_win_is_valid(windows.win) then
      wins[#wins + 1] = windows.win
    end

    if vim.api.nvim_win_is_valid(windows.buf) then
      bufs[#bufs + 1] = windows.buf
    end
  else
    for _, layout in pairs(windows) do
      if layout.win and vim.api.nvim_win_is_valid(layout.win) then
        wins[#wins + 1] = layout.win
        layout.win = nil
      end
      if layout.buf and vim.api.nvim_buf_is_valid(layout.buf) then
        bufs[#bufs + 1] = layout.buf
        layout.buf = nil
      end
      if layout.augroup then
        augroups[#augroups + 1] = layout.augroup
      end
    end
  end

  if #wins > 0 then
    M.close_win(wins)
  end

  if #bufs > 0 then
    M.close_buf(bufs)
  end
  -- for _, v in pairs(ui_cfg) do
  --   if type(v) == "table" then
  --     if v.augroup then
  --       local augroup = Config.sign_group .. v.augroup
  --       QfbookmarkUtils.clear_autocmd_group(augroup)
  --     end
  --     v.buf = nil
  --     v.win = nil
  --   end
  -- end

  -- if ui_cfg.augroup then
  --   local augroup = Config.sign_group .. ui_cfg.augroup
  --   QfbookmarkUtils.clear_autocmd_group(augroup)
  -- end
  -- ui_cfg.buf = nil
  -- ui_cfg.win = nil
  return windows
end

---@param bufs integer|table
function M.close_buf(bufs)
  if type(bufs) == "table" then
    for _, b in pairs(bufs) do
      if vim.api.nvim_buf_is_valid(b) then
        QfbookmarkUtils.buf_del(b)
      end
    end
    return
  end

  if type(bufs) == "number" then
    if vim.api.nvim_buf_is_valid(bufs) then
      QfbookmarkUtils.buf_del(bufs)
    end
  end
end

---@param wins integer|table
function M.close_win(wins)
  if type(wins) == "table" then
    for _, w in pairs(wins) do
      if w and vim.api.nvim_win_is_valid(w) then
        vim.api.nvim_win_close(w, true)
      end
    end
    return
  end

  if type(wins) == "number" then
    if wins and vim.api.nvim_win_is_valid(wins) then
      vim.api.nvim_win_close(wins, true)
    end
  end
end

---@param bufnr integer
---@return "gone" | "alive" | "hidden"
function M.get_buffer_status(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return "gone"
  end

  local buffers = vim.api.nvim_list_bufs()
  for _, b in ipairs(buffers) do
    if b == bufnr then
      return "alive"
    end
  end

  -- buffer still valid, but hidden (bdelete, bwipeout)
  return "hidden"
end

--- Build display lines per entry — 2 lines when no symbol, 3 lines when symbol exists:
---   Line 1 (header): " N  BADGE  path/file.lua ●"
---   Line 2 (detail): "         :lnum  preview text"
---   Line 3 (symbol): "         icon name > icon name"  ← only when chain != ""
---@param idx integer 1-based display index
---@param mark QFbookBufferMarkEntry mark entry to render
---@param path_width integer column width for path alignment
---@param symbol QFBookSymbol resolved symbol (kind + name)
---@return string line1 header line
---@return string line2 detail line
---@return string|nil line3 symbol line, nil when no symbol context
---@return string harpoon harpoon value for lookup
function M.build_entry_lines(idx, mark, path_width, symbol)
  local badge = M.get_mode_badge(mark.mark_mode)
  local path = M.shorten_path(mark.filename, path_width)
  local cur_marker = M.is_current_file(mark.filename) and " ●" or ""
  local lnum = string.format(":%d", mark.line)

  local note_annotation

  if type(mark.note) == "table" then
    note_annotation = table.concat(mark.note, " ")
  elseif type(mark.note) == "string" then
    note_annotation = mark.note
  end

  local preview = mark.mark_mode == "NOTE" and ("⮞ " .. note_annotation or mark.text or "") or (mark.text or "")
  preview = M.shorten_text(preview, path_width)

  -- header: " N  BADGE  plugins/qf.lua ●"
  local line1 = string.format(" %d  %s  %s%s", idx, badge, path, cur_marker)

  -- detail: indent + lnum + preview (full width, no truncation for symbol)
  local indent = string.rep(" ", 9)
  local line2 = string.format("%s%s  %s", indent, lnum, preview)

  -- symbol line: only emit when there is context
  local sym_part = symbol.chain or ""
  local line3 = sym_part ~= "" and (indent .. sym_part) or nil

  return line1, line2, line3, mark.harpoon
end

--- Resolve symbol for a mark entry.
--- Live when buffer loaded; falls back to cached fn_name when gone.
---@param mark QFbookBufferMarkEntry
---@return QFBookSymbol
function M.resolve_fn_name(mark)
  local status = M.get_buffer_status(mark.bufnr)

  if (status == "alive" or status == "hidden") and vim.api.nvim_buf_is_valid(mark.bufnr) then
    local result = QfbookmarkTreesitter.resolve_symbol(mark.bufnr, mark.line, mark.col or 0)
    return result
  end

  -- buffer gone: render cached fn_name as a plain fn symbol
  local cached = mark.fn_name or ""
  if cached == "" or cached == "[--]" then
    return { kind = "unknown", chain = "" }
  end
  return { kind = "fn", chain = cached.chain }
end

---@param entries table<integer, QFBookmarkEntry>,
---@param lnum integer
function M.get_entry_at_line(entries, lnum)
  for _, entry in ipairs(entries) do
    local last = entry.start_line + entry.line_count - 1

    if lnum >= entry.start_line and lnum <= last then
      return entry
    end
  end
end

---@param win integer
---@param total integer
---@param selected table<string, boolean>,
function M.update_title_mark_harpoon_popup(win, total, selected)
  -- total = total or #Mapping.harpoon_map
  -- local sel_count = vim.tbl_count(selected)
  -- local cfg = vim.api.nvim_win_get_config(Mapping.popup.win)
  --
  -- local count_str = sel_count > 0 and string.format("QFMarks (%d) · %d selected", total, sel_count)
  --   or string.format("QFMarks (%d)", total)
  -- cfg.title = QfbookmarkUIUtils.format_title("🔗 " .. count_str)
  -- vim.api.nvim_win_set_config(Mapping.popup.win, cfg)

  total = total
  local sel_count = vim.tbl_count(selected)
  local cfg = vim.api.nvim_win_get_config(win)

  local count_str = sel_count > 0 and string.format("QFMarks (%d) · %d selected", total, sel_count)
    or string.format("QFMarks (%d)", total)
  cfg.title = M.format_title("🔗 " .. count_str)
  vim.api.nvim_win_set_config(win, cfg)
end

return M
