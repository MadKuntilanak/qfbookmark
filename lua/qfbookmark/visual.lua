local Config = require("qfbookmark.config").defaults

local M = { sign_cache = {} }

local MAX_NOTE_LEN = 25

---@param id number
---@param bufnr number
---@param lnum number
---@param mark_mode QFBookMarkMode
---@param extmarkspec QFBookSpec
function M.insert_sign(id, mark_mode, bufnr, lnum, extmarkspec)
  local sign_name = "Qfbookmark" .. mark_mode

  if not M.sign_cache[sign_name] then
    M.sign_cache[sign_name] = true
    vim.fn.sign_define(sign_name, { text = extmarkspec.icon, texthl = extmarkspec.hl_group })
  end

  local priority = Config.extmarks.priority and Config.extmarks.priority or 1

  vim.fn.sign_place(id, Config.sign_group, sign_name, bufnr, { lnum = lnum, priority = priority })
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

  local ns = vim.api.nvim_create_namespace "qfbookmark_note_extmark"

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

  pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, lnum - 1, 0, {
    id = id,
    virt_text = { { icon .. " " .. display, hl } },
    virt_text_pos = "right_align",
    priority = 10,
  })
end

---@param id number
---@param bufnr? number
function M.delete_sign(id, bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  vim.fn.sign_unplace(Config.sign_group, { buffer = bufnr, id = id })
end

---@param id number
---@param bufnr? number
function M.delete_extmark(id, bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local ns = vim.api.nvim_create_namespace "qfbookmark_note_extmark"
  pcall(vim.api.nvim_buf_del_extmark, bufnr, ns, id)
end

---@param bufnr? integer
function M.clear_extmarks(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local ns = vim.api.nvim_create_namespace "qfbookmark_note_extmark"
  pcall(vim.api.nvim_buf_clear_namespace, bufnr, ns, 0, -1)
end

---@param bufnr integer
---@param lnum integer -- 1-based
function M.get_extmark_at_line(bufnr, lnum)
  local ns = vim.api.nvim_create_namespace "qfbookmark_note_extmark"

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
  pcall(vim.api.nvim_buf_clear_namespace, bufnr, Config.ns, 0, -1)

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

--- Apply extmark highlights to every entry in the popup buffer.
---@param bufnr integer
---@param entries table[]  -- source of truth
function M.apply_entry_highlights(bufnr, entries)
  local ns = vim.api.nvim_create_namespace "qfbookmark_popup_hl"
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

  for idx, entry in ipairs(entries) do
    local ln_header = (entry.start_line or 1) - 1

    local header = vim.api.nvim_buf_get_lines(bufnr, ln_header, ln_header + 1, false)[1] or ""
    local detail = vim.api.nvim_buf_get_lines(bufnr, ln_header + 1, ln_header + 2, false)[1] or ""
    local symbol_line = vim.api.nvim_buf_get_lines(bufnr, ln_header + 2, ln_header + 3, false)[1] or ""

    -- ── Header ────────────────────────────────

    local idx_str = tostring(idx)
    local idx_s = 0
    local idx_e = 1 + #idx_str + 2

    pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, ln_header, idx_s, {
      end_col = math.min(idx_e, #header),
      hl_group = "QFBookmarkEntryIdx",
    })

    local badge_s = idx_e
    local badge_e = badge_s + 4

    pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, ln_header, badge_s, {
      end_col = math.min(badge_e, #header),
      hl_group = badge_hl(entry.hval.mark_mode),
    })

    local path_s = badge_e + 2
    local cur_pos = header:find(" ●", path_s, true)

    if cur_pos then
      pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, ln_header, path_s, {
        end_col = cur_pos - 1,
        hl_group = "QFBookmarkEntryPath",
      })

      pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, ln_header, cur_pos, {
        end_col = #header,
        hl_group = "QFBookmarkEntryCurrentFile",
      })
    else
      pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, ln_header, path_s, {
        end_col = #header,
        hl_group = "QFBookmarkEntryPath",
      })
    end

    -- ── Detail line ───────────────────────────

    local lnum_s, lnum_e_byte = detail:match "():%d+()"
    if lnum_s then
      pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, ln_header + 1, lnum_s - 1, {
        end_col = lnum_e_byte - 1,
        hl_group = "QFBookmarkEntryLnum",
      })

      local preview_s = lnum_e_byte + 1
      if preview_s <= #detail then
        local is_symbol = detail:find("⮞", preview_s + 1, true)
        if is_symbol then
          pcall(
            vim.api.nvim_buf_set_extmark,
            bufnr,
            ns,
            ln_header + 1,
            preview_s,
            { end_col = #detail, hl_group = "QFbookmarkNoteExtmarkNoteEx" }
          )
        else
          pcall(
            vim.api.nvim_buf_set_extmark,
            bufnr,
            ns,
            ln_header + 1,
            preview_s,
            { end_col = #detail, hl_group = "QFBookmarkEntryDetail" }
          )
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
          pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, ln_header + 2, sym_s, {
            end_col = #symbol_line,
            hl_group = "QFBookmarkEntryFnName",
          })
        else
          local sep = symbol_line:find(" > ", sym_s + 1, true)
          if sep then
            pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, ln_header + 2, sym_s, {
              end_col = sep - 1,
              hl_group = "QFBookmarkEntrySymbolType",
            })

            pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, ln_header + 2, sep + 2, {
              end_col = #symbol_line,
              hl_group = "QFBookmarkEntryFnName",
            })
          else
            pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, ln_header + 2, sym_s, {
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
function M.apply_entry_buffer_highlights(bufnr)
  local ns = vim.api.nvim_create_namespace "qfbookmark_popup_buffer_hl"
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  for lnum, line in ipairs(lines) do
    if line and line ~= "" then
      -- Flag
      local flag = line:find "%%" or line:find "%#"
      if flag then
        vim.api.nvim_buf_set_extmark(bufnr, ns, lnum - 1, 0, {
          end_col = 2,
          hl_group = "QFBookmarkEntryFlag",
        })
      end

      -- Path
      local lnum_s = line:find ":%d+"
      if lnum_s then
        local lnum_e = line:find("[^%d]", lnum_s + 1) or #line
        vim.api.nvim_buf_set_extmark(bufnr, ns, lnum - 1, lnum_s - 1, {
          end_col = lnum_e,
          hl_group = "QFBookmarkEntryLnum",
        })
      end
    end
  end
end

function M.apply_save_highlights(buf, fn_opts, type_label, dir_display)
  local ns = vim.api.nvim_create_namespace "qfbookmark_popup_save_hl"
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

  -- line 0: type badge (QuickFix / LocList)
  local badge_hl_group = fn_opts.is_loc and "QFBookmarkBadgeNote" or "QFBookmarkBadgeMark"
  pcall(vim.api.nvim_buf_set_extmark, buf, ns, 0, 0, {
    end_col = #type_label,
    hl_group = badge_hl_group,
  })

  -- line 2: "  filename   value"
  local fn_key_end = ("  filename   "):len()
  pcall(vim.api.nvim_buf_set_extmark, buf, ns, 2, 2, {
    end_col = fn_key_end - 3,
    hl_group = "QFBookmarkEntryIdx",
  })
  pcall(vim.api.nvim_buf_set_extmark, buf, ns, 2, fn_key_end, {
    end_col = fn_key_end + #fn_opts.filename,
    hl_group = "QFBookmarkEntryPath",
  })

  -- line 3: "  directory  value"
  local dir_key_end = ("  directory  "):len()
  pcall(vim.api.nvim_buf_set_extmark, buf, ns, 3, 2, {
    end_col = dir_key_end - 2,
    hl_group = "QFBookmarkEntryIdx",
  })
  pcall(vim.api.nvim_buf_set_extmark, buf, ns, 3, dir_key_end, {
    end_col = dir_key_end + #dir_display,
    hl_group = "QFBookmarkEntryDirectory",
  })
end

return M
