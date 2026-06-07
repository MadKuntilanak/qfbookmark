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

      -- each entry spans 2 lines; only header lines (odd) carry the " N  " prefix
      -- detail lines (even, leading indent) are skipped
      local out_lines = {}
      for _, raw in ipairs(lines_raw) do
        local idx_str = raw:match "^ (%d+) "
        if idx_str then
          local original_idx = tonumber(idx_str)
          -- harpoon_map is keyed by line_nr; header of entry N is at line_nr (N-1)*2+1
          local ln = (original_idx - 1) * 2 + 1
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

---@param scroll_mode "up" | "down"
function Mapping.mark.scroll_preview_window(scroll_mode)
  if not Mapping.popup.preview.win or not vim.api.nvim_win_is_valid(Mapping.popup.preview.win) then
    QfbookmarkUIUtils.warn "`win` previewer is invalid!"
    return
  end

  local function scroll_down(win)
    vim.api.nvim_win_call(win, function()
      vim.cmd "normal! 2j"
    end)
  end

  local function scroll_up(win)
    vim.api.nvim_win_call(win, function()
      vim.cmd "normal! 2k"
    end)
  end

  if scroll_mode == "up" then
    scroll_up(Mapping.popup.preview.win)
  else
    scroll_down(Mapping.popup.preview.win)
  end
end

-- move by 2 lines at a time to jump between entries (header + detail)
function Mapping.mark.nav_entry(direction)
  local cur = vim.api.nvim_win_get_cursor(0)[1]
  local total = vim.api.nvim_buf_line_count(Mapping.buf)
  -- always land on a header line (odd)
  local header = cur % 2 == 0 and cur - 1 or cur
  local next_header = header + direction * 2
  if next_header < 1 then
    next_header = 1
  end
  if next_header > total then
    next_header = total - (total % 2 == 0 and 1 or 0)
  end
  vim.api.nvim_win_set_cursor(0, { next_header, 0 })
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

  local row = vim.api.nvim_win_get_cursor(0)[1]

  local start = row % 2 == 0 and row - 1 or row
  local finish = start + 1
  local winnr = vim.api.nvim_get_current_win()
  local line_count = vim.api.nvim_buf_line_count(Mapping.buf)

  local can_move_up = start > 1
  local can_move_down = finish < line_count

  -- Disable moving when the cursor is on the first or last entry.
  -- stylua: ignore start
  if is_prev and not can_move_up then return end
  if not is_prev and not can_move_down then return end

  local new_start
  if not is_prev then new_start = start + 2 else new_start = start - 2 end
  -- stylua: ignore end

  -- add highlight with matchaddpos
  local hl_group = Config.window.popup.mark and Config.window.popup.mark.hl or "Visual"
  local matchid = vim.fn.matchaddpos(hl_group, { { new_start }, { new_start + 1 } }, 10, -1, { window = winnr })
  local durationMs = 400

  if not is_prev then
    vim.cmd(string.format("%d,%dmove %d", start, finish, finish + 2))
  else
    vim.cmd(string.format("%d,%dmove %d", start, finish, start - 3))
  end

  vim.defer_fn(function()
    if is_let then
      vim.api.nvim_set_option_value("modifiable", false, { buf = Mapping.buf })
      vim.api.nvim_set_option_value("readonly", true, { buf = Mapping.buf })
    end
    pcall(vim.fn.matchdelete, matchid, winnr)

    -- optional: refresh?
    vim.cmd "redraw"
  end, durationMs)
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
  Mapping.harpoon_map = opts_popup.content_map
  Mapping.is_harpoon = opts_popup.is_harpoon and true or false
  Mapping.is_buffers = opts_popup.is_buffers and true or false
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

    ["<c-y>"] = {
      mode = "n",
      fun = function()
        Mapping.setup_open_key "buffer"
      end,
    },
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

  _keys[Config.window.popup.mark and Config.window.popup.mark.keymap.move_down or "<a-n>"] = {
    mode = "n",
    fun = function()
      Mapping.mark.move_item_to()
    end,
  }
  _keys[Config.window.popup.mark and Config.window.popup.mark.keymap.move_up or "<a-p>"] = {
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
      local total = vim.api.nvim_buf_line_count(buf)
      -- if cursor is on the detail line (even), step up to its header (odd)
      local header_line = cur % 2 == 0 and cur - 1 or cur
      -- remove header + detail; guard against last line having no pair
      if header_line + 1 <= total then
        vim.api.nvim_buf_set_lines(buf, header_line - 1, header_line + 1, false, {})
      else
        vim.api.nvim_buf_set_lines(buf, header_line - 1, header_line, false, {})
      end

      if is_let then
        vim.api.nvim_set_option_value("modifiable", false, { buf = Mapping.buf })
        vim.api.nvim_set_option_value("readonly", true, { buf = Mapping.buf })
      end
    end,
  }

  _keys["<c-u>"] = {
    mode = "n",
    fun = function()
      Mapping.mark.scroll_preview_window "up"
    end,
  }
  _keys["<c-d>"] = {
    mode = "n",
    fun = function()
      Mapping.mark.scroll_preview_window "down"
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

return M
