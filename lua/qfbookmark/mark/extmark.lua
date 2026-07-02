local Config = require("qfbookmark.config").defaults

local QfbookmarkMarkUtils = require "qfbookmark.mark.utils"
local QfbookmarkUtils = require "qfbookmark.utils"

local M = {}

local MAX_NOTE_LEN = 25

---@param bufnr integer
---@param namespace_name integer
---@param line integer
---@param col integer
---@param opts vim.api.keyset.set_extmark
---@return integer|nil
function M.set_extmark(bufnr, namespace_name, line, col, opts)
  if QfbookmarkUtils.is_valid(bufnr) then
    local ok, id = pcall(vim.api.nvim_buf_set_extmark, bufnr, namespace_name, line, col, opts)

    if not ok then
      QfbookmarkUtils.error "failed to create extmark annotation"
      return nil
    end

    return id
  end
end

---@param id integer
---@param bufnr integer
---@param lnum integer
---@param category QFBookMarkMode
---@param text string
function M.insert_extmark(id, category, bufnr, lnum, text)
  if #text == 0 then
    return
  end

  local ns = QfbookmarkMarkUtils.register_namespace "qfbookmark_note_extmark"

  -- truncate teks
  local display = vim.fn.strdisplaywidth(text) > MAX_NOTE_LEN and vim.fn.strcharpart(text, 0, MAX_NOTE_LEN) .. "…"
    or text

  local hl_map = {
    MARK = "QFbookmarkNoteExtmarkMark",
    FIX = "QFbookmarkNoteExtmarkFix",
    DEBUG = "QFbookmarkNoteExtmarkDebug",
    NOTE = "QFbookmarkNoteExtmarkNote",
  }
  local hl = hl_map[category] or "QFbookmarkNoteExtmarkMark"

  local icon = Config.extmarks.keywords[category].icon or "📌 "

  M.set_extmark(bufnr, ns, lnum - 1, 0, {
    id = id,
    virt_text = { { icon .. " " .. display, hl } },
    -- virt_text_pos = "right_align",
    priority = 10,
  })
end

---@param bufnr integer
---@param ns integer
---@param id integer
function M.del_extmark(bufnr, ns, id)
  if QfbookmarkUtils.is_valid(bufnr) then
    pcall(vim.api.nvim_buf_del_extmark, bufnr, ns, id)
  end
end

---@param id number
---@param ns integer
---@param bufnr? number
function M.delete_extmark(id, ns, bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  M.del_extmark(bufnr, ns, id)
end

---@param extmark_name string
---@param bufnr? integer
function M.clear_extmarks(extmark_name, bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local ns = QfbookmarkMarkUtils.register_namespace(extmark_name)
  QfbookmarkMarkUtils.del_namespace(bufnr, ns)
end

---@param bufnr integer
---@param ns integer
function M.get_buf_extmark(bufnr, ns)
  if QfbookmarkUtils.is_valid(bufnr) then
    return vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
  end
end

---@param bufnr integer
---@param id integer
---@param ns integer
---@return string[]  lines currently covered by the annotation range
function M.get_annotation_lines(bufnr, ns, id)
  local range = M.get_annotation_range(bufnr, ns, id)
  if not range then
    return {}
  end

  return vim.api.nvim_buf_get_lines(bufnr, range.start_row, range.end_row + 1, false)
end

---@param bufnr integer
---@param id integer
---@return QFBookmarkExtermarkAnnotationRange|nil
---  0-indexed rows, as returned by nvim_buf_get_extmark_by_id
function M.get_annotation_range(bufnr, ns, id)
  local ok, mark = pcall(vim.api.nvim_buf_get_extmark_by_id, bufnr, ns, id, { details = true })

  if not ok or not mark or vim.tbl_isempty(mark) then
    return nil
  end

  local row, col, details = mark[1], mark[2], mark[3]
  if not details then
    return nil
  end

  return {
    start_row = row,
    start_col = col,
    end_row = details.end_row,
    end_col = details.end_col,
  }
end

---@param bufnr integer
---@param lnum integer -- 1-based
function M.get_extmark_at_line(bufnr, ns, lnum)
  local marks = M.get_buf_extmark(bufnr, ns)

  return vim.tbl_map(
    function(mark)
      return {
        id = mark[1],
        lnum = mark[2] + 1,
        col = mark[3] + 1,
        details = mark[4],
      }
    end,
    vim.tbl_filter(function(mark)
      return mark[2] == (lnum - 1)
    end, marks)
  )
end

---Detect whether an annotation's range has collapsed (zero-width),
---which usually means the original block/line it covered was deleted.
---
---Single-line annotations are zero-width *by design* (start_row == end_row,
---end_col == 0), so a plain shape check would false-positive on every one of
---them. We disambiguate using the span the annotation was *created* with:
---  - originally multi-line + now zero-width  -> the lines got deleted, orphaned
---  - originally single-line                  -> shape never tells us anything;
---                                                 fall back to checking whether
---@param bufnr integer
---@param id integer
---@return boolean
function M.is_orphaned(bufnr, ns, id, meta)
  local range = M.get_annotation_range(bufnr, ns, id)
  if not range then
    return true -- extmark itself is gone
  end

  local original_span = meta and meta.original_span or 0

  local collapsed = range.start_row == range.end_row and range.start_col == range.end_col

  if original_span > 0 then
    -- was multi-line: collapsing to zero-width is a real signal
    return collapsed
  end

  -- was single-line from the start: collapse is expected, not a signal.
  -- the closest we can do is check the line still exists in the buffer.
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  return range.start_row + 1 > line_count
end

---Fill the sign column for every line in [start_line, end_line] (1-indexed,
---inclusive), since a single extmark's sign_text only ever renders on its
---start_row — there's no native "ranged sign".
---@param bufnr integer
---@param start_line integer
---@param end_line integer
---@param hl string
---@return integer[]  extmark ids created, so they can be cleaned up later
function M.render_range_signs(bufnr, range_signs_enabled, ns_signs, start_line, end_line, hl)
  if not range_signs_enabled then
    return {}
  end

  local ids = {}
  for line = start_line - 1, end_line - 1 do
    local id = M.set_extmark(bufnr, ns_signs, line, 0, {
      sign_text = "▌",
      sign_hl_group = hl,
      priority = 1,
    })
    table.insert(ids, id)
  end
  return ids
end

return M
