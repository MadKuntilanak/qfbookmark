local Config = require("qfbookmark.config").defaults

local QfbookmarkUIUtils = require "qfbookmark.ui.utils"
local QfbookmarkUtils = require "qfbookmark.utils"
local QfbookmarkNav = require "qfbookmark.nav"
local QfbookmarkUIPopup = require "qfbookmark.ui.popup"

local M = {}

local Mapping = {}

-- ╓─────────────────────────────────────────────────────────────────────────────╖
-- ║                                   GENERAL                                   ║
-- ╙─────────────────────────────────────────────────────────────────────────────╜

---@param key string
function Mapping.press_normal_key(key, is_with_bracket)
  is_with_bracket = is_with_bracket or false

  local pkey = function()
    if is_with_bracket then
      return "<" .. key .. ">"
    end
    return key
  end

  if QfbookmarkUtils.is_buf_readonly(Mapping.buf) then
    vim.api.nvim_set_option_value("modifiable", true, { buf = Mapping.buf })
    vim.api.nvim_set_option_value("readonly", false, { buf = Mapping.buf })
  end

  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(pkey(), true, false, true), "n", true)
end

function Mapping.exit_close()
  if Mapping.is_buffers then
    QfbookmarkUIUtils.close_win { Mapping.popup.win }
    QfbookmarkUIUtils.clean_up(Mapping.popup)
  elseif Mapping.is_harpoon then
    local lines_raw = vim.api.nvim_buf_get_lines(Mapping.buf, 0, -1, false)

    QfbookmarkUIUtils.close_win { Mapping.popup.win, Mapping.popup.preview and Mapping.popup.preview.win or nil }

    vim.schedule(function()
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", true)

      -- detail lines (even, leading indent) are skipped
      local out_lines = {}
      for _, raw in ipairs(lines_raw) do
        local idx_str = raw:match "^ (%d+) "
        if idx_str then
          local original_idx = tonumber(idx_str)
          local ln = Mapping.entry_start_line and Mapping.entry_start_line[original_idx]
          local hval = Mapping.harpoon_map[ln]
          if hval then
            out_lines[#out_lines + 1] = hval
          end
        end
      end
      if not (#lines_raw == 0 and #lines_raw[1] == 0) then
        if Mapping.cb then
          Mapping.cb(out_lines)
        end
      end
      QfbookmarkUIUtils.clean_up(Mapping.popup)
    end)
  else
    QfbookmarkUIUtils.close_win { Mapping.popup.win, Mapping.popup.preview and Mapping.popup.preview.win or nil }
    QfbookmarkUIUtils.clean_up(Mapping.popup)
  end

  vim.cmd.stopinsert()
end

---@param open_mode OpenMode
function Mapping.setup_open_key(open_mode)
  local cur_line_nr = vim.api.nvim_win_get_cursor(0)[1]

  QfbookmarkUIUtils.close_win { Mapping.popup.win, Mapping.popup.preview and Mapping.popup.preview.win or nil }

  vim.schedule(function()
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", true)

    if Mapping.is_harpoon then
      local hval = Mapping.harpoon_map[cur_line_nr]
      if hval then
        for _, m in pairs(Mapping.contents) do
          if m.harpoon == hval then
            QfbookmarkNav.jump_to {
              filename = m.filename,
              col = m.col,
              line = m.line,
              mode_open = open_mode,
            }
            break
          end
        end
      end
    end

    if Mapping.is_buffers then
      ---@type QFBufferItem
      local hval = Mapping.harpoon_map[cur_line_nr]
      if hval then
        QfbookmarkNav.jump_to {
          filename = hval.info.name,
          col = hval.info.col,
          line = hval.info.lnum,
          mode_open = open_mode,
        }
      end
    end

    QfbookmarkUIUtils.clean_up(Mapping.popup)
  end)
end

-- ╓─────────────────────────────────────────────────────────────────────────────╖
-- ║                                    SAVE                                     ║
-- ╙─────────────────────────────────────────────────────────────────────────────╜

Mapping.save = {}

function Mapping.save.save_input()
  local lines = vim.api.nvim_buf_get_lines(Mapping.buf, 0, -1, false)
  local input = lines[1] or ""
  QfbookmarkUIUtils.close_win { Mapping.popup.win, Mapping.popup.preview and Mapping.popup.preview.win or nil }

  vim.schedule(function()
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", true)
    if input == "" then
      return
    end

    if Mapping.cb then
      Mapping.cb(input)
    end
    QfbookmarkUIUtils.clean_up(Mapping.popup)
  end)
end

-- ╓─────────────────────────────────────────────────────────────────────────────╖
-- ║                                    MARK                                     ║
-- ╙─────────────────────────────────────────────────────────────────────────────╜

Mapping.mark = {}

---@param direction integer
---@param amount? integer
function Mapping.mark.scroll_preview_window(direction, amount)
  if not Mapping.popup.preview.win or not vim.api.nvim_win_is_valid(Mapping.popup.preview.win) then
    QfbookmarkUIUtils.warn "`win` previewer is invalid!"
    return
  end

  amount = amount or 2
  local next_or = amount .. (direction * 2 > 0 and "j" or "k")

  vim.api.nvim_win_call(Mapping.popup.preview.win, function()
    vim.cmd("normal! " .. next_or)
  end)
end

-- Navigate by entry using entry_start_line lookup
function Mapping.mark.nav_entry(direction)
  local cur = vim.api.nvim_win_get_cursor(0)[1]
  local total = vim.api.nvim_buf_line_count(0)

  if not Mapping.entry_start_line or vim.tbl_isempty(Mapping.entry_start_line) then
    return
  end

  local entry_starts = {}
  for _, ln in pairs(Mapping.entry_start_line) do
    entry_starts[#entry_starts + 1] = ln
  end
  table.sort(entry_starts)

  if #entry_starts == 0 then
    return
  end

  local cur_entry_pos = 1
  for i, ln in ipairs(entry_starts) do
    if ln <= cur then
      cur_entry_pos = i
    end
  end

  local next_pos = math.max(1, math.min(cur_entry_pos + direction, #entry_starts))
  local target = entry_starts[next_pos]
  if not target or target < 1 or target > total then
    return
  end

  vim.api.nvim_win_set_cursor(0, { target, 0 })
end

local renew_preview = true

function Mapping.mark.renew_preview()
  if renew_preview then
    return
  end
  renew_preview = true

  QfbookmarkUIUtils.close_win { Mapping.popup.preview.win }

  local editor = QfbookmarkUIUtils.get_editor_size()
  local height = editor.height
  Mapping.wincfg.height = height - QfbookmarkUIUtils.PADDING_PREVIEW
  Mapping.wincfg.width = math.ceil(editor.width / 4)

  local buf_preview, win_preview = QfbookmarkUIPopup.mark_preview(Mapping.wincfg, Mapping.wincfg.width, height)
  if not win_preview or not buf_preview then
    return
  end

  Mapping.popup.preview.win = win_preview
  Mapping.popup.preview.buf = buf_preview

  QfbookmarkUIPopup.setup_mark_preview_contents(Mapping.opts_popup, Mapping.popup.buf, win_preview, buf_preview)
end

---@param is_prev? boolean
function Mapping.mark.move_item_to(is_prev)
  is_prev = is_prev or false

  local is_let = false

  if QfbookmarkUtils.is_buf_readonly(Mapping.buf) then
    vim.api.nvim_set_option_value("modifiable", true, { buf = Mapping.buf })
    vim.api.nvim_set_option_value("readonly", false, { buf = Mapping.buf })
    is_let = true
  end

  local function restore_readonly()
    if is_let then
      vim.api.nvim_set_option_value("modifiable", false, { buf = Mapping.buf })
      vim.api.nvim_set_option_value("readonly", true, { buf = Mapping.buf })
    end
  end

  local row = vim.api.nvim_win_get_cursor(0)[1]
  local line_count = vim.api.nvim_buf_line_count(Mapping.buf)
  local winnr = vim.api.nvim_get_current_win()

  local entry_starts = {}
  for _, ln in pairs(Mapping.entry_start_line) do
    entry_starts[#entry_starts + 1] = ln
  end
  table.sort(entry_starts)

  if #entry_starts == 0 then
    restore_readonly()
    return
  end

  local cur_pos = 1
  for i, ln in ipairs(entry_starts) do
    if ln <= row then
      cur_pos = i
    end
  end

  local can_move_up = cur_pos > 1
  local can_move_down = cur_pos < #entry_starts

  if is_prev and not can_move_up then
    restore_readonly()
    return
  end
  if not is_prev and not can_move_down then
    restore_readonly()
    return
  end

  local cur_start = entry_starts[cur_pos]
  local cur_finish = (entry_starts[cur_pos + 1] or (line_count + 1)) - 1

  local tgt_pos = is_prev and (cur_pos - 1) or (cur_pos + 1)
  local tgt_start = entry_starts[tgt_pos]
  local tgt_finish = (entry_starts[tgt_pos + 1] or (line_count + 1)) - 1

  -- flash-highlight target entry
  local hl_group = Config.window.mark and Config.window.mark.hl or "Visual"
  local hl_lines = {}
  for ln = tgt_start, tgt_finish do
    hl_lines[#hl_lines + 1] = { ln }
  end
  local matchid = vim.fn.matchaddpos(hl_group, hl_lines, 10, -1, { window = winnr })

  if not is_prev then
    vim.cmd(string.format("%d,%dmove %d", cur_start, cur_finish, tgt_finish))
  else
    vim.cmd(string.format("%d,%dmove %d", cur_start, cur_finish, tgt_start - 1))
  end

  -- rebuild both harpoon_map and entry_start_line from actual buffer content
  local QfbookmarkUI = require "qfbookmark.ui.view"
  if QfbookmarkUI.rebuild_mark_maps then
    QfbookmarkUI.rebuild_mark_maps()
  end

  -- move cursor to the header of the entry we just moved
  local new_entry_starts = {}
  for _, ln in pairs(Mapping.entry_start_line) do
    new_entry_starts[#new_entry_starts + 1] = ln
  end
  table.sort(new_entry_starts)
  local new_pos = is_prev and (cur_pos - 1) or (cur_pos + 1)
  local new_header = new_entry_starts[new_pos]
  if new_header then
    vim.api.nvim_win_set_cursor(0, { new_header, 0 })
  end

  vim.defer_fn(function()
    restore_readonly()
    pcall(vim.fn.matchdelete, matchid, winnr)
    vim.cmd "redraw"
  end, 400)
end

-- ╓─────────────────────────────────────────────────────────────────────────────╖
-- ║                                   BUFFER                                    ║
-- ╙─────────────────────────────────────────────────────────────────────────────╜

Mapping.buffer = {}

function Mapping.buffer.item_del()
  local cur_line_nr = vim.api.nvim_win_get_cursor(0)[1]
  ---@type QFBufferItem
  local hval = Mapping.harpoon_map[cur_line_nr]
  if hval then
    local target_buf = hval.bufnr
    if vim.api.nvim_buf_is_valid(target_buf) then
      QfbookmarkUtils.buf_del(target_buf)
      Mapping.press_normal_key "dd"

      -- optional: refresh?
      vim.cmd "redraw"
    end
  end
end

local function set_vim_keymaps(_keys)
  if type(_keys) ~= "table" then
    QfbookmarkUIUtils.warn "`_keys` must a table!"
    return
  end

  for i, x in pairs(_keys) do
    vim.keymap.set(x.mode, i, x.fun, { buffer = Mapping.buf, nowait = true })
  end
end

-- ├──────────────────────────────────┤ API ├───────────────────────────────┤

---@param opts_popup QfBookUiPopupCfg
---@param buf integer
---@param cb? function
function M.build_keymaps(opts_popup, buf, cb)
  cb = cb or nil

  if not opts_popup.popup then
    QfbookmarkUIUtils.warn "Field `opts_popup.popup` is empty or nil!"
    return
  end

  Mapping.opts_popup = opts_popup
  Mapping.popup = opts_popup.popup
  Mapping.popup.preview = opts_popup.popup.preview and opts_popup.popup.preview or nil
  Mapping.contents = opts_popup.contents
  Mapping.wincfg = opts_popup.win_opts.wincfg
  Mapping.entry_start_line = opts_popup.entry_start_line and opts_popup.entry_start_line or {}
  Mapping.harpoon_map = opts_popup.content_map
  Mapping.is_harpoon = opts_popup.is_harpoon and opts_popup.is_harpoon or false
  Mapping.is_buffers = opts_popup.is_buffers and opts_popup.is_buffers or false
  Mapping.cb = cb
  Mapping.buf = buf

  local _keys = {
    ["<CR>"] = {
      mode = { "n", "i" },
      fun = function()
        if Mapping.is_buffers or Mapping.is_harpoon then
          Mapping.setup_open_key "default"
          Mapping.exit_close()
        else
          Mapping.save.save_input()
        end
      end,
    },
    ["o"] = {
      mode = "n",
      fun = function()
        Mapping.setup_open_key "default"
      end,
    },
    ["q"] = {
      mode = "n",
      fun = Mapping.exit_close,
    },
    ["<Esc>"] = {
      mode = { "n", "i" },
      fun = Mapping.exit_close,
    },
    ["<C-c>"] = {
      mode = "n",
      fun = Mapping.exit_close,
    },
    ["<C-q>"] = {
      mode = "n",
      fun = Mapping.exit_close,
    },
    ["<C-i>"] = {
      mode = "n",
      fun = Mapping.exit_close,
    },
    ["<C-o>"] = {
      mode = "n",
      fun = Mapping.exit_close,
    },
  }

  local nav_keys = {

    -- +-----------------------------------------------------------------------------+
    -- |                                 NAVIGATION                                  |
    -- +-----------------------------------------------------------------------------+

    ["<c-p>"] = {
      mode = "n",
      fun = function()
        Mapping.press_normal_key("up", true)
      end,
    },
    ["<c-k>"] = {
      mode = "n",
      fun = function()
        Mapping.press_normal_key("up", true)
      end,
    },
    ["<c-n>"] = {
      mode = "n",
      fun = function()
        Mapping.press_normal_key("down", true)
      end,
    },
    ["<c-j>"] = {
      mode = "n",
      fun = function()
        Mapping.press_normal_key("down", true)
      end,
    },

    -- +-----------------------------------------------------------------------------+
    -- |                                  MODE OPEN                                  |
    -- +-----------------------------------------------------------------------------+

    ["<c-s>"] = {
      mode = "n",
      fun = function()
        Mapping.setup_open_key "split"
      end,
    },
    ["<c-v>"] = {
      mode = "n",
      fun = function()
        Mapping.setup_open_key "vsplit"
      end,
    },
    ["<c-t>"] = {
      mode = "n",
      fun = function()
        Mapping.setup_open_key "tabnew"
      end,
    },
  }

  for nav_key, nav_val in pairs(nav_keys) do
    if not _keys[nav_key] then
      _keys[nav_key] = nav_val
    end
  end
  return _keys
end

---@param opts_popup QfBookUiPopupCfg
---@param buf integer
function M.setup_keymap_mark(opts_popup, buf, cb)
  opts_popup.is_buffers = false
  opts_popup.is_harpoon = true

  local _keys = M.build_keymaps(opts_popup, buf, cb)

  -- stylua: ignore start
  renew_preview = false -- to toggle renew preview
  _keys["<c-r>"] = { mode = "n", fun = function()  Mapping.mark.renew_preview() end }

  _keys["<c-n>"] = { mode = "n", fun = function() Mapping.mark.nav_entry(1) end }
  _keys["<c-p>"] = { mode = "n", fun = function() Mapping.mark.nav_entry(-1) end }

  _keys["j"] = { mode = "n", fun = function() Mapping.mark.nav_entry(1) end }
  _keys["k"] = { mode = "n", fun = function() Mapping.mark.nav_entry(-1) end }
  _keys["<c-k>"] = { mode = "n", fun = function() Mapping.mark.nav_entry(-1) end }
  _keys["<c-j>"] = { mode = "n", fun = function() Mapping.mark.nav_entry(1) end }
  -- stylua: ignore end

  _keys[Config.window.mark and Config.window.mark.keymap.move_down or "<a-n>"] = {
    mode = "n",
    fun = function()
      Mapping.mark.move_item_to()
    end,
  }
  _keys[Config.window.mark and Config.window.mark.keymap.move_up or "<a-p>"] = {
    mode = "n",
    fun = function()
      Mapping.mark.move_item_to(true)
    end,
  }

  _keys["dd"] = {
    mode = "n",
    fun = function()
      local is_let = false
      -- delete both lines of the entry (header + detail) at once
      if QfbookmarkUtils.is_buf_readonly(Mapping.buf) then
        vim.api.nvim_set_option_value("modifiable", true, { buf = Mapping.buf })
        vim.api.nvim_set_option_value("readonly", false, { buf = Mapping.buf })
        is_let = true
      end
      local cur = vim.api.nvim_win_get_cursor(0)[1]
      local total = vim.api.nvim_buf_line_count(Mapping.buf)

      -- find the header line of the current entry
      local entry_starts = {}
      for _, ln in pairs(Mapping.entry_start_line) do
        entry_starts[#entry_starts + 1] = ln
      end
      table.sort(entry_starts)

      local header_ln = entry_starts[1] or 1
      local next_ln = total + 1
      for i, ln in ipairs(entry_starts) do
        if ln <= cur then
          header_ln = ln
          next_ln = entry_starts[i + 1] or (total + 1)
        end
      end

      -- delete from header_ln to next entry's header - 1 (0-based end is exclusive)
      vim.api.nvim_buf_set_lines(buf, header_ln - 1, next_ln - 1, false, {})

      if is_let then
        vim.api.nvim_set_option_value("modifiable", false, { buf = Mapping.buf })
        vim.api.nvim_set_option_value("readonly", true, { buf = Mapping.buf })
      end
    end,
  }

  _keys["<c-u>"] = {
    mode = "n",
    fun = function()
      Mapping.mark.scroll_preview_window(-1)
    end,
  }
  _keys["<c-d>"] = {
    mode = "n",
    fun = function()
      Mapping.mark.scroll_preview_window(1)
    end,
  }
  _keys["<c-b>"] = {
    mode = "n",
    fun = function()
      Mapping.mark.scroll_preview_window(-1, 10)
    end,
  }

  _keys["<c-f>"] = {
    mode = "n",
    fun = function()
      Mapping.mark.scroll_preview_window(1, 10)
    end,
  }

  set_vim_keymaps(_keys)
end

---@param opts_popup QfBookUiPopupCfg
---@param buf integer
function M.setup_keymap_buffers(opts_popup, buf)
  opts_popup.is_buffers = true
  opts_popup.is_harpoon = false
  local _keys = M.build_keymaps(opts_popup, buf)

  _keys["gp"] = {
    mode = "n",
    fun = function()
      Mapping.press_normal_key("up", true)
    end,
  }
  _keys["gn"] = {
    mode = "n",
    fun = function()
      Mapping.press_normal_key("down", true)
    end,
  }

  _keys["dd"] = {
    mode = "n",
    fun = Mapping.buffer.item_del,
  }

  _keys["<c-d>"] = nil
  _keys["<c-u>"] = nil

  set_vim_keymaps(_keys)
end

---@param opts_popup QfBookUiPopupCfg
---@param buf integer
---@param cb function
function M.setup_keymap_save_input(opts_popup, buf, cb)
  opts_popup.is_buffers = false
  opts_popup.is_harpoon = false
  local _keys = M.build_keymaps(opts_popup, buf, cb)

  _keys["<c-d>"] = nil
  _keys["<c-u>"] = nil

  set_vim_keymaps(_keys)
end

---@param opts_popup QfBookUiPopupCfg
---@param buf integer
function M.setup_keymap_note(opts_popup, buf)
  opts_popup.is_buffers = false
  opts_popup.is_harpoon = false
  local _keys = M.build_keymaps(opts_popup, buf)

  _keys["<c-d>"] = nil
  _keys["<c-u>"] = nil

  set_vim_keymaps(_keys)
end

return M
