local M = { sign_cache = {} }
local Config = require("qfbookmark.config").defaults

---@param id number
---@param bufnr number
---@param line number
---@param mark_mode QFBookMarkMode
---@param extmarkspec QFBookSpec
function M.insert_signs(id, mark_mode, bufnr, line, extmarkspec)
  local sign_name = "Qfbookmark" .. mark_mode

  if not M.sign_cache[sign_name] then
    M.sign_cache[sign_name] = true
    if Config.extmarks.enabled then
      vim.fn.sign_define(sign_name, { text = extmarkspec.icon, texthl = extmarkspec.hl_group })
    end
  end

  local priority = 1
  if Config.extmarks.priority then
    priority = Config.extmarks.priority
  end

  vim.fn.sign_place(id, Config.sign_group, sign_name, bufnr, { lnum = line, priority = priority })
end

---@param id number
---@param bufnr? number
function M.remove_sign(id, bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  vim.fn.sign_unplace(Config.sign_group, { buffer = bufnr, id = id })
end

--- Map mark_mode string → highlight group name for its badge.
---@param mark_mode string
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
---@param buf integer must popup buffer
---@param mark_lists QFbookBufferMarkEntry[]
---@param entry_start_line table<integer, integer>  entry idx → 1-based header line_nr
function M.apply_entry_highlights(buf, mark_lists, entry_start_line)
  local ns = vim.api.nvim_create_namespace "qfbookmark_popup_hl"
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

  for idx, mark in ipairs(mark_lists) do
    local ln_header = (entry_start_line[idx] or (idx * 3 - 2)) - 1 -- 0-based
    local ln_detail = ln_header + 1
    local ln_symbol = ln_header + 2 -- may or may not exist

    local header = vim.api.nvim_buf_get_lines(buf, ln_header, ln_header + 1, false)[1] or ""
    local detail = vim.api.nvim_buf_get_lines(buf, ln_detail, ln_detail + 1, false)[1] or ""
    local symbol_line = vim.api.nvim_buf_get_lines(buf, ln_symbol, ln_symbol + 1, false)[1] or ""

    -- ── Header line: " N  BADGE  path ●" ────────────────────────────────

    local idx_str = tostring(idx)
    local idx_s = 0
    local idx_e = 1 + #idx_str + 2 -- " " + digits + "  "

    -- index number
    pcall(vim.api.nvim_buf_set_extmark, buf, ns, ln_header, idx_s, {
      end_col = math.min(idx_e, #header),
      hl_group = "QFBookmarkEntryIdx",
    })

    -- badge (always 4 chars: "MARK", "FIX ", "NOTE", "DBG ")
    local badge_s = idx_e
    local badge_e = badge_s + 4
    pcall(vim.api.nvim_buf_set_extmark, buf, ns, ln_header, badge_s, {
      end_col = math.min(badge_e, #header),
      hl_group = badge_hl(mark.mark_mode),
    })

    -- Path (after "  " separator following badge)
    local path_s = badge_e + 2
    local cur_pos = header:find(" ●", path_s, true) -- byte position of " ●"
    if cur_pos then
      pcall(vim.api.nvim_buf_set_extmark, buf, ns, ln_header, path_s, {
        end_col = cur_pos - 1,
        hl_group = "QFBookmarkEntryPath",
      })
      -- "●" is 3 bytes; highlight from the space before it to end of line
      pcall(vim.api.nvim_buf_set_extmark, buf, ns, ln_header, cur_pos, {
        end_col = #header,
        hl_group = "QFBookmarkEntryCurrentFile",
      })
    else
      pcall(vim.api.nvim_buf_set_extmark, buf, ns, ln_header, path_s, {
        end_col = #header,
        hl_group = "QFBookmarkEntryPath",
      })
    end

    -- ── Detail line: "         :lnum  preview text" ──────────────────────

    local lnum_s, lnum_e_byte = detail:match "():%d+()"
    if lnum_s then
      pcall(vim.api.nvim_buf_set_extmark, buf, ns, ln_detail, lnum_s - 1, {
        end_col = lnum_e_byte - 1,
        hl_group = "QFBookmarkEntryLnum",
      })
      local preview_s = lnum_e_byte + 1
      if preview_s <= #detail then
        pcall(vim.api.nvim_buf_set_extmark, buf, ns, ln_detail, preview_s, {
          end_col = #detail,
          hl_group = "QFBookmarkEntryDetail",
        })
      end
    end

    -- ── Symbol line: "         icon name > icon name" ─────────────────────
    -- only present when chain != "" — detect by checking it starts with spaces
    -- and is not a header (no " N  " pattern) and not a detail (no ":lnum")
    if symbol_line ~= "" and not symbol_line:match "^ %d+ " and not symbol_line:match "^%s+:%d+" then
      local sym_s = symbol_line:find "%S" -- first non-space byte (1-based)
      if sym_s then
        sym_s = sym_s - 1 -- 0-based
        -- check if first icon is fn/method (ƒ = 0xC6 0x92) or type icon
        local is_fn = symbol_line:sub(sym_s + 1, sym_s + 2) == "\xC6\x92"
        if is_fn then
          pcall(vim.api.nvim_buf_set_extmark, buf, ns, ln_symbol, sym_s, {
            end_col = #symbol_line,
            hl_group = "QFBookmarkEntryFnName",
          })
        else
          -- chain may have multiple segments: "TypeIcon Name > fnIcon name"
          -- highlight type part as EntrySymbolType and fn part as EntryFnName
          local sep = symbol_line:find(" > ", sym_s + 1, true)
          if sep then
            pcall(vim.api.nvim_buf_set_extmark, buf, ns, ln_symbol, sym_s, {
              end_col = sep - 1,
              hl_group = "QFBookmarkEntrySymbolType",
            })
            local fn_s = sep + 3 -- after " > "
            pcall(vim.api.nvim_buf_set_extmark, buf, ns, ln_symbol, fn_s - 1, {
              end_col = #symbol_line,
              hl_group = "QFBookmarkEntryFnName",
            })
          else
            pcall(vim.api.nvim_buf_set_extmark, buf, ns, ln_symbol, sym_s, {
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
---@param buf integer must popup buffer
function M.apply_entry_buffer_highlights(buf)
  local ns = vim.api.nvim_create_namespace "qfbookmark_popup_buffer_hl"
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  for lnum, line in ipairs(lines) do
    if line and line ~= "" then
      -- Flag
      local flag = line:find "%%" or line:find "%#"
      if flag then
        vim.api.nvim_buf_set_extmark(buf, ns, lnum - 1, 0, {
          end_col = 2,
          hl_group = "QFBookmarkEntryFlag",
        })
      end

      -- Path
      local lnum_s = line:find ":%d+"
      if lnum_s then
        local lnum_e = line:find("[^%d]", lnum_s + 1) or #line
        vim.api.nvim_buf_set_extmark(buf, ns, lnum - 1, lnum_s - 1, {
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
