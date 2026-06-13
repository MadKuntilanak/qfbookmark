local Config = require("qfbookmark.config").defaults

local QfbookmarkUIUtils = require "qfbookmark.ui.utils"
local QfbookmarkUtils = require "qfbookmark.utils"
local QfbookmarkNav = require "qfbookmark.nav"
local QfbookmarkUIPopup = require "qfbookmark.ui.popup"

local M = {}

local Mapping = {}

local get_hval = function(content_map, cur_line_nr)
  local hval
  for _, x in pairs(content_map) do
    if x.start_line == cur_line_nr then
      hval = x.hval
    end
  end
  return hval
end

local update_title_main_win = function(total, selected)
  total = total or #Mapping.content_map
  local sel_count = vim.tbl_count(selected)
  local cfg = vim.api.nvim_win_get_config(Mapping.popup.win)

  local count_str = sel_count > 0 and string.format("QFMarks (%d) · %d selected", total, sel_count)
    or string.format("QFMarks (%d)", total)
  cfg.title = QfbookmarkUIUtils.format_title("🔗 " .. count_str)
  vim.api.nvim_win_set_config(Mapping.popup.win, cfg)
end

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
    QfbookmarkUIUtils.close_win { Mapping.popup.win, Mapping.popup.preview and Mapping.popup.preview.win or nil }

    vim.schedule(function()
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", true)

      local out_lines = {}

      for _, e in ipairs(Mapping.content_map or {}) do
        if e.hval then
          out_lines[#out_lines + 1] = e.hval
        end
      end

      if Mapping.cb then
        Mapping.cb(out_lines)
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
      local entry = QfbookmarkUIUtils.get_entry_at_line(Mapping.content_map, cur_line_nr)

      if entry and entry.mark then
        local mark = entry.mark

        QfbookmarkNav.jump_to {
          filename = mark.filename,
          col = mark.col,
          line = mark.line,
          mode_open = open_mode,
        }
      end
    end

    if Mapping.is_buffers then
      ---@type QFBookBufferItem
      local entry = QfbookmarkUIUtils.get_entry_at_line(Mapping.content_map, cur_line_nr)
      local hval = entry and entry["hval"]
      if hval then
        QfbookmarkNav.jump_to {
          filename = hval.info.name,
          col = hval.info.col,
          line = hval.info.lnum,
          mode_open = open_mode,
        }
      end
    end

    if Mapping.is_mark_annotation then
      local raw_lines = vim.api.nvim_buf_get_lines(Mapping.buf, 0, -1, false)
      if Mapping.cb then
        Mapping.cb(raw_lines)
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

function Mapping.mark.nav_entry(direction)
  local cur = vim.api.nvim_win_get_cursor(0)[1]

  local entries = Mapping.content_map
  if not entries or #entries == 0 then
    return
  end

  local cur_idx = 1
  for i, e in ipairs(entries) do
    if e.start_line and e.start_line <= cur then
      cur_idx = i
    end
  end

  local next_idx = math.max(1, math.min(cur_idx + direction, #entries))
  local target = entries[next_idx]

  if not target or not target.start_line then
    return
  end

  -- Safety clamp
  local line_count = vim.api.nvim_buf_line_count(0)
  local target_line = math.max(1, math.min(target.start_line, line_count))

  vim.api.nvim_win_set_cursor(0, { target_line, 0 })
end

local mark_preview_fullscreen = false
local mark_preview_wincfg_orig = nil

local function save_cfg_win_mark_preview(wincfg)
  return {
    main_wincfg = wincfg,
    height = wincfg.height,
    width = wincfg.width,
    col = wincfg.col,
  }
end

function Mapping.mark.full_screen_preview()
  local is_full_screen = mark_preview_fullscreen

  local height
  if not is_full_screen then
    mark_preview_fullscreen = true

    if not mark_preview_wincfg_orig then
      mark_preview_wincfg_orig = save_cfg_win_mark_preview(Mapping.wincfg)
    end

    local editor = QfbookmarkUIUtils.get_editor_size()
    height = editor.height

    Mapping.wincfg.height = height - QfbookmarkUIUtils.PADDING_PREVIEW
    Mapping.wincfg.width = math.ceil(editor.width / 4)

    local __col = Mapping.opts_popup.popup.preview.wincfg.col - Mapping.wincfg.width - 2
    Mapping.wincfg.col = Config.window.mark.anchor == "NW" and __col or Mapping.wincfg.col
  else
    mark_preview_fullscreen = false

    if mark_preview_wincfg_orig then
      Mapping.wincfg = mark_preview_wincfg_orig.main_wincfg
      Mapping.wincfg.height = mark_preview_wincfg_orig.height
      Mapping.wincfg.width = mark_preview_wincfg_orig.width
      Mapping.wincfg.col = mark_preview_wincfg_orig.col

      height = Mapping.opts_popup.popup.preview.wincfg.height

      mark_preview_wincfg_orig = nil
    end
  end

  QfbookmarkUIUtils.close_win { Mapping.popup.preview.win }

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
  local buf = Mapping.buf
  local row = vim.api.nvim_win_get_cursor(0)[1]

  local entries = Mapping.content_map
  if not entries or #entries == 0 then
    return
  end

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

  -- Find current index
  local cur_idx = 1
  for i, e in ipairs(entries) do
    if e.start_line and e.start_line <= row then
      cur_idx = i
    end
  end

  local target_idx = is_prev and (cur_idx - 1) or (cur_idx + 1)
  if not entries[target_idx] then
    return
  end

  local target = Mapping.content_map[target_idx]

  local winnr = vim.api.nvim_get_current_win()

  local tgt_start = target.start_line
  local tgt_finish = tgt_start + target.line_count - 1
  local hl_group = "QFBookmarkEntrySelectTo"

  local hl_lines = {}
  for ln = tgt_start, tgt_finish do
    table.insert(hl_lines, { ln })
  end

  local matchid = vim.fn.matchaddpos(hl_group, hl_lines, 10, -1, { window = vim.api.nvim_get_current_win() })

  -- Swap
  entries[cur_idx], entries[target_idx] = entries[target_idx], entries[cur_idx]

  -- Rebuild buffer (from data ONLY!)
  local lines = {}

  for i, e in ipairs(entries) do
    local m = e.mark
    local symbol = QfbookmarkUIUtils.resolve_fn_name(m)

    local l1, l2, l3 = QfbookmarkUIUtils.build_entry_lines(i, m, Mapping.wincfg.width, symbol)

    table.insert(lines, l1)
    table.insert(lines, l2)
    if l3 then
      table.insert(lines, l3)
    end

    -- Update start_line mapping
    e.start_line = #lines - (l3 and 2 or 1)
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  -- Move cursor to new position
  local new_entry = entries[target_idx]
  if new_entry and new_entry.start_line then
    vim.api.nvim_win_set_cursor(0, { new_entry.start_line, 0 })
  end

  -- Update cursorline manually once
  vim.defer_fn(function()
    restore_readonly()
    pcall(vim.fn.matchdelete, matchid, winnr)
    vim.cmd "redraw"
  end, 400)
end

function Mapping.mark.toggle_selection()
  local cur_line_nr = vim.api.nvim_win_get_cursor(0)[1]
  local entries = QfbookmarkUIUtils.get_entry_at_line(Mapping.content_map, cur_line_nr)

  -- If the cursor is not on an entry, search upward for the nearest header.
  if not entries then
    for ln = cur_line_nr, 1, -1 do
      entries = get_hval(Mapping.content_map, ln)
      if entries then
        break
      end
    end
  end

  if not entries then
    return
  end

  if Mapping.selected[entries.hval] then
    Mapping.selected[entries.hval] = nil
  else
    Mapping.selected[entries.hval] = true
  end

  -- Rebuild checkbox extmarks + line hl
  local QfbookmarkMarkVisual = require "qfbookmark.visual"
  Mapping.opts_popup.active = entries.hval
  QfbookmarkMarkVisual.apply_entry_highlights(
    Mapping.buf,
    Mapping.opts_popup.content_map,
    Mapping.selected,
    Mapping.opts_popup.active
  )

  -- Update title count
  local total = #Mapping.content_map
  update_title_main_win(total, Mapping.selected)
end

function Mapping.mark.select_bookmark_master()
  local path_qf = Config.save_dir
  local Path = require "qfbookmark.path"
  local PUtils = require "qfbookmark.path.utils"

  if not path_qf or not PUtils.is_dir(path_qf) then
    QfbookmarkUtils.warn "something went wrong"
    return
  end

  local prefix = "qfmark"

  local cmd = {
    "fd",
    -- ".",
    prefix,
    -- vim.fn.shellescape(path_qf),
    path_qf,
    "-d",
    "2",
    "-t",
    "f",
    "-e",
    "lua",
  }

  local files = vim.fn.systemlist(cmd)

  local qf_master = {}
  local select_files = {}

  local reform = function(path, is_current)
    is_current = is_current or false

    local basename = PUtils.basename(path)

    local parent = vim.fn.fnamemodify(path, ":h") -- /path/to/the
    local dir = vim.fn.fnamemodify(parent, ":t") -- the

    local dir_master = vim.split(dir, "-")
    local name_project = dir_master[1]
    local hash_project = dir_master[2]
    local branch_name = ""
    local shorten = QfbookmarkUIUtils.shorten_text(hash_project, 20)

    local text = is_current and "current" or name_project .. "-" .. shorten
    return {
      orig = path,
      dir = dir,
      basename = basename,
      project = name_project,
      branch = branch_name,
      text = text,
    }
  end

  local path_git_cwd = Path.get_target_path_with_gitcwd(false)

  --- Create table for current mark project first
  local current_mark = reform(path_git_cwd, true)
  -- table.insert(qf_master, current_mark)
  qf_master[current_mark.text] = current_mark
  table.insert(select_files, "current")

  for _, f in ipairs(files) do
    local other_mark = reform(f)

    -- Do not include current project
    if other_mark.orig ~= current_mark.orig then
      -- qf_master[#qf_master + 1] = other_mark
      qf_master[other_mark.text] = other_mark
      select_files[#select_files + 1] = other_mark.text
    end
  end

  local picker = require "qfbookmark.pickers"
  picker.pick_master_bookmark(Config, select_files, qf_master)
end

--- Get list of selected mark entries (ordered by entry_start_line)
function Mapping.mark.get_selected_marks()
  local sel = {}
  for _, entry in pairs(Mapping.content_map) do
    if Mapping.selected[entry.hval] then
      sel[#sel + 1] = { start_line = entry.start_line, mark = entry.mark }
    end
  end
  table.sort(sel, function(a, b)
    return a.start_line < b.start_line
  end)

  local result = {}
  for _, v in ipairs(sel) do
    result[#result + 1] = v.mark
  end
  return result
end

function Mapping.mark.deselect_all_marks()
  local sel_marks = Mapping.mark.get_selected_marks()
  if #sel_marks == 0 then
    return
  end

  for _, entry in ipairs(Mapping.content_map) do
    if Mapping.selected[entry.hval] then
      Mapping.selected[entry.hval] = nil
    end
  end
end

-- ╓─────────────────────────────────────────────────────────────────────────────╖
-- ║                                   BUFFER                                    ║
-- ╙─────────────────────────────────────────────────────────────────────────────╜

Mapping.buffer = {}

function Mapping.buffer.item_del()
  local cur_line_nr = vim.api.nvim_win_get_cursor(0)[1]
  ---@type QFBookBufferItem
  local hval = get_hval(Mapping.content_map, cur_line_nr)
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
local setup_mapping_opts = function(opts_popup, buf, cb)
  cb = cb or nil

  Mapping.buf = buf
  Mapping.opts_popup = opts_popup
  Mapping.popup = opts_popup.popup
  Mapping.popup.preview = opts_popup.popup.preview and opts_popup.popup.preview or nil
  Mapping.wincfg = opts_popup.win_opts.wincfg
  Mapping.selected = opts_popup.selected
  Mapping.content_map = opts_popup.content_map
  Mapping.is_harpoon = opts_popup.is_harpoon and opts_popup.is_harpoon or false
  Mapping.is_buffers = opts_popup.is_buffers and opts_popup.is_buffers or false
  Mapping.is_mark_annotation = opts_popup.is_mark_annotation and opts_popup.is_mark_annotation or false
  Mapping.is_note = opts_popup.is_note and opts_popup.is_note or false

  Mapping.cb = cb

  --- Clean up
  vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave" }, {
    buffer = Mapping.buf,
    callback = function()
      vim.schedule(function()
        QfbookmarkUIUtils.close_win { Mapping.popup.win, Mapping.popup.preview and Mapping.popup.preview.win or nil }
        QfbookmarkUIUtils.clean_up(Mapping.popup)
      end)
    end,
  })
end

---@param opts_popup QfBookUiPopupCfg
---@param buf integer
---@param cb? function
function M.build_keymaps(opts_popup, buf, cb)
  cb = cb or nil

  if not opts_popup.popup then
    QfbookmarkUIUtils.warn "Field `opts_popup.popup` is empty or nil!"
    return
  end

  setup_mapping_opts(opts_popup, buf, cb)

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
      mode = { "n", "i" },
      fun = Mapping.exit_close,
    },
    ["<Esc>"] = {
      mode = { "n", "i" },
      fun = Mapping.exit_close,
    },
    ["<C-c>"] = {
      mode = { "n", "i" },
      fun = Mapping.exit_close,
    },
    ["<C-q>"] = {
      mode = { "n", "i" },
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
  opts_popup.is_note = false
  opts_popup.is_mark_annotation = false
  opts_popup.is_harpoon = true

  local _keys = M.build_keymaps(opts_popup, buf, cb)

  -- stylua: ignore start
  mark_preview_fullscreen = false -- toggle resize preview win
  _keys[Config.window.mark and Config.window.mark.keymap.zoom or "<C-r>"] = { mode = "n", fun = function()  Mapping.mark.full_screen_preview() end }

  _keys["<c-n>"] = { mode = "n", fun = function() Mapping.mark.nav_entry(1) end }
  _keys["<c-p>"] = { mode = "n", fun = function() Mapping.mark.nav_entry(-1) end }

  _keys["j"] = { mode = "n", fun = function() Mapping.mark.nav_entry(1) end }
  _keys["k"] = { mode = "n", fun = function() Mapping.mark.nav_entry(-1) end }
  _keys["<c-k>"] = { mode = "n", fun = function() Mapping.mark.nav_entry(-1) end }
  _keys["<c-j>"] = { mode = "n", fun = function() Mapping.mark.nav_entry(1) end }
  -- stylua: ignore end

  _keys[Config.window.mark and Config.window.mark.keymap.move_item_down or "<a-n>"] = {
    mode = "n",
    fun = function()
      Mapping.mark.move_item_to()
    end,
  }
  _keys[Config.window.mark and Config.window.mark.keymap.move_item_up or "<a-p>"] = {
    mode = "n",
    fun = function()
      Mapping.mark.move_item_to(true)
    end,
  }

  _keys[Config.window.mark and Config.window.mark.keymap.load_all or "<F4>"] = {
    mode = "n",
    fun = function()
      Mapping.mark.select_bookmark_master()
      Mapping.exit_close()
    end,
  }

  _keys[Config.window.mark and Config.window.mark.keymap.select or "<F4>"] = {
    mode = "n",
    fun = function()
      Mapping.mark.toggle_selection()
    end,
  }

  _keys["s"] = {
    mode = "n",
    fun = function()
      local sel_marks = Mapping.mark.get_selected_marks()
      if #sel_marks == 0 then
        QfbookmarkUtils.warn "No marks selected."
        return
      end

      QfbookmarkUIUtils.close_win { Mapping.popup.win, Mapping.popup.preview and Mapping.popup.preview.win or nil }
      QfbookmarkUIUtils.clean_up(Mapping.popup)

      local results = {
        selected = true,
        data = sel_marks,
      }

      vim.schedule(function()
        if Mapping.cb then
          Mapping.cb(results)
        end
      end)
    end,
  }

  _keys["D"] = {
    mode = "n",
    fun = Mapping.mark.deselect_all_marks,
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

      local function restore_readonly()
        if is_let then
          vim.api.nvim_set_option_value("modifiable", false, { buf = Mapping.buf })
          vim.api.nvim_set_option_value("readonly", true, { buf = Mapping.buf })
        end
      end

      local cur = vim.api.nvim_win_get_cursor(0)[1]

      local entries = Mapping.content_map
      if not entries or #entries == 0 then
        return
      end

      -- find current entry index
      local cur_idx = 1
      for i, e in ipairs(entries) do
        if e.start_line <= cur then
          cur_idx = i
        end
      end

      local target = entries[cur_idx]
      if not target then
        return
      end

      table.remove(entries, cur_idx)

      Mapping.content_map = entries

      -- rebuild again from data
      local lines = {}
      local line_nr = 1

      for i, entry in ipairs(entries) do
        local mark = entry.mark

        local symbol = QfbookmarkUIUtils.resolve_fn_name(mark)
        local l1, l2, l3 = QfbookmarkUIUtils.build_entry_lines(i, mark, Mapping.wincfg.width, symbol)

        entry.start_line = line_nr

        table.insert(lines, l1)
        table.insert(lines, l2)

        line_nr = line_nr + 2

        if l3 then
          table.insert(lines, l3)
          entry.line_count = 3
          line_nr = line_nr + 1
        else
          entry.line_count = 2
        end
      end

      vim.api.nvim_buf_set_lines(Mapping.buf, 0, -1, false, lines)

      local QfbookmarkMarkVisual = require "qfbookmark.visual"
      QfbookmarkMarkVisual.apply_entry_highlights(Mapping.buf, entries, Mapping.selected, Mapping.opts_popup.active)

      -- Update title count
      local total = #entries
      update_title_main_win(total, Mapping.selected)

      vim.defer_fn(function()
        restore_readonly()
        vim.cmd "redraw"
      end, 400)
    end,
  }

  _keys[Config.window.mark and Config.window.mark.keymap.scroll_preview_up or "<C-u>"] = {
    mode = "n",
    fun = function()
      Mapping.mark.scroll_preview_window(-1)
    end,
  }
  _keys[Config.window.mark and Config.window.mark.keymap.scroll_preview_down or "<C-d>"] = {
    mode = "n",
    fun = function()
      Mapping.mark.scroll_preview_window(1)
    end,
  }
  _keys[Config.window.mark and Config.window.mark.keymap.scroll_preview_up_fast or "<C-b>"] = {
    mode = "n",
    fun = function()
      Mapping.mark.scroll_preview_window(-1, 10)
    end,
  }

  _keys[Config.window.mark and Config.window.mark.keymap.scroll_preview_down_fast or "<C-f>"] = {
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
  opts_popup.is_mark_annotation = false
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
  opts_popup.is_mark_annotation = false
  opts_popup.is_note = false
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
  opts_popup.is_mark_annotation = false
  opts_popup.is_note = true

  local _keys = M.build_keymaps(opts_popup, buf)

  _keys["<c-d>"] = nil
  _keys["<c-u>"] = nil

  set_vim_keymaps(_keys)
end

---@param opts_popup QfBookUiPopupCfg
---@param buf integer
---@param cb function
function M.setup_keymap_mark_annotation(opts_popup, buf, cb)
  opts_popup.is_buffers = false
  opts_popup.is_harpoon = false
  opts_popup.is_note = false
  opts_popup.is_mark_annotation = true

  setup_mapping_opts(opts_popup, buf, cb)

  local _keys = {
    ["<C-c>"] = {
      mode = { "n", "i" },
      fun = function()
        Mapping.setup_open_key "default"
        Mapping.exit_close()
      end,
    },

    ["<Esc>"] = {
      mode = { "n", "i" },
      fun = Mapping.exit_close,
    },
    ["<C-q>"] = {
      mode = { "n", "i" },
      fun = Mapping.exit_close,
    },
    ["q"] = {
      mode = "n",
      fun = Mapping.exit_close,
    },
  }
  set_vim_keymaps(_keys)
end

return M
