local QfbookmarkUtils = require "qfbookmark.utils"

---@class QFBookSelectedList
local SelectedList = {}
SelectedList.__index = SelectedList

--- Wrap a plain array of selected items with chainable methods.
---@param items table[]
---@return QFBookSelectedList
function SelectedList.wrap(items)
  return setmetatable(items or {}, SelectedList)
end

---@param target QFBookListProviders
function SelectedList:add_to(target)
  local valid_targets = { "buffers", "mark", "debug", "fix", "note", "quickfix", "loclist" }

  assert(
    vim.tbl_contains(valid_targets, target),
    string.format("invalid target '%s', expected one of: %s", target, table.concat(valid_targets, ", "))
  )

  if #self == 0 then
    return
  end

  if vim.tbl_contains({ "mark", "debug", "fix", "note" }, target) then
    local QfbookmarkBookmark = require "qfbookmark.mark"

    local mark_mode = target:upper()

    for _, item in ipairs(self) do
      local filename = item.filename or (item.info and item.info.name)
      local bufnr = item.bufnr or (item.filename and QfbookmarkUtils.resolve_bufnr(item.filename))
      if not bufnr then
        goto continue
      end

      local line = item.line or item.lnum or (item.info and item.info.lnum)

      -- Ensure the line number is not zero,
      -- required by vim.fn.sign_place (M.insert_sign:visual.lua)
      if line == 0 then
        line = 1
      end

      local col = item.col or (item.info and item.info.col)

      local text = item.text
        or vim.api.nvim_buf_get_lines(bufnr, (line == 0 and line or line - 1), line + 1, false)[1]
        or ""

      -- Ensure the column number is non-zero as well
      if col == 0 then
        col = 1
      end

      if filename then
        QfbookmarkBookmark.add_mark_at(bufnr, line, col, text, mark_mode)
      end
      ::continue::
    end

    QfbookmarkUtils.info(string.format("Added %d item(s) to marks", #self))
  elseif target == "quickfix" or target == "loclist" then
    local qf_items = {}
    for _, item in ipairs(self) do
      local filename = item.filename or (item.info and item.info.name)
      local bufnr = item.bufnr or (item.filename and QfbookmarkUtils.resolve_bufnr(item.filename))
      if not bufnr then
        goto continue
      end

      local line = item.line or item.lnum or (item.info and item.info.lnum)
      local text = item.text or ""
      local col = item.col or (item.info and item.info.col)

      qf_items[#qf_items + 1] = {
        filename = filename,
        lnum = line,
        col = col,
        text = text,
      }
      ::continue::
    end
    if target == "quickfix" then
      vim.fn.setqflist(qf_items, "a")
    else
      vim.fn.setloclist(0, qf_items, "a")
    end
    QfbookmarkUtils.info(string.format("Added %d item(s) to %s", #self, target))
  end
end

---@param template_name string  required when target == "note": the name of the template defined in
function SelectedList:add_note_to(template_name)
  if not template_name then
    QfbookmarkUtils.error "add_to(template_name) requires a template name."
    return
  end

  local Config = require("qfbookmark.config").defaults

  local TEMPLATES = vim.tbl_keys(Config.window.note.insert_to_note.templates) -- { mark, debug, note .. }

  assert(
    vim.tbl_contains(TEMPLATES, template_name),
    string.format("invalid template_name '%s', expected one of: %s", template_name, table.concat(TEMPLATES, ", "))
  )

  local QfbookmarkNote = require "qfbookmark.note"
  QfbookmarkNote.add_to_note(template_name)
end

--- Return the plain underlying array (in case caller needs to strip
--- the metatable, e.g. to vim.deepcopy or vim.inspect cleanly).
---@return table[]
function SelectedList:unwrap()
  local plain = {}
  for i, v in ipairs(self) do
    plain[i] = v
  end
  return plain
end

return SelectedList
