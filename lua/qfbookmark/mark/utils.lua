local Config = require("qfbookmark.config").defaults

local QfbookmarkUtils = require "qfbookmark.utils"

local M = {
  namespace_cache = {},
}

local MAX_NOTE_LEN = 25

---@param namespace_name string
function M.register_namespace(namespace_name)
  if not M.namespace_cache[namespace_name] then
    M.namespace_cache[namespace_name] = vim.api.nvim_create_namespace(namespace_name)
  end
  return M.namespace_cache[namespace_name]
end

---@param bufnr integer
---@param ns integer
function M.del_namespace(bufnr, ns)
  if QfbookmarkUtils.is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  end
end

-- built-in fallback templates, always available even with no user config
local BUILTIN_TEMPLATES = {
  copy_raw = {
    description = "Just the raw code, no wrapping",
    builder = function(ctx)
      return table.concat(ctx.lines, "\n")
    end,
  },
}

---@return QFBookSpec
function M.get_keyword_def(category)
  local keywords = (Config.extmarks and Config.extmarks.keywords) or {}
  local keyword_def = keywords[category]
  return keyword_def
end

--- Check whether mark data exists in the bookmark storage.
--- This only checks the internal `mark_lists` table and does not inspect
--- placed signs or extmarks in the buffer.
---@param mark_lists QFBookmarkBufferMark
---@param category QFBookMarkMode
---@param key? integer
---@param bufnr? integer
---@return boolean
function M.is_valid_key(mark_lists, category, key, bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not mark_lists[category] or not mark_lists[category][key] then
    return false
  end

  return true
end

local function get_templates()
  return (Config.window.mark and Config.window.mark.context_templates.handler) or {}
end

---@param template_name string
---@return table|nil
function M.resolve_template(template_name)
  return get_templates()[template_name] or BUILTIN_TEMPLATES[template_name]
end

---@return string[]  ordered template names, builtins first then user-defined
function M.template_names()
  local names = {}
  for name in pairs(BUILTIN_TEMPLATES) do
    table.insert(names, name)
  end
  for name in pairs(get_templates()) do
    table.insert(names, name)
  end
  table.sort(names)
  return names
end

function M.get_keywords()
  return (Config.extmarks and Config.extmarks.keywords) or {}
end

---Build an ordered list of { name, def } from the keywords table.
---Defaults (mark/fix/debug/note) are surfaced first if present, then the rest.
function M.ordered_keywords()
  local keywords = M.get_keywords()
  local default_order = { "mark", "fix", "debug", "note" }
  local seen = {}
  local ordered = {}

  for _, name in ipairs(default_order) do
    if keywords[name] then
      table.insert(ordered, { name = name, def = keywords[name] })
      seen[name] = true
    end
  end

  for name, def in pairs(keywords) do
    if not seen[name] then
      table.insert(ordered, { name = name, def = def })
    end
  end

  return ordered
end

function M.resolve_mark_sign(bufnr)
  M.del_namespace(bufnr, Config.ns)

  -- clear all signs
  local ok_signs, signinfo = pcall(vim.fn.sign_getplaced, bufnr, { group = Config.sign_group })
  if ok_signs and signinfo and signinfo[1] and signinfo[1].signs then
    for _, sign in pairs(signinfo[1].signs) do
      pcall(vim.fn.sign_unplace, Config.sign_group, { buffer = bufnr, id = sign.id })
    end
  end
end

---@param bufnr integer
---@param lnum integer
---@return boolean
local function is_not_valid_line(bufnr, lnum)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  return lnum >= 0 and lnum < line_count
end

---@param bufnr integer
---@param lnum integer
---@param col integer
---@return boolean
function M.is_not_valid_line_and_col(bufnr, lnum, col)
  if is_not_valid_line(bufnr, lnum) then
    return false
  end

  local text = vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)[1] or ""
  local line_len = #text
  return col >= 0 and col <= line_len
end

---@return integer start_line, integer end_line  (1-indexed, inclusive)
function M.visual_range()
  local start_line = vim.fn.line "v"
  local end_line = vim.fn.line "."

  if start_line == 0 or end_line == 0 then
    start_line = vim.fn.getpos("'<")[2]
    end_line = vim.fn.getpos("'>")[2]
  end

  return math.min(start_line, end_line), math.max(start_line, end_line)
end

function M.clamp_range(bufnr, start_line, end_line)
  local line_count = math.max(1, vim.api.nvim_buf_line_count(bufnr))
  start_line = math.max(1, math.min(start_line, line_count))
  end_line = math.max(1, math.min(end_line, line_count))
  return math.min(start_line, end_line), math.max(start_line, end_line)
end

---@param keyword_def table
---@param text string|string[]
function M.render_virt_text(keyword_def, text)
  if not text then
    QfbookmarkUtils.error("mark.utils.render_virt_text", "text is nil")
    return
  end

  local max_len = MAX_NOTE_LEN or 25

  ---@type string
  local display_text = ""

  if type(text) == "table" then
    display_text = text[1] or ""
  elseif type(text) == "string" then
    display_text = text
  end

  local display = display_text

  if vim.fn.strdisplaywidth(display_text) > max_len then
    display = vim.fn.strcharpart(display_text, 0, max_len) .. "…"
  end

  if display == "" then
    display = keyword_def.description or ""
  end

  local icon = keyword_def.icon or ""

  return {
    { (" %s %s"):format(icon, display), keyword_def.hl_group },
  }
end

return M
