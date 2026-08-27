local QfbookmarkMarkUtils = require "qfbookmark.mark.utils"
local QfbookmarkMarkExtmark = require "qfbookmark.mark.extmark"
local QfbookmarkMarkSign = require "qfbookmark.mark.sign"

local M = {}

--- Map category string → highlight group name for its badge.
---@param category QFBookMarkMode
---@return string
local function badge_hl(category)
  local map = {
    MARK = "QFBookmarkBadgeMark",
    FIX = "QFBookmarkBadgeFix",
    NOTE = "QFBookmarkBadgeNote",
    DEBUG = "QFBookmarkBadgeDebug",
  }
  return map[category] or "QFBookmarkBadgeMark"
end

--- Apply extmark highlights for all popup entries, including
--- selection and cursor-line states.
---@param bufnr integer
---@param content_map QFBookmarkEntry[]
---@param selected table<string, boolean>
---@param cursor_hval string
function M.apply_entry_mark_highlights(bufnr, content_map, selected, cursor_hval)
  local ns = QfbookmarkMarkUtils.register_namespace "qfbookmark_popup_hl"
  QfbookmarkMarkUtils.del_namespace(bufnr, ns)

  for _, entry in ipairs(content_map) do
    local ln_header = (entry.start_line or 1) - 1

    local header = vim.api.nvim_buf_get_lines(bufnr, ln_header, ln_header + 1, false)[1] or ""
    local detail = vim.api.nvim_buf_get_lines(bufnr, ln_header + 1, ln_header + 2, false)[1] or ""
    local symbol_line = vim.api.nvim_buf_get_lines(bufnr, ln_header + 2, ln_header + 3, false)[1] or ""

    -- ── Header: use the offsets calculated during entry construction ──────
    local cols = entry.cols

    if cols then
      QfbookmarkMarkExtmark.set_extmark(bufnr, ns, ln_header, cols.idx_s, {
        end_col = math.min(cols.idx_e, #header),
        hl_group = "QFBookmarkEntryIdx",
      })

      QfbookmarkMarkExtmark.set_extmark(bufnr, ns, ln_header, cols.badge_s, {
        end_col = math.min(cols.badge_e, #header),
        hl_group = badge_hl(entry.mark.category),
      })

      QfbookmarkMarkExtmark.set_extmark(bufnr, ns, ln_header, cols.base_s, {
        end_col = math.min(cols.base_e, #header),
        hl_group = "QFBookmarkEntryBasename",
      })

      if cols.is_current then
        QfbookmarkMarkExtmark.set_extmark(bufnr, ns, ln_header, cols.marker_s, {
          end_col = math.min(cols.marker_e, #header),
          hl_group = "QFBookmarkEntryCurrentFile",
        })
      end

      QfbookmarkMarkExtmark.set_extmark(bufnr, ns, ln_header, cols.dir_s, {
        end_col = math.min(cols.dir_e, #header),
        hl_group = "QFBookmarkEntryPath",
      })
    end

    -- ── Selected entry ────────────────────────────────
    local is_sel = selected[entry.hval] == true
    local is_cursor = entry.hval == cursor_hval

    local chk_text = is_sel and "✓" or "○"
    local chk_hl

    if is_cursor and is_sel then
      chk_hl = "QFBookmarkEntrySelectedCheckCursor"
    elseif is_cursor then
      chk_hl = "QFBookmarkEntryUnselectedCheckCursor"
    elseif is_sel then
      chk_hl = "QFBookmarkEntrySelectedCheck"
    else
      chk_hl = "QFBookmarkEntryUnselectedCheck"
    end

    QfbookmarkMarkExtmark.set_extmark(bufnr, ns, ln_header, 0, {
      virt_text = { { chk_text, chk_hl } },
      virt_text_pos = "right_align",
      hl_eol = true,
      hl_mode = "replace",
      priority = 10,
    })

    if is_sel then
      local line_count = entry.line_count or 2
      for ln = ln_header, ln_header + line_count - 1 do
        QfbookmarkMarkExtmark.set_extmark(bufnr, ns, ln, 0, {
          end_row = ln + 1,
          end_col = 0,
          hl_group = "QFBookmarkEntrySelected",
          hl_eol = true,
          hl_mode = "replace",
          priority = 10,
        })
      end

      if cols then
        QfbookmarkMarkExtmark.set_extmark(bufnr, ns, ln_header, cols.dir_s, {
          end_col = #header,
          hl_group = "QFBookmarkEntrySelectedPath",
          priority = 10,
        })
      end
    end

    -- ── Detail line: preserve the existing format ─────────────────────────
    local lnum_s, lnum_e_byte = detail:match "():%d+()"
    if lnum_s then
      QfbookmarkMarkExtmark.set_extmark(bufnr, ns, ln_header + 1, lnum_s - 1, {
        end_col = lnum_e_byte - 1,
        hl_group = "QFBookmarkEntryLnum",
      })

      -- local preview_s = lnum_e_byte + 1
      local preview_s = lnum_e_byte
      if preview_s <= #detail then
        local is_symbol = detail:find("⮞", preview_s + 1, true)
        if is_symbol then
          QfbookmarkMarkExtmark.set_extmark(bufnr, ns, ln_header + 1, preview_s, {
            end_col = #detail,
            hl_group = "QFbookmarkNoteExtmarkNoteEx",
          })
        else
          QfbookmarkMarkExtmark.set_extmark(bufnr, ns, ln_header + 1, preview_s, {
            end_col = #detail,
            hl_group = "QFBookmarkEntryDetail",
          })
        end
      end
    end

    -- ── Symbol line: highlight the symbol type and function name ──────────
    if symbol_line ~= "" and not symbol_line:match "^ %d+ " and not symbol_line:match "^%s+:%d+" then
      local sym_s = symbol_line:find "%S"
      if sym_s then
        sym_s = sym_s - 1
        local is_fn = symbol_line:sub(sym_s + 1, sym_s + 2) == "\xC6\x92"

        if is_fn then
          QfbookmarkMarkExtmark.set_extmark(bufnr, ns, ln_header + 2, sym_s, {
            end_col = #symbol_line,
            hl_group = "QFBookmarkEntryFnName",
          })
        else
          local sep = symbol_line:find(" > ", sym_s + 1, true)
          if sep then
            QfbookmarkMarkExtmark.set_extmark(bufnr, ns, ln_header + 2, sym_s, {
              end_col = sep - 1,
              hl_group = "QFBookmarkEntrySymbolType",
            })
            QfbookmarkMarkExtmark.set_extmark(bufnr, ns, ln_header + 2, sep + 2, {
              end_col = #symbol_line,
              hl_group = "QFBookmarkEntryFnName",
            })
          else
            QfbookmarkMarkExtmark.set_extmark(bufnr, ns, ln_header + 2, sym_s, {
              end_col = #symbol_line,
              hl_group = "QFBookmarkEntrySymbolType",
            })
          end
        end
      end
    end
  end
end

---Apply extmarks to each buffer list entry
---@param bufnr integer must popup buffer
---@param list table[] list of buffer entries (same order as displayed lines)
---@param selected table<integer, boolean>  keyed by bufnr
---@param namespace string
---@param cursor_hval string
---@param base_width integer  fixed width of the basename column (must match build_entry_line_buffers)
---@param lnum_width integer  fixed width of the lnum column (must match build_entry_line_buffers)
function M.apply_entry_buffer_highlights(bufnr, list, selected, namespace, cursor_hval, base_width, lnum_width)
  selected = selected or {}
  namespace = namespace or ("qfbookmark" .. tostring(bufnr))
  local ns = QfbookmarkMarkUtils.register_namespace(namespace)
  QfbookmarkMarkUtils.del_namespace(bufnr, ns)

  local ns_chk = QfbookmarkMarkUtils.register_namespace "qfbookmark_popup_buffer_chk"
  QfbookmarkMarkUtils.del_namespace(bufnr, ns_chk)

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  -- fixed column offsets, derived from build_entry_line_buffers' format:
  -- "{idx:4}   {badge:2}  {base:base_width} {lnum:lnum_width}  {dir}"
  local BADGE_COL0 = 7
  local BADGE_COL1 = 8
  local BASE_START = 11
  local BASE_END = BASE_START + base_width
  local LNUM_START = BASE_END + 1
  local LNUM_END = LNUM_START + lnum_width
  local DIR_START = LNUM_END + 2

  for lnum, line in ipairs(lines) do
    if not line or line == "" then
      goto continue
    end

    local entry = list[lnum]
    local is_sel = entry and selected[entry.bufnr] == true
    local row = lnum - 1

    -- ── index: col 0-3 (4 char, right-aligned digit) ───────────────────
    local idx_s, idx_e = line:find "%d+"
    if idx_s and idx_e and idx_s <= 4 then
      QfbookmarkMarkExtmark.set_extmark(bufnr, ns, row, idx_s - 1, {
        end_col = idx_e,
        hl_group = "QFBookmarkEntryIdx",
        priority = 10,
      })
    end

    -- ── checkbox ─────────────────────────────────────────────────────
    local chk_text = is_sel and "✓" or "○"
    local is_cursor = cursor_hval and tostring(lnum) == cursor_hval
    local chk_hl

    if is_cursor and is_sel then
      chk_hl = "QFBookmarkEntrySelectedCheckCursor"
    elseif is_cursor then
      chk_hl = "QFBookmarkEntryUnselectedCheckCursor"
    elseif is_sel then
      chk_hl = "QFBookmarkEntrySelectedCheck"
    else
      chk_hl = "QFBookmarkEntryUnselectedCheck"
    end

    QfbookmarkMarkExtmark.set_extmark(bufnr, ns_chk, row, 0, {
      virt_text = { { chk_text, chk_hl } },
      virt_text_pos = "right_align",
      hl_eol = true,
      hl_mode = "replace",
      priority = 10,
    })

    -- ── selected background ──────────────────────────────────────────
    if is_sel then
      QfbookmarkMarkExtmark.set_extmark(bufnr, ns, row, 0, {
        end_row = row + 1,
        end_col = 0,
        hl_group = "QFBookmarkEntrySelected",
        hl_eol = true,
        priority = 10,
      })
    end

    -- ── flag/badge: col 7-8 ────────────────────────────────────────────
    local col0 = line:sub(BADGE_COL0 + 1, BADGE_COL0 + 1)
    local col1 = line:sub(BADGE_COL1 + 1, BADGE_COL1 + 1)

    local is_flag = col0 == "%" or col0 == "#"
    local is_hidden = col0 == "h"
    local is_modified_col0 = col0 == "+"
    local is_modified_col1 = col1 == "+"

    if is_flag then
      QfbookmarkMarkExtmark.set_extmark(bufnr, ns, row, BADGE_COL0, {
        end_col = BADGE_COL0 + 1,
        hl_group = "QFBookmarkEntryFlag",
        priority = 10,
      })
    elseif is_hidden then
      QfbookmarkMarkExtmark.set_extmark(bufnr, ns, row, BADGE_COL0, {
        end_col = BADGE_COL0 + 1,
        hl_group = "QFBookmarkEntryHiddenFlag",
        priority = 10,
      })
    elseif is_modified_col0 then
      QfbookmarkMarkExtmark.set_extmark(bufnr, ns, row, BADGE_COL0, {
        end_col = BADGE_COL0 + 1,
        hl_group = "QFBookmarkEntryModifiedFlag",
        priority = 10,
      })
    end

    if is_modified_col1 then
      QfbookmarkMarkExtmark.set_extmark(bufnr, ns, row, BADGE_COL1, {
        end_col = BADGE_COL1 + 1,
        hl_group = "QFBookmarkEntryModifiedFlag",
        priority = 10,
      })
    end

    -- ── basename: fixed column, no need to search ──────────────────────
    if #line >= BASE_START then
      local base_end = math.min(BASE_END, #line)
      QfbookmarkMarkExtmark.set_extmark(bufnr, ns, row, BASE_START, {
        end_col = base_end,
        hl_group = "QFBookmarkEntryBasename",
        priority = 10,
      })
    end

    -- ── lnum: fixed column ───────────────────────────────────────────
    if #line >= LNUM_START then
      local lnum_end = math.min(LNUM_END, #line)
      QfbookmarkMarkExtmark.set_extmark(bufnr, ns, row, LNUM_START, {
        end_col = lnum_end,
        hl_group = "QFBookmarkEntryLnum",
        priority = 10,
      })
    end

    -- ── dir path: trailing, fills to end of line ────────────────────────
    if #line > DIR_START then
      QfbookmarkMarkExtmark.set_extmark(bufnr, ns, row, DIR_START, {
        end_col = #line,
        hl_group = "QFBookmarkEntryPath",
        priority = 10,
      })
    end

    ::continue::
  end
end

---@param bufnr integer
---@param namespace string
function M.apply_entry_save_highlights(bufnr, fn_opts, type_label, dir_display, namespace)
  namespace = namespace or ("qfbookmark" .. tostring(bufnr))

  local ns = QfbookmarkMarkUtils.register_namespace(namespace)
  QfbookmarkMarkUtils.del_namespace(bufnr, ns)

  -- line 0: type badge (QuickFix / LocList)
  local badge_hl_group = fn_opts.is_loc and "QFBookmarkBadgeNote" or "QFBookmarkBadgeMark"
  QfbookmarkMarkExtmark.set_extmark(bufnr, ns, 0, 0, {
    end_col = #type_label,
    hl_group = badge_hl_group,
  })

  -- line 2: "  filename   value"
  local fn_key_end = ("  filename   "):len()
  QfbookmarkMarkExtmark.set_extmark(bufnr, ns, 2, 2, {
    end_col = fn_key_end - 3,
    hl_group = "QFBookmarkEntryIdx",
  })
  QfbookmarkMarkExtmark.set_extmark(bufnr, ns, 2, fn_key_end, {
    end_col = fn_key_end + #fn_opts.filename,
    hl_group = "QFBookmarkEntryPath",
  })

  -- line 3: "  directory  value"
  local dir_key_end = ("  directory  "):len()
  QfbookmarkMarkExtmark.set_extmark(bufnr, ns, 3, 2, {
    end_col = dir_key_end - 2,
    hl_group = "QFBookmarkEntryIdx",
  })
  QfbookmarkMarkExtmark.set_extmark(bufnr, ns, 3, dir_key_end, {
    end_col = dir_key_end + #dir_display,
    hl_group = "QFBookmarkEntryDirectory",
  })
end

---@param qf_selected table[]
---@param is_loc boolean
function M.apply_qf_selection_highlights(qf_selected, is_loc)
  local bufnr = vim.api.nvim_get_current_buf()

  QfbookmarkMarkSign.register_sign("QFSelected", "✓", "QFBookmarkEntrySelectedCheck")
  QfbookmarkMarkSign.register_sign("QFUnselected", " ", "QFBookmarkEntryUnselectedCheck")

  local sign_group = "qfbookmark_qf_select"

  -- sign column: checkbox
  vim.fn.sign_unplace(sign_group, { buffer = bufnr })

  -- extmark: background highlight
  local ns = QfbookmarkMarkUtils.register_namespace "qfbookmark_qf_selection"
  QfbookmarkMarkUtils.del_namespace(bufnr, ns)

  local list = is_loc and vim.fn.getloclist(0) or vim.fn.getqflist()

  for idx = 1, #list do
    local is_sel = qf_selected[idx] == true

    QfbookmarkMarkSign.set_signplace(bufnr, 0, sign_group, is_sel and "QFSelected" or "QFUnselected", { lnum = idx })

    if is_sel then
      QfbookmarkMarkExtmark.set_extmark(bufnr, ns, idx - 1, 0, {
        end_row = idx,
        end_col = 0,
        hl_group = "QFBookmarkEntrySelected",
        hl_eol = true,
        priority = 10,
      })
    end
  end
end

return M
