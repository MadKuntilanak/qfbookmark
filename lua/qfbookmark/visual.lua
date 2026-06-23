local Config = require("qfbookmark.config").defaults
local QfbookmarkUtils = require "qfbookmark.utils"

local M = {
  sign_cache = {},
  namespace_cache = {},
}

local MAX_NOTE_LEN = 25

---@param bufnr integer
---@param ns integer
---@param line integer
---@param col integer
---@param opts vim.api.keyset.set_extmark
local function set_extmark(bufnr, ns, line, col, opts)
  if QfbookmarkUtils.is_valid(bufnr) then
    pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, line, col, opts)
  end
end

---@param bufnr integer
---@param id integer
---@param sign_name string
---@param sign_group string
---@param opts? vim.fn.sign_place.dict
local function set_sign_place(bufnr, id, sign_group, sign_name, opts)
  if QfbookmarkUtils.is_valid(bufnr) then
    vim.fn.sign_place(id, sign_group, sign_name, bufnr, opts)
  end
end

---@param bufnr integer
---@param ns integer
---@param id integer
local function del_extmark(bufnr, ns, id)
  if QfbookmarkUtils.is_valid(bufnr) then
    pcall(vim.api.nvim_buf_del_extmark, bufnr, ns, id)
  end
end

---@param bufnr integer
---@param ns integer
local function del_namespace(bufnr, ns)
  if QfbookmarkUtils.is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  end
end

---@param icon string
---@param hl_group string
local function register_sign(sign_name, icon, hl_group)
  if not M.sign_cache[sign_name] then
    M.sign_cache[sign_name] = true
    vim.fn.sign_define(sign_name, { text = icon, texthl = hl_group })
  end
end

---@param namespace_name string
local function register_namespace(namespace_name)
  if not M.namespace_cache[namespace_name] then
    M.namespace_cache[namespace_name] = vim.api.nvim_create_namespace(namespace_name)
  end
  return M.namespace_cache[namespace_name]
end

---@param id number
---@param bufnr number
---@param lnum number
---@param mark_mode QFBookMarkMode
---@param extmarkspec QFBookSpec
function M.insert_sign(id, mark_mode, bufnr, lnum, extmarkspec)
  local sign_name = "Qfbookmark" .. mark_mode
  register_sign(sign_name, extmarkspec.icon, extmarkspec.hl_group)

  local priority = Config.extmarks.priority and Config.extmarks.priority or 1
  set_sign_place(bufnr, id, Config.sign_group, sign_name, { lnum = lnum, priority = priority })
end

---@param id number
---@param bufnr? number
function M.delete_sign(id, bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if QfbookmarkUtils.is_valid(bufnr) then
    vim.fn.sign_unplace(Config.sign_group, { buffer = bufnr, id = id })
  end
end

---@param id integer
---@param bufnr integer
---@param lnum integer
---@param mark_mode QFBookMarkMode
---@param text string
function M.insert_extmark(id, mark_mode, bufnr, lnum, text)
  if #text == 0 then
    return
  end

  local ns = register_namespace "qfbookmark_note_extmark"

  -- truncate teks
  local display = vim.fn.strdisplaywidth(text) > MAX_NOTE_LEN and vim.fn.strcharpart(text, 0, MAX_NOTE_LEN) .. "…"
    or text

  local hl_map = {
    MARK = "QFbookmarkNoteExtmarkMark",
    FIX = "QFbookmarkNoteExtmarkFix",
    DEBUG = "QFbookmarkNoteExtmarkDebug",
    NOTE = "QFbookmarkNoteExtmarkNote",
  }
  local hl = hl_map[mark_mode] or "QFbookmarkNoteExtmarkMark"

  local icon = Config.extmarks.keywords[mark_mode].icon or "📌 "

  set_extmark(bufnr, ns, lnum - 1, 0, {
    id = id,
    virt_text = { { icon .. " " .. display, hl } },
    -- virt_text_pos = "right_align",
    priority = 10,
  })
end
---@param id number
---@param bufnr? number
function M.delete_extmark(id, bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local ns = register_namespace "qfbookmark_note_extmark"
  del_extmark(bufnr, ns, id)
end

---@param bufnr? integer
function M.clear_extmarks(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local ns = register_namespace "qfbookmark_note_extmark"
  del_namespace(bufnr, ns)
end

---@param bufnr integer
---@param lnum integer -- 1-based
function M.get_extmark_at_line(bufnr, lnum)
  local ns = register_namespace "qfbookmark_note_extmark"

  local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })

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

---@param bufnr integer
---@return table <integer>
local function get_all_signs_buffer(bufnr)
  local placed = vim.fn.sign_getplaced(bufnr, { group = "*" }) -- Ambil semua sign yang terpasang
  local all_signs = placed[1] and placed[1].signs or {}
  return all_signs
end

---@param bufnr integer
---@param existing_ids table
---@return table <integer>
function M.get_sign_unused_ids(bufnr, existing_ids)
  local all_signs = get_all_signs_buffer(bufnr)
  local unused_ids = {}

  for _, sign in ipairs(all_signs) do
    if existing_ids[sign.id] then
      -- table.insert(unused_ids, sign.id)
      table.insert(unused_ids, sign)
      existing_ids[sign.id] = true -- Tandai ID sudah digunakan
    end
  end

  return unused_ids
end

---@param bufnr integer
---@param lnum integer
---@return table
function M.get_sign_at_line(bufnr, lnum)
  local all_signs = get_all_signs_buffer(bufnr)

  for _, x in pairs(all_signs) do
    if x.lnum == lnum then
      return x
    end
  end

  return {}
end

function M.resolve_mark_sign(bufnr)
  del_namespace(bufnr, Config.ns)

  -- clear all signs
  local ok_signs, signinfo = pcall(vim.fn.sign_getplaced, bufnr, { group = Config.sign_group })
  if ok_signs and signinfo and signinfo[1] and signinfo[1].signs then
    for _, sign in pairs(signinfo[1].signs) do
      pcall(vim.fn.sign_unplace, Config.sign_group, { buffer = bufnr, id = sign.id })
    end
  end
end

--- Map mark_mode string → highlight group name for its badge.
---@param mark_mode QFBookMarkMode
---@return string
local function badge_hl(mark_mode)
  local map = {
    MARK = "QFBookmarkBadgeMark",
    FIX = "QFBookmarkBadgeFix",
    NOTE = "QFBookmarkBadgeNote",
    DEBUG = "QFBookmarkBadgeDebug",
  }
  return map[mark_mode] or "QFBookmarkBadgeMark"
end

-- +-----------------------------------------------------------------------------+
-- |                                APPLY EXTMARK                                |
-- +-----------------------------------------------------------------------------+

--- Apply extmark highlights for all popup entries, including
--- selection and cursor-line states.
---@param bufnr integer
---@param content_map QFBookmarkEntry[]
---@param selected table<string, boolean>
---@param cursor_hval string
function M.apply_entry_highlights(bufnr, content_map, selected, cursor_hval)
  local ns = register_namespace "qfbookmark_popup_hl"
  del_namespace(bufnr, ns)

  for idx, entry in ipairs(content_map) do
    local ln_header = (entry.start_line or 1) - 1

    local header = vim.api.nvim_buf_get_lines(bufnr, ln_header, ln_header + 1, false)[1] or ""
    local detail = vim.api.nvim_buf_get_lines(bufnr, ln_header + 1, ln_header + 2, false)[1] or ""
    local symbol_line = vim.api.nvim_buf_get_lines(bufnr, ln_header + 2, ln_header + 3, false)[1] or ""

    -- ── Header ────────────────────────────────

    local idx_str = tostring(idx)
    local idx_s = 0
    local idx_e = 1 + #idx_str + 2

    set_extmark(bufnr, ns, ln_header, idx_s, {
      end_col = math.min(idx_e, #header),
      hl_group = "QFBookmarkEntryIdx",
    })

    local badge_s = idx_e
    local badge_e = badge_s + 4

    set_extmark(bufnr, ns, ln_header, badge_s, {
      end_col = math.min(badge_e, #header),
      hl_group = badge_hl(entry.mark.mark_mode),
    })

    local path_s = badge_e + 2
    local cur_pos = header:find(" ●", path_s, true)

    local path_text = header:sub(path_s + 1, #header)
    -- find last "/" within path_text to split dir vs basename
    local last_slash = nil
    for i = #path_text, 1, -1 do
      if path_text:sub(i, i) == "/" then
        last_slash = i
        break
      end
    end

    if last_slash then
      -- dir part: dim
      set_extmark(bufnr, ns, ln_header, path_s, {
        end_col = path_s + last_slash,
        hl_group = "QFBookmarkEntryPath",
      })

      -- basename part: bright
      set_extmark(bufnr, ns, ln_header, path_s + last_slash, {
        end_col = #header,
        hl_group = "QFBookmarkEntryBasename",
      })

      -- dot part
      if cur_pos then
        set_extmark(bufnr, ns, ln_header, cur_pos, {
          end_col = #header,
          hl_group = "QFBookmarkEntryCurrentFile",
        })
      end
    else
      set_extmark(bufnr, ns, ln_header, path_s, {
        end_col = #header,
        hl_group = "QFBookmarkEntryBasename",
      })
      -- dot part
      if cur_pos then
        set_extmark(bufnr, ns, ln_header, cur_pos, {
          end_col = #header,
          hl_group = "QFBookmarkEntryCurrentFile",
        })
      end
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

    set_extmark(bufnr, ns, ln_header, 0, {
      virt_text = { { chk_text, chk_hl } },
      virt_text_pos = "right_align",
      hl_eol = true,
      hl_mode = "replace",
      priority = 10,
    })

    if is_sel then
      local line_count = entry.line_count or 2
      for ln = ln_header, ln_header + line_count - 1 do
        set_extmark(bufnr, ns, ln, 0, {
          end_row = ln + 1,
          end_col = 0,
          hl_group = "QFBookmarkEntrySelected",
          hl_eol = true,
          hl_mode = "replace",
          priority = 10,
        })
      end
      -- unplan: dont hl line path?
      local _path_s = header:find("  ", 8, true)

      if _path_s then
        set_extmark(bufnr, ns, ln_header, path_s + 1, {
          end_col = #header,
          hl_group = "QFBookmarkEntrySelectedPath",
          priority = 10,
        })
      end
    end

    -- ── Detail line ───────────────────────────

    local lnum_s, lnum_e_byte = detail:match "():%d+()"
    if lnum_s then
      set_extmark(bufnr, ns, ln_header + 1, lnum_s - 1, {
        end_col = lnum_e_byte - 1,
        hl_group = "QFBookmarkEntryLnum",
      })

      local preview_s = lnum_e_byte + 1
      if preview_s <= #detail then
        local is_symbol = detail:find("⮞", preview_s + 1, true)
        if is_symbol then
          set_extmark(bufnr, ns, ln_header + 1, preview_s, {
            end_col = #detail,
            hl_group = "QFbookmarkNoteExtmarkNoteEx",
          })
        else
          set_extmark(bufnr, ns, ln_header + 1, preview_s, {
            end_col = #detail,
            hl_group = "QFBookmarkEntryDetail",
          })
        end
      end
    end

    -- ── Symbol line ───────────────────────────

    if symbol_line ~= "" and not symbol_line:match "^ %d+ " and not symbol_line:match "^%s+:%d+" then
      local sym_s = symbol_line:find "%S"
      if sym_s then
        sym_s = sym_s - 1

        local is_fn = symbol_line:sub(sym_s + 1, sym_s + 2) == "\xC6\x92"

        if is_fn then
          set_extmark(bufnr, ns, ln_header + 2, sym_s, {
            end_col = #symbol_line,
            hl_group = "QFBookmarkEntryFnName",
          })
        else
          local sep = symbol_line:find(" > ", sym_s + 1, true)
          if sep then
            set_extmark(bufnr, ns, ln_header + 2, sym_s, {
              end_col = sep - 1,
              hl_group = "QFBookmarkEntrySymbolType",
            })

            set_extmark(bufnr, ns, ln_header + 2, sep + 2, {
              end_col = #symbol_line,
              hl_group = "QFBookmarkEntryFnName",
            })
          else
            set_extmark(bufnr, ns, ln_header + 2, sym_s, {
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
function M.apply_entry_buffer_highlights(bufnr, list, selected)
  selected = selected or {}

  local ns = register_namespace "qfbookmark_popup_buffer_hl"
  local ns_chk = register_namespace "qfbookmark_popup_buffer_chk"
  del_namespace(bufnr, ns)
  del_namespace(bufnr, ns_chk)

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

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
      set_extmark(bufnr, ns, row, idx_s - 1, {
        end_col = idx_e,
        hl_group = "QFBookmarkEntryIdx",
        priority = 10,
      })
    end

    -- ── checkbox ─────────────────────────────────────────────────────
    local chk_text = is_sel and "✓" or "○"
    local chk_hl = is_sel and "QFBookmarkEntrySelectedCheck" or "QFBookmarkEntryUnselectedCheck"

    set_extmark(bufnr, ns_chk, row, 0, {
      virt_text = { { chk_text, chk_hl } },
      virt_text_pos = "right_align",
      priority = 20,
    })

    -- ── selected background ──────────────────────────────────────────
    if is_sel then
      set_extmark(bufnr, ns, row, 0, {
        end_row = row + 1,
        end_col = 0,
        hl_group = "QFBookmarkEntrySelected",
        hl_eol = true,
        priority = 20,
      })
    end

    -- ── flag/badge: col 7-8 (after "{idx:4}   ") ────────────────────────
    -- format: "{idx pad to 4}   {col0}{col1}  {path} {lnum}"
    local BADGE_COL0 = 7 -- 0-based
    local BADGE_COL1 = 8

    local col0 = line:sub(BADGE_COL0 + 1, BADGE_COL0 + 1)
    local col1 = line:sub(BADGE_COL1 + 1, BADGE_COL1 + 1)

    local is_flag = col0 == "%" or col0 == "#"
    local is_hidden = col0 == "h"
    local is_modified_col0 = col0 == "+"
    local is_modified_col1 = col1 == "+"

    if is_flag then
      set_extmark(bufnr, ns, row, BADGE_COL0, {
        end_col = BADGE_COL0 + 1,
        hl_group = "QFBookmarkEntryFlag",
        priority = 10,
      })
    elseif is_hidden then
      set_extmark(bufnr, ns, row, BADGE_COL0, {
        end_col = BADGE_COL0 + 1,
        hl_group = "QFBookmarkEntryHiddenFlag",
        priority = 10,
      })
    elseif is_modified_col0 then
      set_extmark(bufnr, ns, row, BADGE_COL0, {
        end_col = BADGE_COL0 + 1,
        hl_group = "QFBookmarkEntryModifiedFlag",
        priority = 10,
      })
    end

    if is_modified_col1 then
      set_extmark(bufnr, ns, row, BADGE_COL1, {
        end_col = BADGE_COL1 + 1,
        hl_group = "QFBookmarkEntryModifiedFlag",
        priority = 10,
      })
    end

    -- ── path + line number: path starts at col 11 ──────────────────────
    local lnum_s = line:find ":%d+$"
    if lnum_s then
      local path_start = 11 -- 0-based: after "{idx:4}   {badge:2}  "
      local path_end = lnum_s - 2
      local path_text = line:sub(path_start + 1, path_end)

      local last_slash
      for i = #path_text, 1, -1 do
        if path_text:sub(i, i) == "/" then
          last_slash = i
          break
        end
      end

      if last_slash then
        set_extmark(bufnr, ns, row, path_start, {
          end_col = path_start + last_slash,
          hl_group = "QFBookmarkEntryPath",
          priority = 10,
        })
        set_extmark(bufnr, ns, row, path_start + last_slash, {
          end_col = path_end,
          hl_group = "QFBookmarkEntryBasename",
          priority = 10,
        })
      else
        set_extmark(bufnr, ns, row, path_start, {
          end_col = path_end,
          hl_group = "QFBookmarkEntryBasename",
          priority = 10,
        })
      end

      set_extmark(bufnr, ns, row, lnum_s - 1, {
        end_col = #line,
        hl_group = "QFBookmarkEntryLnum",
        priority = 10,
      })
    end

    ::continue::
  end
end

---@param bufnr integer
---@param namespace string
function M.apply_save_highlights(bufnr, fn_opts, type_label, dir_display, namespace)
  namespace = namespace or ("qfbookmark" .. tostring(bufnr))
  local ns = register_namespace(namespace)
  del_namespace(bufnr, ns)

  -- line 0: type badge (QuickFix / LocList)
  local badge_hl_group = fn_opts.is_loc and "QFBookmarkBadgeNote" or "QFBookmarkBadgeMark"
  set_extmark(bufnr, ns, 0, 0, {
    end_col = #type_label,
    hl_group = badge_hl_group,
  })

  -- line 2: "  filename   value"
  local fn_key_end = ("  filename   "):len()
  set_extmark(bufnr, ns, 2, 2, {
    end_col = fn_key_end - 3,
    hl_group = "QFBookmarkEntryIdx",
  })
  set_extmark(bufnr, ns, 2, fn_key_end, {
    end_col = fn_key_end + #fn_opts.filename,
    hl_group = "QFBookmarkEntryPath",
  })

  -- line 3: "  directory  value"
  local dir_key_end = ("  directory  "):len()
  set_extmark(bufnr, ns, 3, 2, {
    end_col = dir_key_end - 2,
    hl_group = "QFBookmarkEntryIdx",
  })
  set_extmark(bufnr, ns, 3, dir_key_end, {
    end_col = dir_key_end + #dir_display,
    hl_group = "QFBookmarkEntryDirectory",
  })
end

---@param qf_selected table[]
---@param is_loc boolean
function M.apply_qf_selection_highlights(qf_selected, is_loc)
  local bufnr = vim.api.nvim_get_current_buf()

  local sign_group = "qfbookmark_qf_select"
  register_sign("QFSelected", "✓", "QFBookmarkEntrySelectedCheck")
  register_sign("QFUnselected", " ", "QFBookmarkEntryUnselectedCheck")

  -- sign column: checkbox
  vim.fn.sign_unplace(sign_group, { buffer = bufnr })

  -- extmark: background highlight
  local ns = register_namespace "qfbookmark_qf_selection"
  del_namespace(bufnr, ns)

  local list = is_loc and vim.fn.getloclist(0) or vim.fn.getqflist()

  for idx = 1, #list do
    local is_sel = qf_selected[idx] == true

    set_sign_place(bufnr, 0, sign_group, is_sel and "QFSelected" or "QFUnselected", { lnum = idx })

    if is_sel then
      set_extmark(bufnr, ns, idx - 1, 0, {
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
