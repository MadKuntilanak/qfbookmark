local Config = require("qfbookmark.config").defaults
local QfbookmarkUtils = require "qfbookmark.utils"

local loaded = false
local Trouble

local silent_notify = false

local QF_CONTEXT_KEY = "qfbookmark_trouble_origin"

local function setup_trouble()
  if loaded then
    return Trouble
  end
  local ok, _ = pcall(require, "trouble")
  if not ok then
    if not silent_notify then
      QfbookmarkUtils.error "This integration requires `folke/trouble.nvim`"
    end
    return
  end
  Trouble = require "trouble"
  loaded = true
  return Trouble
end

local M = {}

---@param is_loc? boolean
---@return {mode: string, source: string}|nil
local function get_qf_origin(is_loc)
  local info = is_loc and vim.fn.getloclist(0, { context = true }) or vim.fn.getqflist { context = true }
  if type(info.context) ~= "table" then
    return nil
  end
  return info.context[QF_CONTEXT_KEY]
end

---@param mode string
---@param source string
---@param is_loc? boolean
local function set_qf_origin(mode, source, is_loc)
  local ctx = { [QF_CONTEXT_KEY] = { mode = mode, source = source } }
  if is_loc then
    vim.fn.setloclist(0, {}, "a", { context = ctx })
  else
    vim.fn.setqflist({}, "a", { context = ctx })
  end
end

---@param qf_entries table[]   raw entries from getqflist()/getloclist()
---@param origin_mode string   e.g. "lsp_references", "quickfix"
---@return trouble.Item[]
local function qf_to_trouble_items(qf_entries, origin_mode)
  local severities = {
    E = vim.diagnostic.severity.ERROR,
    W = vim.diagnostic.severity.WARN,
    I = vim.diagnostic.severity.INFO,
    H = vim.diagnostic.severity.HINT,
    N = vim.diagnostic.severity.HINT,
  }

  local is_lsp_mode = origin_mode and origin_mode:match "^lsp_"
  local is_diagnostic_mode = origin_mode and origin_mode:match "^diagnostics"

  local Item = require "trouble.item"

  local ret = {}
  for _, e in ipairs(qf_entries) do
    if e.valid == 1 then
      local row = e.lnum == 0 and 1 or e.lnum
      local col = (e.col == 0 and 1 or e.col) - 1
      local end_row = e.end_lnum == 0 and row or e.end_lnum
      local end_col = e.end_col == 0 and col or (e.end_col - 1)

      local bufnr = (e.bufnr and e.bufnr ~= 0) and e.bufnr or nil
      local fname = (e.filename and e.filename ~= "") and e.filename
        or (bufnr and vim.api.nvim_buf_get_name(bufnr) or nil)
      if not fname then
        goto continue
      end

      if not bufnr then
        bufnr = vim.fn.bufadd(fname)
      end
      if bufnr and not vim.api.nvim_buf_is_loaded(bufnr) then
        vim.fn.bufload(bufnr)
      end

      if is_lsp_mode then
        -- lsp_* format: "{text:ts} ({item.client}) {pos}"
        -- Read real source line like lsp.range_to_item does.
        local line_text
        if bufnr and vim.api.nvim_buf_is_loaded(bufnr) and row > 0 then
          local lines = vim.api.nvim_buf_get_lines(bufnr, row - 1, row, false)
          line_text = lines[1]
        end
        ret[#ret + 1] = Item.new {
          buf = bufnr,
          filename = fname,
          pos = { row, col },
          end_pos = { end_row, end_col },
          source = "lsp",
          item = {
            text = line_text and vim.trim(line_text) or e.text,
            type = e.type,
            client = nil,
            client_id = nil,
          },
        }
      elseif is_diagnostic_mode then
        -- diag format: "{severity_icon|item.type:DiagnosticSignWarn} {message:ts} {pos}"
        ret[#ret + 1] = Item.new {
          buf = bufnr,
          filename = fname,
          pos = { row, col },
          end_pos = { end_row, end_col },
          message = e.text,
          severity = severities[e.type] or 0,
          source = "diagnostics",
        }
      else
        -- qf format: "{severity_icon|item.type:DiagnosticSignWarn} {text:ts} {pos}"
        -- Identical structure to qf.lua M.get_list() — source="qf", severity field.
        ret[#ret + 1] = Item.new {
          pos = { row, col },
          end_pos = { end_row, end_col },
          text = e.text,
          severity = severities[e.type] or 0,
          buf = bufnr,
          filename = fname,
          item = e,
          source = "qf",
        }
      end

      ::continue::
    end
  end

  Item.add_id(ret, { "severity" })
  Item.add_text(ret, { mode = "full" })
  return ret
end

---@param mode  string
---@param items trouble.Item[]
local function open_trouble_with_items(mode, items)
  local View = require "trouble.view"
  local Tree = require "trouble.tree"
  local TConfig = require "trouble.config"

  local opts = TConfig.get(mode)
  opts.auto_refresh = false
  opts.auto_jump = false

  -- If an open view for this mode exists, just update its data in-place.
  local existing = View.get { mode = mode, open = true }
  if #existing > 0 then
    local view = existing[1].view
    if view.win:valid() then
      for _, section in ipairs(view.sections) do
        section.items = items
        section.node = Tree.build(items, section.section)
        section:update() -- triggers on_update → view:render()
      end
      view.win:focus()
      return
    end
  end

  -- No open view
  -- create a new one and inject items before the first render.
  local view = View.new(opts)

  -- Freeze: M:refresh() in view/init.lua checks view._frozen and skips section:refresh()
  -- (the LSP query path) when true.
  view._frozen = true

  for _, section in ipairs(view.sections) do
    section.items = items
    section.node = Tree.build(items, section.section)
  end

  vim.schedule(function()
    view:open()
  end)

  view:wait(function()
    if view.win.win and vim.api.nvim_win_is_valid(view.win.win) then
      view.win:focus()
    end

    view._frozen = false
  end)
end

-- ---------------------------------------------------------------------------
-- data_troubles: read items from the currently open trouble window
-- ---------------------------------------------------------------------------
---@return QFBookLists
local function data_troubles()
  local severities_key = {
    [1] = "E",
    [2] = "W",
    [3] = "I",
    [4] = "H",
  }

  local list_items = {
    items = {},
    title = "",
    trouble_mode = nil,
    trouble_source = nil,
  }

  if vim.bo.filetype ~= "trouble" then
    return list_items
  end

  local items = Trouble.get_items()
  local View = require "trouble.view"
  local views = View.get { open = true }
  local current_mode = #views > 0 and views[#views].mode or nil

  for _, item in pairs(items) do
    local text = item.text
    local _type = item.type
    if current_mode == "diagnostics" then
      text = item.message
      _type = severities_key[item.severity] or ""
    end

    table.insert(list_items.items, {
      bufnr = item.buf,
      text = text,
      lnum = item.pos[1],
      col = item.pos[2],
      filename = item.filename,
      type = _type,
      -- severity = severities[item.type] or 0,
    })

    list_items.title = "Trouble-" .. item.source
    list_items.trouble_mode = current_mode or item.source
    list_items.trouble_source = item.source
  end

  return list_items
end

-- ---------------------------------------------------------------------------
-- toggle_trouble_window: trouble → quickfix
-- ---------------------------------------------------------------------------
---@param list_type QFBookListType
---@param is_loc? boolean
local function toggle_trouble_window(list_type, is_loc)
  is_loc = is_loc or false

  local list_items = data_troubles()

  local qf_win = QfbookmarkUtils.windows_is_opened { "trouble" }
  if qf_win.found then
    Trouble.close()
  end

  local open_cmd = list_type == "loclist" and Config.window.quickfix.lopen or Config.window.quickfix.copen

  QfbookmarkUtils.save_to_qf_and_auto_open_qf(list_items, open_cmd, is_loc)

  -- Tag the new qf list with origin metadata.
  if list_items.trouble_mode then
    set_qf_origin(list_items.trouble_mode, list_items.trouble_source or "", is_loc)
  end
end

-- ---------------------------------------------------------------------------
-- toggle_qf_window: quickfix → trouble (restoring original mode + items)
-- ---------------------------------------------------------------------------
---@param list_type QFBookListType
---@param is_loc? boolean
local function toggle_qf_window(list_type, is_loc)
  is_loc = is_loc or QfbookmarkUtils.is_loclist()

  local origin = get_qf_origin(is_loc)

  -- Read raw entries BEFORE closing the window.
  local raw_entries
  if origin and origin.mode then
    local raw_data = QfbookmarkUtils.get_data_qf(is_loc)
    local raw = is_loc and raw_data.location or raw_data.quickfix
    raw_entries = raw and raw.items or {}
  end

  -- Close the qf/loc window.
  local qf_win = QfbookmarkUtils.windows_is_opened { "qf" }
  if qf_win.found then
    vim.cmd(is_loc and "lclose" or "cclose")
  end

  if origin and origin.mode and raw_entries then
    local trouble_items = qf_to_trouble_items(raw_entries, origin.mode)
    open_trouble_with_items(origin.mode, trouble_items)
  elseif list_type == "loclist" then
    vim.cmd.Trouble "loclist focus"
  else
    vim.cmd.Trouble "quickfix focus"
  end
end

-- ╓─────────────────────────────────────────────────────────────────────────────╖
-- ║                                 Public API                                  ║
-- ╙─────────────────────────────────────────────────────────────────────────────╜
---@param is_trouble_ft? boolean
---@param list_type QFBookListType
---@param is_loc? boolean
function M.handle_toggle_qf(is_trouble_ft, list_type, is_loc)
  Trouble = setup_trouble()
  if not Trouble then
    return
  end

  is_loc = is_loc or false
  is_trouble_ft = is_trouble_ft or false

  if is_trouble_ft then
    toggle_trouble_window(list_type, is_loc)
  else
    toggle_qf_window(list_type, is_loc)
  end
end

return M
