-- lua/qfbookmark/qf_highlight.lua
local M = {}

local _ns = vim.api.nvim_create_namespace "qfbookmark_hl"
M.ns = _ns

-- ---------------------------------------------------------------------------
-- Treesitter helpers
-- ---------------------------------------------------------------------------
local _query_cache = {}
local function get_hl_query(lang)
  if _query_cache[lang] == nil then
    _query_cache[lang] = vim.treesitter.query.get(lang, "highlights") or false
  end
  return _query_cache[lang] or nil
end

---@param bufnr integer
---@param lnum  integer  1-indexed
---@return {sc:integer, ec:integer, hl:string}[]
local function ts_from_buf(bufnr, lnum)
  local ft = vim.bo[bufnr].filetype
  if ft == "" then
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
    for cap, node, meta in q:iter_captures(root, bufnr, row, row + 1) do
      if cap == nil then
        break
      end
      local range = vim.treesitter.get_range(node, bufnr, meta[cap])
      local sr, sc, _, er, ec = range[1], range[2], range[3], range[4], range[5]
      if sr > row then
        break
      end
      if er > row then
        ec = -1
      end
      out[#out + 1] = { sc = sc, ec = ec, hl = ("@%s.%s"):format(q.captures[cap], tree:lang()) }
    end
  end)
  return out
end

---@param text  string
---@param bufnr integer
---@param fname string
---@return {sc:integer, ec:integer, hl:string}[]
local function ts_from_string(text, bufnr, fname)
  local ft = (bufnr and bufnr > 0 and vim.api.nvim_buf_is_valid(bufnr)) and vim.bo[bufnr].filetype or ""
  if ft == "" then
    ft = vim.filetype.match { buf = bufnr, filename = fname } or ""
  end
  if ft == "" then
    return {}
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
    if er > 0 then
      ec = -1
    end
    out[#out + 1] = { sc = sc, ec = ec, hl = ("@%s.%s"):format(q.captures[cap], lang) }
  end
  return out
end

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
  local highlighter = STH.active[bufnr]
  if not highlighter then
    return {}
  end
  local ft = vim.bo[bufnr].filetype
  local out = {}
  local line0 = lnum - 1
  for _, client in pairs(highlighter.client_state) do
    local hs = client.current_result and client.current_result.highlights
    if hs then
      local lo, hi = 1, #hs + 1
      while lo < hi do
        local mid = bit.rshift(lo + hi, 1)
        if hs[mid].line < line0 then
          lo = mid + 1
        else
          hi = mid
        end
      end
      for i = lo, #hs do
        local tok = hs[i]
        if tok.line >= lnum then
          break
        end
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

-- ---------------------------------------------------------------------------
-- Line layout parser
-- ---------------------------------------------------------------------------
-- Supports any qftf format that uses "│" as separator (including nvim-bqf).
-- We locate the TWO "│" separators to find the text column.
-- Anything before the first │ = filename region.
-- Between │ and │ = lnum:col region.
-- After second │ = [optional type badge] + text.

local SEP = "│"
local SEP_LEN = #SEP -- 3 bytes UTF-8

---@class QFLine
---@field valid    boolean
---@field fname_s  integer  0-idx
---@field fname_e  integer  0-idx exclusive (just before the space before │)
---@field sep1_s   integer
---@field lnum_s   integer
---@field lnum_e   integer
---@field sep2_s   integer
---@field type_s   integer
---@field type_e   integer
---@field text_s   integer

---@param line string
---@param e    table
---@return QFLine
local function parse_qf_line(line, e)
  local s1 = line:find(SEP, 1, true)
  if not s1 then
    return { valid = false }
  end
  local s2 = line:find(SEP, s1 + SEP_LEN, true)
  if not s2 then
    return { valid = false }
  end

  -- Convert to 0-indexed.
  local sep1_s = s1 - 1
  local sep2_s = s2 - 1
  local after_sep2 = sep2_s + SEP_LEN

  -- qftf renders type as "" or " E" (space + uppercase letter).
  -- We detect the type from e.type, same as qftf does.
  local qtype_str = (e.type and e.type ~= "") and (" " .. e.type:sub(1, 1):upper()) or ""
  local type_len = #qtype_str -- 0 or 2

  local type_s = after_sep2
  local type_e = after_sep2 + type_len
  local text_s = type_e + 1 -- +1 skips the mandatory space: "│%s %s"

  return {
    valid = true,
    fname_s = 0,
    fname_e = sep1_s, -- include any trailing space before │
    sep1_s = sep1_s,
    lnum_s = sep1_s + SEP_LEN,
    lnum_e = sep2_s,
    sep2_s = sep2_s,
    type_s = type_s,
    type_e = type_e,
    text_s = text_s,
  }
end

-- ---------------------------------------------------------------------------
-- Resolve source col_offset
-- ---------------------------------------------------------------------------
-- e.text in qf items may be the raw source line (trimmed) OR something else
-- entirely (git diff output, grep match, etc.).
-- We try to find e.text inside the real source line to compute col_offset.
-- If not found (e.g. git diff), col_offset = 0 and we parse e.text as a string.

---@param e        table   qf item
---@param src_buf  integer|nil
---@param src_lnum integer|nil
---@return integer col_offset, boolean use_buf
local function resolve_col_offset(e, src_buf, src_lnum)
  if not (src_buf and src_lnum and vim.api.nvim_buf_is_loaded(src_buf)) then
    return 0, false
  end

  local src_lines = vim.api.nvim_buf_get_lines(src_buf, src_lnum - 1, src_lnum, false)
  local src_line = src_lines[1]
  if not src_line then
    return 0, false
  end

  if not e.text or e.text == "" then
    return 0, true
  end

  -- Strip leading/trailing whitespace (qftf often trims).
  local stripped = e.text:match "^%s*(.-)%s*$"
  if not stripped or stripped == "" then
    return 0, true
  end

  local pos = src_line:find(stripped, 1, true)
  if pos then
    return pos - 1, true -- 0-indexed offset
  end

  -- e.text not found in source line (git diff, grep, etc.) — fall back to
  -- string parser with no offset.
  return 0, false
end

-- ---------------------------------------------------------------------------
-- Apply highlights for one line
-- ---------------------------------------------------------------------------

local TYPE_HL = {
  E = "QFBookmarkError",
  W = "QFBookmarkWarn",
  I = "QFBookmarkInfo",
  H = "QFBookmarkHint",
  N = "QFBookmarkHint",
}

local function set_mark(buf, row, sc, ec, hl, pri)
  if sc >= ec and ec ~= -1 then
    return
  end
  pcall(vim.api.nvim_buf_set_extmark, buf, _ns, row, sc, {
    end_col = ec == -1 and -1 or ec,
    hl_group = hl,
    priority = pri,
  })
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

  -- Structural highlights -----------------------------------------------
  set_mark(qf_buf, row, L.fname_s, L.fname_e, "QFBookmarkFile", 100)
  set_mark(qf_buf, row, L.sep1_s, L.sep1_s + SEP_LEN, "QFBookmarkSep", 100)
  set_mark(qf_buf, row, L.lnum_s, L.lnum_e, "QFBookmarkLineNr", 100)
  set_mark(qf_buf, row, L.sep2_s, L.sep2_s + SEP_LEN, "QFBookmarkSep", 100)

  if e.type and e.type ~= "" then
    local t = e.type:sub(1, 1):upper()
    set_mark(qf_buf, row, L.type_s, L.type_e, TYPE_HL[t] or "Normal", 110)
  end

  -- Text column TS/LSP highlights ---------------------------------------
  local text_s = L.text_s
  if text_s >= line_len then
    return
  end

  local src_buf = e.bufnr and e.bufnr > 0 and e.bufnr or nil
  local src_lnum = e.lnum and e.lnum > 0 and e.lnum or nil

  local col_offset, use_buf = resolve_col_offset(e, src_buf, src_lnum)

  local ts_hls, lsp_hls = {}, {}
  if use_buf then
    ts_hls = ts_from_buf(src_buf, src_lnum)
    lsp_hls = lsp_from_buf(src_buf, src_lnum)
  else
    -- Buffer not loaded OR e.text is not a raw source line (e.g. git diff).
    -- Parse whatever text is in the qf column directly.
    local qf_text = line:sub(text_s + 1) -- text as shown in qf
    if qf_text ~= "" then
      ts_hls = ts_from_string(qf_text, src_buf, e.filename)
      -- For string-parsed highlights, cols are already relative to qf_text,
      -- so col_offset = 0 and text_s already accounts for position.
    end
  end

  -- Apply with col shifting from source-space → qf-space.
  local function apply_hl(sc, ec, hl, pri)
    local rel_sc = sc - col_offset
    local rel_ec = ec == -1 and -1 or (ec - col_offset)
    if rel_ec ~= -1 and rel_ec <= 0 then
      return
    end -- before our window
    local qf_sc = text_s + math.max(rel_sc, 0)
    local qf_ec = rel_ec == -1 and line_len or (text_s + rel_ec)
    if qf_sc >= line_len then
      return
    end
    qf_ec = math.min(qf_ec, line_len)
    set_mark(qf_buf, row, qf_sc, qf_ec, hl, 120 + (pri or 0))
  end

  for _, h in ipairs(ts_hls) do
    apply_hl(h.sc, h.ec, h.hl, 0)
  end
  for _, h in ipairs(lsp_hls) do
    apply_hl(h.sc, h.ec, h.hl, 10 + (h.pri or 0))
  end
end

-- ---------------------------------------------------------------------------
-- Public: apply to whole qf buffer
-- ---------------------------------------------------------------------------

function M.apply(qf_buf)
  if not vim.api.nvim_buf_is_valid(qf_buf) then
    return
  end

  local winid = vim.fn.bufwinid(qf_buf)
  local is_loc = winid ~= -1 and ((vim.fn.getwininfo(winid)[1] or {}).loclist == 1)

  local qf_data = (is_loc and winid ~= -1) and vim.fn.getloclist(winid, { items = true, id = 0 })
    or vim.fn.getqflist { items = true, id = 0 }

  if not qf_data or not qf_data.items then
    return
  end

  local lines = vim.api.nvim_buf_get_lines(qf_buf, 0, -1, false)
  for i, line in ipairs(lines) do
    apply_line(qf_buf, i - 1, line, qf_data.items[i])
  end
end

-- ---------------------------------------------------------------------------
-- Public: setup
-- ---------------------------------------------------------------------------

function M.setup()
  local defs = {
    QFBookmarkFile = { link = "Directory", default = true },
    QFBookmarkSep = { link = "NonText", default = true },
    QFBookmarkLineNr = { link = "LineNr", default = true },
    QFBookmarkError = { link = "DiagnosticError", default = true },
    QFBookmarkWarn = { link = "DiagnosticWarn", default = true },
    QFBookmarkInfo = { link = "DiagnosticInfo", default = true },
    QFBookmarkHint = { link = "DiagnosticHint", default = true },
  }
  for name, opts in pairs(defs) do
    vim.api.nvim_set_hl(0, name, opts)
  end

  local grp = vim.api.nvim_create_augroup("QFBookmarkHighlight", { clear = true })

  local function schedule_apply(buf)
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == "quickfix" then
        M.apply(buf)
      end
    end)
  end

  vim.api.nvim_create_autocmd("QuickFixCmdPost", {
    group = grp,
    callback = function()
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        local b = vim.api.nvim_win_get_buf(w)
        if vim.bo[b].buftype == "quickfix" then
          schedule_apply(b)
          break
        end
      end
    end,
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
