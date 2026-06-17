local QfbookmarkUtils = require "qfbookmark.utils"

local M = {}

local _ns = vim.api.nvim_create_namespace "qfbookmark_hl"
M.ns = _ns

local _query_cache = {}
local function get_hl_query(lang)
  if _query_cache[lang] == nil then
    _query_cache[lang] = vim.treesitter.query.get(lang, "highlights") or false
  end
  return _query_cache[lang] or nil
end

-- Returns highlights for a single line in a loaded buffer.
-- Mirrors quicker.nvim buf_get_ts_highlights exactly.
---@param bufnr integer
---@param lnum  integer  1-indexed
---@return {sc:integer, ec:integer, hl:string}[]
local function ts_from_buf(bufnr, lnum)
  local ft = vim.bo[bufnr].filetype
  if not ft or ft == "" then
    ft = vim.filetype.match { buf = bufnr } or ""
  end
  local lang = vim.treesitter.language.get_lang(ft) or ft
  if lang == "" then
    return {}
  end
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, lang)
  if not ok or not parser then
    return {}
  end
  local row = lnum - 1
  if not parser:is_valid() then
    parser:parse(true)
  end

  local out = {}
  parser:for_each_tree(function(tstree, tree)
    if not tstree then
      return
    end
    local root = tstree:root()
    local rs, _, re = root:range()
    if rs > row or re < row then
      return
    end
    local q = get_hl_query(tree:lang())
    if not q then
      return
    end

    -- Pass (row, re+1) as range so iter_captures is sorted from `row` onward.
    -- This makes `break` safe when start_row > row (same as quicker.nvim).
    for cap, node, meta in q:iter_captures(root, bufnr, row, re + 1) do
      if cap == nil then
        break
      end
      local range = vim.treesitter.get_range(node, bufnr, meta[cap])
      local sr, sc, _, er, ec = range[1], range[2], range[3], range[4], range[5]
      if sr > row then
        break
      end
      if er > sr then
        ec = -1
      end -- multiline node: extend to EOL
      out[#out + 1] = { sc = sc, ec = ec, hl = ("@%s.%s"):format(q.captures[cap], tree:lang()) }
    end
  end)
  return out
end

-- Fallback: parse the raw text string when the buffer is not loaded.
-- Mirrors quicker.nvim get_heuristic_ts_highlights.
---@param text  string
---@param bufnr integer|nil
---@param fname string|nil
---@return {sc:integer, ec:integer, hl:string}[]
local function ts_from_string(text, bufnr, fname)
  local ft = (bufnr and bufnr > 0 and vim.api.nvim_buf_is_valid(bufnr)) and vim.bo[bufnr].filetype or ""
  if ft == "" then
    ft = vim.filetype.match { buf = bufnr, filename = fname } or ""
  end
  if ft == "" then
    -- Fallback highlight for filenames when no filetype is available
    return { {
      sc = 0,
      ec = 200,
      hl = "QFBookmarkQfText",
    } }
  end
  local lang = vim.treesitter.language.get_lang(ft)
  if not lang then
    return {}
  end
  local ok, parser = pcall(vim.treesitter.get_string_parser, text, lang)
  if not ok then
    return {}
  end
  local root = parser:parse(true)[1]:root()
  local q = get_hl_query(lang)
  if not q then
    return {}
  end

  local out = {}
  for cap, node, meta in q:iter_captures(root, text) do
    if cap == nil then
      break
    end
    local range = vim.treesitter.get_range(node, text, meta[cap])
    local sr, sc, _, er, ec = range[1], range[2], range[3], range[4], range[5]
    if sr > 0 then
      break
    end
    if er > sr then
      ec = -1
    end
    out[#out + 1] = { sc = sc, ec = ec, hl = ("@%s.%s"):format(q.captures[cap], lang) }
  end
  return out
end

-- Mirrors quicker.nvim buf_get_lsp_highlights.
---@param bufnr integer
---@param lnum  integer  1-indexed
---@return {sc:integer, ec:integer, hl:string, pri:integer}[]
local function lsp_from_buf(bufnr, lnum)
  local ok, STH = pcall(function()
    return vim.lsp.semantic_tokens.__STHighlighter
  end)
  if not ok or not STH then
    return {}
  end
  local h = STH.active[bufnr]
  if not h then
    return {}
  end
  local ft = vim.bo[bufnr].filetype
  local out = {}
  for _, client in pairs(h.client_state) do
    local hs = client.current_result and client.current_result.highlights
    if hs then
      -- binary search (same as quicker.nvim lower_bound)
      local lo, hi = 1, #hs + 1
      while lo < hi do
        local mid = bit.rshift(lo + hi, 1)
        if hs[mid].line < lnum - 1 then
          lo = mid + 1
        else
          hi = mid
        end
      end
      for i = lo, #hs do
        local tok = hs[i]
        if tok.line >= lnum then
          break
        end -- same as quicker: >= lnum (1-idx)
        out[#out + 1] = { sc = tok.start_col, ec = tok.end_col, hl = ("@lsp.type.%s.%s"):format(tok.type, ft), pri = 0 }
        for mod in pairs(tok.modifiers or {}) do
          out[#out + 1] = { sc = tok.start_col, ec = tok.end_col, hl = ("@lsp.mod.%s.%s"):format(mod, ft), pri = 1 }
          out[#out + 1] = {
            sc = tok.start_col,
            ec = tok.end_col,
            hl = ("@lsp.typemod.%s.%s.%s"):format(tok.type, mod, ft),
            pri = 2,
          }
        end
      end
    end
  end
  return out
end

-- +-----------------------------------------------------------------------------+
-- | Line layout parser                                                          |
-- +-----------------------------------------------------------------------------+
local SEP = "│"
local SEP_LEN = #SEP -- 3 bytes UTF-8

local function parse_qf_line(line, e)
  local s1 = line:find(SEP, 1, true)
  if not s1 then
    return { valid = false }
  end
  local s2 = line:find(SEP, s1 + SEP_LEN, true)
  if not s2 then
    return { valid = false }
  end

  local sep1_s = s1 - 1
  local sep2_s = s2 - 1
  local after_sep2 = sep2_s + SEP_LEN

  local qtype_str = (e.type and e.type ~= "") and (" " .. e.type:sub(1, 1):upper()) or ""
  local type_len = #qtype_str -- 0 or 2

  local type_s = after_sep2
  local type_e = type_s + type_len
  local text_s = type_e + 1 -- skip mandatory space before text

  return {
    valid = true,
    fname_s = 0,
    fname_e = sep1_s,
    sep1_s = sep1_s,
    lnum_s = sep1_s + SEP_LEN,
    lnum_e = sep2_s,
    sep2_s = sep2_s,
    type_s = type_s,
    type_e = type_e,
    text_s = text_s,
  }
end

-- +-----------------------------------------------------------------------------+
-- | Resolve col_offset                                                          |
-- +-----------------------------------------------------------------------------+
local function resolve_col_offset(e, src_buf, src_lnum)
  if not (src_buf and src_lnum and vim.api.nvim_buf_is_loaded(src_buf)) then
    return 0, false
  end
  local lines = vim.api.nvim_buf_get_lines(src_buf, src_lnum - 1, src_lnum, false)
  local src_line = lines[1]
  if not src_line then
    return 0, false
  end
  if not e.text or e.text == "" then
    return 0, true
  end

  -- Try exact match first, then stripped.
  local pos = src_line:find(e.text, 1, true)
  if pos then
    return pos - 1, true
  end

  local stripped = e.text:match "^%s*(.-)%s*$"
  if stripped and stripped ~= "" then
    pos = src_line:find(stripped, 1, true)
    if pos then
      return pos - 1, true
    end
  end

  return 0, false
end

-- +-----------------------------------------------------------------------------+
-- | Apply highlights for one line                                               |
-- +-----------------------------------------------------------------------------+
local TYPE_HL = {
  E = "QFBookmarkQfError",
  W = "QFBookmarkQfWarn",
  I = "QFBookmarkQfInfo",
  H = "QFBookmarkQfHint",
  N = "QFBookmarkQfHint",
}

-- CRITICAL: always use strict=false so out-of-bounds cols don't silently fail.
-- CRITICAL: ec=-1 means "to EOL" — must use end_row+hl_eol, NOT end_col=-1.
local function set_mark(buf, row, sc, ec, hl, pri)
  if ec ~= -1 and sc >= ec then
    return
  end
  local opts = {
    hl_group = hl,
    priority = pri,
    strict = false, -- don't error on out-of-bounds cols
  }
  if ec == -1 then
    -- Span to end of line.
    opts.end_row = row + 1
    opts.end_col = 0
    opts.hl_eol = true
  else
    opts.end_col = ec
  end
  pcall(vim.api.nvim_buf_set_extmark, buf, _ns, row, sc, opts)
end

---@param qf_buf integer
---@param row    integer  0-indexed
---@param line   string
---@param e      table
local function apply_line(qf_buf, row, line, e)
  vim.api.nvim_buf_clear_namespace(qf_buf, _ns, row, row + 1)
  if not (e and e.valid == 1) then
    return
  end

  local L = parse_qf_line(line, e)
  if not L.valid then
    return
  end

  local line_len = #line

  local path_text = line:sub(L.fname_s + 1, L.fname_e)
  local last_slash = nil
  for i = #path_text, 1, -1 do
    if path_text:sub(i, i) == "/" then
      last_slash = i
      break
    end
  end

  -- Structural columns.
  if last_slash then
    set_mark(qf_buf, row, L.fname_s, L.fname_e, "QFBookmarkQfFile", 100)
    -- Basename
    set_mark(qf_buf, row, last_slash, L.fname_e + last_slash, "QFBookmarkQfFileBasename", 100)
  else
    set_mark(qf_buf, row, L.fname_s, L.fname_e, "QFBookmarkQfFileBasename", 100)
  end
  set_mark(qf_buf, row, L.sep1_s, L.sep1_s + SEP_LEN, "QFBookmarkQfSep", 100)
  set_mark(qf_buf, row, L.lnum_s, L.lnum_e, "QFBookmarkQfLineNr", 100)
  set_mark(qf_buf, row, L.sep2_s, L.sep2_s + SEP_LEN, "QFBookmarkQfSep", 100)

  if e.type and e.type ~= "" then
    local t = e.type:sub(1, 1):upper()
    set_mark(qf_buf, row, L.type_s, L.type_e, TYPE_HL[t] or "Normal", 110)
  end

  local text_s = L.text_s
  if text_s >= line_len then
    return
  end

  local src_buf = (e.bufnr and e.bufnr > 0) and e.bufnr or nil
  local src_lnum = (e.lnum and e.lnum > 0) and e.lnum or nil

  local col_offset, use_buf = resolve_col_offset(e, src_buf, src_lnum)
  local ts_hls, lsp_hls = {}, {}

  if use_buf and src_buf and src_lnum then
    ts_hls = ts_from_buf(src_buf, src_lnum)
    lsp_hls = lsp_from_buf(src_buf, src_lnum)
  else
    local qf_text = line:sub(text_s + 1)
    if qf_text ~= "" then
      ts_hls = ts_from_string(qf_text, src_buf, e.filename)
      col_offset = 0 -- string-parsed cols already relative to qf_text
    end
  end

  -- Shift source col offsets → qf buffer col offsets.
  local function apply_hl(sc, ec, hl, pri)
    local rel_sc = sc - col_offset
    local rel_ec = ec == -1 and -1 or (ec - col_offset)
    if rel_ec ~= -1 and rel_ec <= 0 then
      return
    end
    local qf_sc = text_s + math.max(rel_sc, 0)
    local qf_ec = rel_ec == -1 and -1 or math.min(text_s + rel_ec, line_len)
    if qf_sc >= line_len then
      return
    end
    set_mark(qf_buf, row, qf_sc, qf_ec, hl, 120 + (pri or 0))
  end

  for _, h in ipairs(ts_hls) do
    apply_hl(h.sc, h.ec, h.hl, 0)
  end

  for _, h in ipairs(lsp_hls) do
    apply_hl(h.sc, h.ec, h.hl, 10 + (h.pri or 0))
  end
end

-- +-----------------------------------------------------------------------------+
-- | Apply to whole qf buffer                                                    |
-- +-----------------------------------------------------------------------------+
local function apply(qf_buf)
  if not vim.api.nvim_buf_is_valid(qf_buf) then
    return
  end

  local is_loc = QfbookmarkUtils.is_loclist()
  local raw_data = QfbookmarkUtils.get_data_qf(is_loc)

  local qf_data = is_loc and raw_data.location or raw_data.quickfix

  if not qf_data or not qf_data.items then
    return
  end

  local lines = vim.api.nvim_buf_get_lines(qf_buf, 0, -1, false)
  for i, line in ipairs(lines) do
    apply_line(qf_buf, i - 1, line, qf_data.items[i])
  end
end

-- ╓─────────────────────────────────────────────────────────────────────────────╖
-- ║                                 Public API                                  ║
-- ╙─────────────────────────────────────────────────────────────────────────────╜
function M.setup()
  local defs = {
    QFBookmarkQfFile = { link = "Directory", default = true },
    QFBookmarkQfFileBasename = { link = "Normal", default = true },
    QFBookmarkQfText = { link = "Normal", default = true },
    QFBookmarkQfSep = { link = "NonText", default = true, bold = false },
    QFBookmarkQfLineNr = { link = "LineNr", default = true, bold = false },
    QFBookmarkQfError = { link = "DiagnosticError", default = true },
    QFBookmarkQfWarn = { link = "DiagnosticWarn", default = true },
    QFBookmarkQfInfo = { link = "DiagnosticInfo", default = true },
    QFBookmarkQfHint = { link = "DiagnosticHint", default = true },
  }
  for name, opts in pairs(defs) do
    vim.api.nvim_set_hl(0, name, opts)
  end

  local grp = vim.api.nvim_create_augroup("QFBookmarkHighlight", { clear = true })

  local function schedule_apply(buf)
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == "quickfix" then
        apply(buf)
      end
    end)
  end

  local function find_qf_buf_and_apply()
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      local b = vim.api.nvim_win_get_buf(w)
      if vim.bo[b].buftype == "quickfix" then
        schedule_apply(b)
      end
    end
  end

  vim.api.nvim_create_autocmd("QuickFixCmdPost", {
    group = grp,
    callback = find_qf_buf_and_apply,
  })

  vim.api.nvim_create_autocmd({ "BufWinEnter", "FileType" }, {
    group = grp,
    pattern = "quickfix",
    callback = function(ev)
      schedule_apply(ev.buf)
    end,
  })
end

return M
