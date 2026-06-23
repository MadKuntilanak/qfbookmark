local QfbookmarkUtils = require "qfbookmark.utils"

local function tbl_count(tbl)
  local count = 0
  for _ in pairs(tbl) do
    count = count + 1
  end
  return count
end

local notify = function(success_add, already_add)
  local added = tbl_count(success_add)
  local skipped = tbl_count(already_add)

  local parts = {}

  if added > 0 then
    parts[#parts + 1] = string.format("added %d", added)
  end

  if skipped > 0 then
    parts[#parts + 1] = string.format("skipped %d", skipped)
  end

  if #parts > 0 then
    QfbookmarkUtils.info(string.format("Added %d item(s); skipped %d item(s) already present.", added, skipped))
  end
end

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

    local already_add = {}
    local success_add = {}

    for _, item in ipairs(self) do
      local filename = item.filename or (item.info and item.info.name)
      local bufnr = item.bufnr or (item.filename and QfbookmarkUtils.resolve_bufnr(item.filename))
      if not QfbookmarkUtils.is_valid(bufnr) then
        bufnr = QfbookmarkUtils.resolve_bufnr(filename)
      end

      local line = item.line or item.lnum or (item.info and item.info.lnum)

      -- Ensure the line number is not zero,
      -- required by vim.fn.sign_place (M.insert_sign:visual.lua)
      if line == 0 then
        line = 1
      end

      local col = item.col or (item.info and item.info.col)

      ---@cast bufnr integer
      local text = item.text
        or vim.api.nvim_buf_get_lines(bufnr, (line == 0 and line or line - 1), line + 1, false)[1]
        or ""

      -- Ensure the column number is non-zero as well
      if col == 0 then
        col = 1
      end

      if filename then
        local ok = QfbookmarkBookmark.add_mark_at(bufnr, line, col, text, mark_mode)
        local id = tonumber(line .. bufnr)
        if not id then
          goto continue
        end

        if not ok then
          already_add[id] = true
        else
          success_add[id] = true
        end
      end
      ::continue::
    end

    notify(success_add, already_add)
  elseif target == "quickfix" or target == "loclist" then
    local qf_items = {}
    for _, item in ipairs(self) do
      local filename = item.filename or (item.info and item.info.name)
      local bufnr = item.bufnr or (item.filename and QfbookmarkUtils.resolve_bufnr(item.filename))
      if not QfbookmarkUtils.is_valid(bufnr) then
        bufnr = QfbookmarkUtils.resolve_bufnr(filename)
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
    end

    if target == "quickfix" then
      vim.fn.setqflist(qf_items, "a")
    else
      vim.fn.setloclist(0, qf_items, "a")
    end

    QfbookmarkUtils.info(string.format("Added %d item(s) to %s", #self, target))

    vim.schedule(function()
      local qf = require "qfbookmark.qf"
      local list_type = target == "quickfix" and "quickfix" or "loclist"
      qf.toggle_list(list_type)
    end)
  end
end

---@param template_name string  required when target == "note": the name of the template defined in
function SelectedList:add_note_to(template_name)
  ---@diagnostic disable-next-line: undefined-field
  assert(self.type == "note", "This method is only available for the note provider.")

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
