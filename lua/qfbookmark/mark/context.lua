local QfbookmarkMarkUtils = require "qfbookmark.mark.utils"
local QfbookmarkMarkExtmark = require "qfbookmark.mark.extmark"

local M = {}

---Build the context table passed into every template builder.
---Always re-reads the buffer, so it reflects the *current* state of the range,
---not whatever it was when the annotation was first created.
---@param bufnr integer
---@param ns integer
---@param key integer
---@param category string
---@return table|nil
function M.build_ctx(bufnr, ns, key, category)
  local __mark = require "qfbookmark.mark"
  local meta = __mark.get_meta(key, category)
  if not meta then
    return nil
  end

  local id = meta.id

  local range = QfbookmarkMarkExtmark.get_annotation_range(bufnr, ns, id)
  if not range then
    return nil
  end

  local text
  if type(meta.note) == "table" then
    text = table.concat(meta.note, "\n")
  end

  return {
    bufnr = bufnr,
    extmark_id = id,
    category = meta.sign_category,
    text = text,
    lines = QfbookmarkMarkExtmark.get_annotation_lines(bufnr, ns, id),
    filetype = vim.bo[bufnr].filetype,
    filepath = vim.api.nvim_buf_get_name(bufnr),
    range = range,
    orphaned = QfbookmarkMarkExtmark.is_orphaned(bufnr, ns, id, meta),
  }
end

---@param bufnr integer
---@param ns integer
---@param key integer
---@param template_name string
---@return string|nil result, string|nil err
function M.build_context(bufnr, ns, key, template_name)
  local template = QfbookmarkMarkUtils.resolve_template(template_name)
  if not template then
    return nil, string.format("unknown context template '%s'", template_name)
  end

  local ctx = M.build_ctx(bufnr, ns, key, "NOTE")
  if not ctx then
    return nil, "annotation no longer exists"
  end

  if ctx.orphaned then
    return nil, "annotation range is orphaned (source block was likely deleted)"
  end

  local ok, result = pcall(template.builder, ctx)
  if not ok then
    return nil, string.format("template builder error: %s", result)
  end

  return result, nil
end

---Build context strings for a list of mark items.
---@param items table[]  list of { bufnr, key, text?, category? }
---@param ns integer
---@param template_name string
---@return string[] results  per-item built strings (skips errors silently)
---@return string[] labels   short label per item e.g. "fix · init.lua:42"
function M.build_multi(items, ns, template_name)
  local results = {}
  local labels = {}
  for _, item in ipairs(items) do
    local text, err = M.build_context(item.bufnr, ns, item.key, template_name)
    if text then
      local fname = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(item.bufnr), ":t")
      local range = M.build_ctx(item.bufnr, ns, item.key, "NOTE")
      local lnum = range and (range.range.start_row + 1) or "?"
      table.insert(results, text)
      table.insert(labels, string.format("%s · %s:%s", item.category or "NOTE", fname, lnum))
    end
  end
  return results, labels
end

---Send the built context somewhere. Default just copies to the unnamed register;
---override `sink` for actual plugin integration (avante, codecompanion, etc).
---@param text string
---@param target? string  -- e.g. "clipboard" | "register" | custom sink name
function M.dispatch(text, target)
  target = target or "clipboard"

  local QfbookmarkUtils = require "qfbookmark.utils"

  if target == "clipboard" then
    vim.fn.setreg("+", text)
    QfbookmarkUtils.info "context copied to clipboard"
    return
  end

  local cfg = require("qfbookmark.config").defaults or {}
  local sinks = (cfg.window.mark and cfg.window.mark.sinks) or {}
  local sink = sinks[target]

  if not sink then
    QfbookmarkUtils.info(string.format("qfbookmark: no sink registered for '%s', copied instead", target))
    vim.fn.setreg("+", text)
    return
  end

  sink(text)
end

return M
