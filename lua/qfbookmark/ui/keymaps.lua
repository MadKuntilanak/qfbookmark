local Config = require("qfbookmark.config").defaults

local QfbookmarkUIUtils = require "qfbookmark.ui.utils"
local QfbookmarkUtils = require "qfbookmark.utils"
local QfbookmarkKeymapUtils = require "qfbookmark.keymaps.utils"

local QfbookmarkNav = require "qfbookmark.nav"
local QfbookmarkUIPopup = require "qfbookmark.ui.popup"

local M = {}

local Mapping = {}

Mapping.last_position = {
  mark = nil,
  buffer = nil,
}

local get_hval = function(content_map, cur_line_nr)
  local hval
  for _, x in pairs(content_map) do
    if x.start_line == cur_line_nr then
      hval = x.hval
    end
  end
  return hval
end

local update_last_position_cursor = function(provider)
  local set_cursor_position

  if Mapping.last_position[provider] then
    set_cursor_position = Mapping.last_position[provider]
  else
    set_cursor_position = vim.api.nvim_buf_get_mark(0, '"')
  end

  if set_cursor_position then
    local line_count = vim.api.nvim_buf_line_count(0)
    if set_cursor_position and set_cursor_position[1] then
      if set_cursor_position[1] > 0 and set_cursor_position[1] <= line_count then
        pcall(vim.api.nvim_win_set_cursor, 0, set_cursor_position)
      end
    end
  end
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
    if Mapping.popup.win and vim.api.nvim_win_is_valid(Mapping.popup.win) then
      local row = vim.api.nvim_win_get_cursor(Mapping.popup.win)[1]
      local col = vim.api.nvim_win_get_cursor(Mapping.popup.win)[2]
      Mapping.last_position.buffer = { row, col }
    end

    QfbookmarkUIUtils.close_win { Mapping.popup.win }
    QfbookmarkUIUtils.clean_up(Mapping.popup)
  elseif Mapping.is_harpoon then
    if Mapping.popup.win and vim.api.nvim_win_is_valid(Mapping.popup.win) then
      local row = vim.api.nvim_win_get_cursor(Mapping.popup.win)[1]
      local col = vim.api.nvim_win_get_cursor(Mapping.popup.win)[2]
      Mapping.last_position.mark = { row, col }
    end

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
---@param jump_to_n? integer
function Mapping.setup_open_key(open_mode, jump_to_n)
  if Mapping.popup.win and vim.api.nvim_win_is_valid(Mapping.popup.win) then
    local row = vim.api.nvim_win_get_cursor(Mapping.popup.win)[1]
    local col = vim.api.nvim_win_get_cursor(Mapping.popup.win)[2]
    if Mapping.is_harpoon then
      Mapping.last_position.mark = { row, col }
    elseif Mapping.is_buffers then
      Mapping.last_position.buffer = { row, col }
    end
  end

  local cur_line_nr = jump_to_n or vim.api.nvim_win_get_cursor(0)[1]
  QfbookmarkUIUtils.close_win { Mapping.popup.win, Mapping.popup.preview and Mapping.popup.preview.win or nil }

  vim.schedule(function()
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", true)

    if Mapping.is_harpoon then
      local selected_marks = Mapping.mark.get_selected_marks()
      if #selected_marks > 0 and open_mode ~= "default" then
        for _, m in pairs(selected_marks) do
          QfbookmarkNav.jump_to {
            filename = m.filename,
            col = m.col,
            line = m.line,
            mode_open = open_mode,
            win_resized = Mapping.is_harpoon and Config.window.mark.actions.win_resized or false,
          }
        end
        return
      end

      local entry = QfbookmarkUIUtils.get_entry_at_line(Mapping.content_map, cur_line_nr)
      if entry and entry.mark then
        local mark = entry.mark

        QfbookmarkNav.jump_to {
          filename = mark.filename,
          col = mark.col,
          line = mark.line,
          mode_open = open_mode,
          win_resized = Mapping.is_harpoon and Config.window.mark.actions.win_resized or false,
        }
      end
    end

    if Mapping.is_buffers then
      local selected_buffers = Mapping.buffer.get_selected()
      if #selected_buffers > 0 and open_mode ~= "default" then
        for _, hval in pairs(selected_buffers) do
          QfbookmarkNav.jump_to {
            filename = hval.info.name,
            col = hval.info.col,
            line = hval.info.lnum,
            mode_open = open_mode,
            win_resized = Mapping.is_harpoon and Config.window.buffers.actions.win_resized or false,
          }
        end
        return
      end
      ---@type QFBookBufferItem
      local entry = QfbookmarkUIUtils.get_entry_at_line(Mapping.content_map, cur_line_nr)
      local hval = entry and entry["hval"]
      if hval then
        QfbookmarkNav.jump_to {
          filename = hval.info.name,
          col = hval.info.col,
          line = hval.info.lnum,
          mode_open = open_mode,
          win_resized = Mapping.is_buffers and Config.window.buffers.actions.win_resized or false,
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

---@param prefix string
---@param keys QFBookKeys[]
function Mapping.show_help(prefix, keys)
  QfbookmarkUIPopup.show_keymap_helps(prefix, keys)
end

-- ╓─────────────────────────────────────────────────────────────────────────────╖
-- ║                                    SAVE                                     ║
-- ╙─────────────────────────────────────────────────────────────────────────────╜

Mapping.save = {}

function Mapping.save.save_input()
  local lines = vim.api.nvim_buf_get_lines(Mapping.buf, 0, -1, false)
  local input = lines
  QfbookmarkUIUtils.close_win { Mapping.popup.win, Mapping.popup.preview and Mapping.popup.preview.win or nil }

  vim.schedule(function()
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", true)
    if Mapping.on_submit and #input > 0 then
      Mapping.on_submit(input)
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

local is_full_screen = false

function Mapping.mark.full_screen_preview()
  is_full_screen = require("qfbookmark.config").defaults.window.mark.preview_fullscreen

  if is_full_screen then
    is_full_screen = false
  else
    is_full_screen = true
  end

  require("qfbookmark.config").defaults.window.mark.preview_fullscreen = is_full_screen

  QfbookmarkUIUtils.close_win { Mapping.popup.preview.win }

  local buf_preview, win_preview = QfbookmarkUIPopup.mark_preview(
    Mapping.wincfg,
    Mapping.wincfg.width,
    Mapping.wincfg.height,
    { fullscreen = is_full_screen }
  )
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

  -- Swap `inserted_at` too
  local max_inserted = #entries
  for i, e in ipairs(entries) do
    local m = e.mark
    m.inserted_at = max_inserted - i + 1
  end

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

  local modifiable = vim.bo[Mapping.buf].modifiable
  vim.bo[Mapping.buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[Mapping.buf].modifiable = modifiable

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
  QfbookmarkUIUtils.update_title_win_popup(Mapping.popup.win, total, Mapping.selected)
end

function Mapping.mark.select_and_load_qfmasters()
  local path_qf = Config.save_dir
  local Path = require "qfbookmark.path"
  local PUtils = require "qfbookmark.path.utils"

  if not path_qf or not PUtils.is_dir(path_qf) then
    QfbookmarkUtils.warn "something went wrong"
    return
  end

  ---@param path string
  ---@param is_current? boolean
  ---@param padding? integer
  ---@return QFbookMasterOpts
  ---
  local reform = function(path, is_current, padding)
    is_current = is_current or false

    local QfbookmarkPathUtils = require "qfbookmark.path.utils"
    local basename = QfbookmarkPathUtils.basename(path) -- "qfmark_master.lua"

    local parent = vim.fn.fnamemodify(path, ":h") -- /path/to/dotfiles-e76759d5fc3b
    local dir = vim.fn.fnamemodify(parent, ":t") -- "dotfiles-e76759d5fc3b"

    local dir_parts = vim.split(dir, "-")
    local name_project = dir_parts[1] -- "dotfiles"
    local hash_project = dir_parts[2] -- "e76759d5fc3b"

    -- extract branch/tag/commit name from the filename itself:
    --   qfmark_master.lua          → "master"
    --   qfmark_no-branch.lua       → "no-branch"
    --   qfmark_detached-85919cd.lua → "detached-85919cd"
    local branch_name = basename:match "^qfmark_(.+)%.lua$" or ""

    local shorten = QfbookmarkUIUtils.shorten_text(hash_project, 20)

    local text
    if is_current then
      text = "current"
    else
      text =
        string.format("%s-%-" .. tostring(padding - #name_project) .. "s · %s", name_project, shorten, branch_name)
    end

    return {
      orig = path,
      dir = dir,
      basename = basename,
      project = name_project,
      branch = branch_name,
      tag = "",
      text = text,
    }
  end

  local prefix = "qfmark"
  local cmd = {
    "fd",
    -- ".",
    prefix,
    -- vim.fn.shellescape(path_qf),
    path_qf,
    -- "-d",
    -- "2",
    "-t",
    "f",
    "-e",
    "lua",
  }

  local files = vim.fn.systemlist(cmd)

  local qf_master = {}
  local select_files = {}

  local path_git_cwd = Path.get_target_file_path(false)

  --- Create table for current mark project first
  local current_mark = reform(path_git_cwd, true)
  qf_master[current_mark.text] = current_mark
  table.insert(select_files, "current")

  --- Get the maximum padding from the lists
  local get_padding = function()
    local pad = 0
    for _, f in ipairs(files) do
      local parent = vim.fn.fnamemodify(f, ":h") -- /path/to/dotfiles-e76759d5fc3b
      local dir = vim.fn.fnamemodify(parent, ":t") -- "dotfiles-e76759d5fc3b"
      local txt_len = vim.fn.strdisplaywidth(dir)

      if pad < txt_len then
        pad = txt_len
      end
    end

    return pad
  end

  local p = get_padding()

  for _, f in ipairs(files) do
    local other_mark = reform(f, false, p)

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

function Mapping.mark.jump_to_mark_n()
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

---@param is_all? boolean
local function mark_del_item(is_all)
  is_all = is_all or false

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

  local selected = Mapping.mark.get_selected_marks()

  local cur = vim.api.nvim_win_get_cursor(Mapping.popup.win)[1]

  local entries = Mapping.content_map
  if not entries or #entries == 0 then
    return
  end

  -- Start delete item or all items
  if is_all then
    for _ = 1, #entries do
      local target = entries[1]
      if not target then
        goto continue
      end

      table.remove(entries, 1)
      ::continue::
    end
  elseif #selected > 0 then
    for idx_hval, _ in pairs(Mapping.selected) do
      for i, e in ipairs(entries) do
        if idx_hval == e.hval then
          if entries[i] then
            table.remove(entries, i)

            if Mapping.selected[idx_hval] then
              Mapping.selected[idx_hval] = nil
            end
          end
        end
      end
    end
  else
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
  end

  Mapping.content_map = entries

  -- rebuild again from data
  local lines = {}
  local line_nr = 1

  for i, entry in ipairs(entries) do
    local mark = entry.mark

    local symbol = QfbookmarkUIUtils.resolve_fn_name(mark)
    local l1, l2, l3 = QfbookmarkUIUtils.build_entry_lines(i, mark, Mapping.mark_original_width, symbol)

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

  local modifiable = vim.bo[Mapping.buf].modifiable
  vim.bo[Mapping.buf].modifiable = true
  vim.api.nvim_buf_set_lines(Mapping.buf, 0, -1, false, lines)
  vim.bo[Mapping.buf].modifiable = modifiable

  local QfbookmarkMarkVisual = require "qfbookmark.visual"
  QfbookmarkMarkVisual.apply_entry_highlights(Mapping.buf, entries, Mapping.selected, Mapping.opts_popup.active)

  -- Update title count
  local total = #entries
  QfbookmarkUIUtils.update_title_win_popup(Mapping.popup.win, total, Mapping.selected)

  vim.defer_fn(function()
    restore_readonly()
    vim.cmd "redraw"
  end, 400)
end

function Mapping.mark.delete_item()
  mark_del_item()
end

function Mapping.mark.clear_all_items()
  mark_del_item(true)
end

---@param is_all? boolean
function Mapping.mark.preview_context(is_all)
  is_all = is_all or false
  local selected = Mapping.mark.get_selected_marks()
  local cur = vim.api.nvim_win_get_cursor(Mapping.popup.win)[1]
  local entries = Mapping.content_map
  if not entries or #entries == 0 then
    return
  end

  local get_abc = {}

  -- Start delete item or all items
  if #selected > 0 then
    for idx_hval, _ in pairs(Mapping.selected) do
      for i, e in ipairs(entries) do
        if idx_hval == e.hval then
          if entries[i] then
            get_abc[#get_abc + 1] = entries[i]
          end
        end
      end
    end
  else
    -- find current entry index
    local cur_idx = 1
    for i, e in ipairs(entries) do
      if e.start_line <= cur then
        cur_idx = i
      end
    end

    if entries[cur_idx] then
      get_abc[#get_abc + 1] = entries[cur_idx]
    end
  end

  local QfbookmarkMark = require "qfbookmark.mark"

  ---@type {bufnr: integer, key: integer, category: string, inserted_at: integer}
  local items = {}
  for _, mark in pairs(get_abc) do
    local m = mark.mark
    if m.note and #m.note > 0 then
      for _, ann in ipairs(QfbookmarkMark.list_annotations(m.bufnr, m.key)) do
        table.insert(items, {
          bufnr = m.bufnr,
          key = m.key,
          category = ann.category,
          inserted_at = (m.inserted_at and m.inserted_at < 1e13) and m.inserted_at or 0,
        })
        break
      end
    end
  end

  table.sort(items, function(a, b)
    return (a.inserted_at or 0) > (b.inserted_at or 0)
  end)

  if #items == 0 then
    QfbookmarkUtils.warn "no annotation context found"
    return
  end

  if #items == 1 then
    QfbookmarkMark.preview(items[1].bufnr, items[1].key, { default_template = "ask_ai" })
  else
    QfbookmarkMark.preview(
      items[1].bufnr,
      items[1].key,
      { default_template = "ask_ai", is_multi = true, items = items }
    )
  end
end

-- ╓─────────────────────────────────────────────────────────────────────────────╖
-- ║                                   BUFFER                                    ║
-- ╙─────────────────────────────────────────────────────────────────────────────╜

Mapping.buffer = {}

function Mapping.buffer.item_del()
  local cur_line_nr = vim.api.nvim_win_get_cursor(0)[1]

  local selected_buffers = Mapping.buffer.get_selected()

  ---@type QFBookBufferItem
  local hval = get_hval(Mapping.content_map, cur_line_nr)

  if #selected_buffers > 0 then
    local list = Mapping.buffer_list

    for _, x in pairs(selected_buffers) do
      for idx, entry in ipairs(list) do
        if x.bufnr == entry.bufnr then
          if Mapping.buffer_selected[entry.bufnr] then
            Mapping.buffer_selected[entry.bufnr] = nil
          end

          if list[idx] then
            table.remove(list, idx)
          end

          if QfbookmarkUtils.is_valid(entry.bufnr) then
            QfbookmarkUtils.buf_del(entry.bufnr)
          end
        end
      end
    end

    Mapping.content_map = list

    -- rebuild data again
    local display_lines = {}
    local __entries = {}

    for idx, buffer in pairs(list) do
      local line, _hval =
        QfbookmarkUIUtils.build_entry_line_buffers(idx, buffer, Mapping.opts_popup.original_popup_buffer_width)
      display_lines[#display_lines + 1] = line

      local start_line = idx

      local entry = {
        id = idx,
        start_line = start_line,
        hval = _hval,
        line_count = 1,
      }

      __entries[idx] = entry
    end

    local modifiable = vim.bo[Mapping.buf].modifiable
    vim.bo[Mapping.buf].modifiable = true
    vim.api.nvim_buf_set_lines(Mapping.buf, 0, -1, false, display_lines)
    vim.bo[Mapping.buf].modifiable = modifiable

    local QfbookmarkMarkVisual = require "qfbookmark.visual"
    QfbookmarkMarkVisual.apply_entry_buffer_highlights(
      Mapping.buf,
      __entries,
      Mapping.buffer_selected,
      Mapping.popup.namespace
    )

    vim.schedule(function()
      vim.cmd "redraw"
    end)
  elseif hval then
    local target_buf = hval.bufnr
    if QfbookmarkUtils.is_valid(target_buf) then
      QfbookmarkUtils.buf_del(target_buf)
      Mapping.press_normal_key "dd"

      -- optional: refresh?
      vim.cmd "redraw"
    end
  end
end

function Mapping.buffer.clear_all_items()
  local buffers = require "qfbookmark.buffers"
  local list = buffers.load_buffers()
  local removed, skipped = 0, 0

  for _, buf in ipairs(list) do
    local bufnr = buf.bufnr
    if bufnr and bufnr ~= Mapping.last_buf and QfbookmarkUtils.is_valid(bufnr) then
      local ok = pcall(vim.api.nvim_buf_delete, bufnr, { force = false })
      if ok then
        removed = removed + 1
      else
        skipped = skipped + 1
      end
    end
  end

  if skipped > 0 then
    QfbookmarkUtils.warn(string.format("Deleted %d buffers, skipped %d (unsaved changes)", removed, skipped))
  else
    QfbookmarkUtils.info(string.format("Deleted %d buffers", removed))
  end

  vim.cmd "redraw"

  Mapping.exit_close()
end

function Mapping.buffer.toggle_selection()
  local cur_line_nr = vim.api.nvim_win_get_cursor(0)[1]

  local list = Mapping.buffer_list -- list of { bufnr, flag, info, ... } sesuai urutan baris
  local entry = list and list[cur_line_nr]
  if not entry then
    return
  end

  local bufnr = entry.bufnr
  if Mapping.buffer_selected[bufnr] then
    Mapping.buffer_selected[bufnr] = nil
  else
    Mapping.buffer_selected[bufnr] = true
  end

  local QfbookmarkMarkVisual = require "qfbookmark.visual"
  QfbookmarkMarkVisual.apply_entry_buffer_highlights(
    Mapping.buf,
    list,
    Mapping.buffer_selected,
    Mapping.popup.namespace
  )

  local total = #list
  QfbookmarkUIUtils.update_title_win_popup(Mapping.popup.win, total, Mapping.buffer_selected)
end

---@return table[]
function Mapping.buffer.get_selected()
  local list = Mapping.buffer_list
  local result = {}
  for _, entry in ipairs(list or {}) do
    if Mapping.buffer_selected[entry.bufnr] then
      result[#result + 1] = entry
    end
  end
  return result
end

function Mapping.buffer.deselect_all_buffers()
  local sel_marks = Mapping.buffer.get_selected()
  if #sel_marks == 0 then
    return
  end

  local list = Mapping.buffer_list

  for _, entry in ipairs(list) do
    if Mapping.buffer_selected[entry.bufnr] then
      Mapping.buffer_selected[entry.bufnr] = nil
    end
  end

  local QfbookmarkMarkVisual = require "qfbookmark.visual"
  QfbookmarkMarkVisual.apply_entry_buffer_highlights(
    Mapping.buf,
    list,
    Mapping.buffer_selected,
    Mapping.popup.namespace
  )
end

-- ├──────────────────────────────────┤ API ├───────────────────────────────┤

function M.get_selected_marks()
  local data = Mapping.content_map

  local sel_marks = Mapping.mark.get_selected_marks()

  if #sel_marks == 0 then
    local cur_line_nr = vim.api.nvim_win_get_cursor(0)[1]
    local entries = QfbookmarkUIUtils.get_entry_at_line(Mapping.content_map, cur_line_nr)

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

    sel_marks = { entries.mark }
  end

  QfbookmarkUIUtils.close_win { Mapping.popup.win, Mapping.popup.preview and Mapping.popup.preview.win or nil }
  QfbookmarkUIUtils.clean_up(Mapping.popup)

  return { selected = sel_marks, data = data }
end

function M.get_selected_buffers()
  local data = Mapping.content_map

  local sel_buffers = Mapping.buffer.get_selected()

  if #sel_buffers == 0 then
    local cur_line_nr = vim.api.nvim_win_get_cursor(0)[1]

    local list = Mapping.buffer_list
    local entry = list and list[cur_line_nr]
    if not entry then
      return
    end

    sel_buffers = { entry }
  end

  QfbookmarkUIUtils.close_win { Mapping.popup.win, Mapping.popup.preview and Mapping.popup.preview.win or nil }
  QfbookmarkUIUtils.clean_up(Mapping.popup)

  return { selected = sel_buffers, data = data }
end

---@param opts_popup QFBookmarkUiPopupCfg
---@param buf integer
---@param cb? function
local setup_popup_options = function(opts_popup, buf, cb)
  cb = cb or nil

  Mapping.buf = buf
  Mapping.popup = opts_popup.popup
  Mapping.opts_popup = opts_popup
  Mapping.mark_original_width = opts_popup.original_popup_mark_width and opts_popup.original_popup_mark_width or nil
  Mapping.popup.preview = opts_popup.popup.preview and opts_popup.popup.preview or nil
  Mapping.selected = opts_popup.selected
  Mapping.buffer_selected = opts_popup.buffer_selected or {}
  Mapping.wincfg = opts_popup.win_opts.wincfg
  Mapping.buffer_list = opts_popup.contents
  Mapping.last_buf = opts_popup.last_buf
  Mapping.on_submit = opts_popup.on_submit and opts_popup.on_submit or {}
  Mapping.on_cancel = opts_popup.on_cancel and opts_popup.on_cancel or {}
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
      if Mapping.is_note then
        return
      end

      QfbookmarkUIUtils.close_win { Mapping.popup.win, Mapping.popup.preview and Mapping.popup.preview.win or nil }
      QfbookmarkUIUtils.clean_up(Mapping.popup)
    end,
  })
end

---@param opts_popup QFBookmarkUiPopupCfg
---@param buf integer
---@param cb? function
---@return QFBookKeys[]
function M.build_keymaps(opts_popup, buf, cb)
  cb = cb or nil

  if not opts_popup.popup then
    QfbookmarkUIUtils.warn "Field `opts_popup.popup` is empty or nil!"
    return {}
  end

  setup_popup_options(opts_popup, buf, cb)

  local keymaps_opts = {
    -- +-----------------------------------------------------------------------------+
    -- |                                    QUIT                                     |
    -- +-----------------------------------------------------------------------------+

    {
      desc = "Qfmark: quit",
      func = function()
        Mapping.exit_close()
      end,
      keys = Config.keymaps.actions and Config.keymaps.actions.quit,
      mode = "n",
      buffer = Mapping.buf,
      from_user = true,
    },

    -- +-----------------------------------------------------------------------------+
    -- |                                  MODE OPEN                                  |
    -- +-----------------------------------------------------------------------------+

    {
      desc = "Qfmark: open",
      func = function()
        Mapping.setup_open_key "default"
        Mapping.exit_close()
      end,
      keys = Config.keymaps.actions and Config.keymaps.actions.default,
      mode = "n",
      buffer = Mapping.buf,
      from_user = true,
    },
    {
      desc = "Qfmark: open in split",
      func = function()
        Mapping.setup_open_key "split"
        Mapping.exit_close()
      end,
      keys = Config.keymaps.actions and Config.keymaps.actions.split,
      mode = "n",
      buffer = Mapping.buf,
      from_user = true,
    },
    {
      desc = "Qfmark: open in vsplit",
      func = function()
        Mapping.setup_open_key "vsplit"
        Mapping.exit_close()
      end,
      keys = Config.keymaps.actions and Config.keymaps.actions.vsplit,
      mode = "n",
      buffer = Mapping.buf,
      from_user = true,
    },
    {
      desc = "Qfmark: open in tab",
      func = function()
        Mapping.setup_open_key "tabnew"
        Mapping.exit_close()
      end,
      keys = Config.keymaps.actions and Config.keymaps.actions.tab,
      mode = "n",
      buffer = Mapping.buf,
      from_user = true,
    },

    -- +-----------------------------------------------------------------------------+
    -- |                                     NAV                                     |
    -- +-----------------------------------------------------------------------------+

    {
      desc = "Qfmark: move up",
      func = function()
        Mapping.press_normal_key("up", true)
      end,
      keys = Config.keymaps and Config.keymaps.actions.up,
      mode = "n",
      buffer = Mapping.buf,
      from_user = true,
    },
    {
      desc = "Qfmark: move down",
      func = function()
        Mapping.press_normal_key("down", true)
      end,
      keys = Config.keymaps and Config.keymaps.actions.down,
      mode = "n",
      buffer = Mapping.buf,
      from_user = true,
    },
  }
  return keymaps_opts
end

---@param opts_popup QFBookmarkUiPopupCfg
---@param buf integer
function M.setup_keymap_mark(opts_popup, buf, cb)
  opts_popup.is_buffers = false
  opts_popup.is_note = false
  opts_popup.is_mark_annotation = false
  opts_popup.is_harpoon = true

  local _keys = M.build_keymaps(opts_popup, buf, cb)

  update_last_position_cursor "mark"

  QfbookmarkKeymapUtils.append_active_keymaps({
    is_set = true,
    keymaps = {

      -- +-----------------------------------------------------------------------------+
      -- |                                   PREVIEW                                   |
      -- +-----------------------------------------------------------------------------+

      {
        desc = "Qfmark: scroll preview up",
        func = function()
          Mapping.mark.scroll_preview_window(-1)
        end,
        keys = Config.keymaps.actions and Config.keymaps.actions.scroll_preview_up,
        mode = "n",
        buffer = Mapping.buf,
        from_user = true,
      },

      {
        desc = "Qfmark: scroll preview down",
        func = function()
          Mapping.mark.scroll_preview_window(1)
        end,
        keys = Config.keymaps.actions and Config.keymaps.actions.scroll_preview_down,
        mode = "n",
        buffer = Mapping.buf,
        from_user = true,
      },

      {
        desc = "Qfmark: scroll preview up (fast)",
        func = function()
          Mapping.mark.scroll_preview_window(-1, 10)
        end,
        keys = Config.keymaps.actions and Config.keymaps.actions.scroll_preview_up_fast,
        mode = "n",
        buffer = Mapping.buf,
        from_user = true,
      },

      {
        desc = "Qfmark: scroll preview down (fast)",
        func = function()
          Mapping.mark.scroll_preview_window(1, 10)
        end,
        keys = Config.keymaps.actions and Config.keymaps.actions.scroll_preview_down_fast,
        mode = "n",
        buffer = Mapping.buf,
        from_user = true,
      },

      -- +-----------------------------------------------------------------------------+
      -- |                                 NAVIGATION                                  |
      -- +-----------------------------------------------------------------------------+

      {
        desc = "Qfmark: move up",
        func = function()
          Mapping.mark.nav_entry(-1)
        end,
        keys = Config.keymaps and Config.keymaps.actions.up,
        mode = "n",
        buffer = Mapping.buf,
        from_user = true,
      },
      {
        desc = "Qfmark: move down",
        func = function()
          Mapping.mark.nav_entry(1)
        end,
        keys = Config.keymaps and Config.keymaps.actions.down,
        mode = "n",
        buffer = Mapping.buf,
        from_user = true,
      },

      -- +-----------------------------------------------------------------------------+
      -- |                                    ZOOM                                     |
      -- +-----------------------------------------------------------------------------+

      {
        desc = "Qfmark: toggle zoom",
        func = function()
          Mapping.mark.full_screen_preview()
        end,
        keys = Config.keymaps.mark and Config.keymaps.mark.zoom,
        mode = "n",
        buffer = Mapping.buf,
        from_user = true,
      },

      -- +-----------------------------------------------------------------------------+
      -- |                                   MOVE TO                                   |
      -- +-----------------------------------------------------------------------------+

      {
        desc = "Qfmark: move item up",
        func = function()
          Mapping.mark.move_item_to(true)
        end,
        keys = Config.keymaps.mark and Config.keymaps.mark.move_item_up,
        mode = "n",
        buffer = Mapping.buf,
        from_user = true,
      },

      {
        desc = "Qfmark: move item down",
        func = function()
          Mapping.mark.move_item_to()
        end,
        keys = Config.keymaps.mark and Config.keymaps.mark.move_item_down,
        mode = "n",
        buffer = Mapping.buf,
        from_user = true,
      },

      -- +-----------------------------------------------------------------------------+
      -- |                                    MISC                                     |
      -- +-----------------------------------------------------------------------------+

      {
        desc = "Qfmark: delete item",
        func = function()
          Mapping.mark.delete_item()
        end,
        keys = Config.keymaps.actions and Config.keymaps.actions.del_item,
        mode = "n",
        buffer = Mapping.buf,
        from_user = true,
      },
      {
        desc = "Qfmark: delete all items",
        func = function()
          Mapping.mark.clear_all_items()
        end,
        keys = Config.keymaps.actions and Config.keymaps.actions.del_item_all,
        mode = "n",
        buffer = Mapping.buf,
        from_user = true,
      },

      {
        desc = "Qfmark: show preview context",
        func = function()
          Mapping.mark.preview_context()
        end,
        keys = Config.keymaps.mark and Config.keymaps.mark.preview_context,
        mode = "n",
        buffer = Mapping.buf,
        from_user = true,
      },

      {
        desc = "Qfmark: load QFMaster",
        func = function()
          Mapping.mark.select_and_load_qfmasters()
          Mapping.exit_close()
        end,
        keys = Config.keymaps.mark and Config.keymaps.mark.load_all,
        mode = "n",
        buffer = Mapping.buf,
        from_user = true,
      },

      {
        desc = "Qfmark: toggle selection",
        func = function()
          Mapping.mark.toggle_selection()
        end,
        keys = Config.keymaps.actions and Config.keymaps.actions.toggle_select,
        mode = "n",
        buffer = Mapping.buf,
        from_user = true,
      },

      {
        desc = "Qfmark: deselect all items",
        func = function()
          Mapping.mark.deselect_all_marks()
        end,
        keys = Config.keymaps.actions and Config.keymaps.actions.diselect_all,
        mode = "n",
        buffer = Mapping.buf,
        from_user = true,
      },
    },
  }, _keys)

  if Config.window.mark.allow_number then
    for i = 1, #Mapping.content_map do
      QfbookmarkKeymapUtils.append_active_keymaps({
        is_set = Config.window.mark.allow_number,
        keymaps = {
          {
            desc = "Qfmark: jump to " .. i,
            func = function()
              local curline = Mapping.content_map[i]
              Mapping.setup_open_key("default", curline.start_line)
            end,
            keys = tostring(i),
            mode = "n",
            buffer = Mapping.buf,
            from_user = true,
          },
        },
      }, _keys)
    end
  end

  if Config.keymaps.mark.integrations.custom.enabled then
    local user_mark_cmds = Config.keymaps.mark.integrations.custom
    if not user_mark_cmds then
      return
    end

    local user_keys = QfbookmarkKeymapUtils.set_user_mappings(user_mark_cmds, "mark", Mapping.buf)

    QfbookmarkKeymapUtils.append_active_keymaps({
      is_set = Config.keymaps.quickfix.integrations.custom.enabled,
      keymaps = user_keys,
    }, _keys)
  end

  QfbookmarkKeymapUtils.append_active_keymaps({
    is_set = true,
    keymaps = {
      {
        desc = "Qfmark: show helps",
        func = function()
          Mapping.show_help("QFMarks", _keys)
        end,
        keys = "g?",
        mode = { "n" },
        buffer = Mapping.buf,
        from_user = true,
      },
    },
  }, _keys)

  QfbookmarkKeymapUtils.set_keymaps(_keys, true)
end

---@param opts_popup QFBookmarkUiPopupCfg
---@param buf integer
function M.setup_keymap_buffers(opts_popup, buf)
  opts_popup.is_buffers = true
  opts_popup.is_harpoon = false
  opts_popup.is_mark_annotation = false

  local _keys = M.build_keymaps(opts_popup, buf)

  update_last_position_cursor "buffer"

  QfbookmarkKeymapUtils.append_active_keymaps({
    is_set = true,
    keymaps = {
      {
        desc = "Qfmark: delete item",
        func = function()
          Mapping.buffer.item_del()
        end,
        keys = Config.keymaps and Config.keymaps.actions.del_item,
        mode = "n",
        buffer = Mapping.buf,
        from_user = true,
      },
      {
        desc = "Qfmark: delete all items",
        func = function()
          Mapping.buffer.clear_all_items()
        end,
        keys = Config.keymaps and Config.keymaps.actions.del_item_all,
        mode = "n",
        buffer = Mapping.buf,
        from_user = true,
      },
      {
        desc = "Qfmark: toggle selection",
        func = function()
          Mapping.buffer.toggle_selection()
        end,
        keys = Config.keymaps.actions and Config.keymaps.actions.toggle_select,
        mode = "n",
        buffer = Mapping.buf,
        from_user = true,
      },

      {
        desc = "Qfmark: deselect all",
        func = function()
          Mapping.buffer.deselect_all_buffers()
        end,
        keys = Config.keymaps.actions and Config.keymaps.actions.diselect_all,
        mode = "n",
        buffer = Mapping.buf,
        from_user = true,
      },
    },
  }, _keys)

  if Config.window.buffers.allow_number then
    for i = 1, #Mapping.content_map do
      QfbookmarkKeymapUtils.append_active_keymaps({
        is_set = Config.window.buffers.allow_number,
        keymaps = {
          {
            desc = "Qfmark: jump to item [" .. i .. "]",
            func = function()
              local curline = Mapping.content_map[i]
              Mapping.setup_open_key("default", curline.start_line)
            end,
            keys = tostring(i),
            mode = "n",
            buffer = Mapping.buf,
            from_user = true,
          },
        },
      }, _keys)
    end
  end

  if Config.keymaps.buffers.integrations.custom.enabled then
    local user_mark_cmds = Config.keymaps.buffers.integrations.custom
    if not user_mark_cmds then
      return
    end

    local user_keys = QfbookmarkKeymapUtils.set_user_mappings(user_mark_cmds, "buffers", Mapping.buf)

    QfbookmarkKeymapUtils.append_active_keymaps({
      is_set = Config.keymaps.buffers.integrations.custom.enabled,
      keymaps = user_keys,
    }, _keys)
  end

  QfbookmarkKeymapUtils.append_active_keymaps({
    is_set = true,
    keymaps = {
      {
        desc = "Qfmark: show helps",
        func = function()
          Mapping.show_help("QFBuffers", _keys)
        end,
        keys = "g?",
        mode = { "n" },
        buffer = Mapping.buf,
        from_user = true,
      },
    },
  }, _keys)

  QfbookmarkKeymapUtils.set_keymaps(_keys, true)
end

---@param opts_popup QFBookmarkUiPopupCfg
---@param buf integer
---@param cb function
function M.setup_keymap_save_input(opts_popup, buf, cb)
  opts_popup.is_buffers = false
  opts_popup.is_harpoon = false
  opts_popup.is_mark_annotation = false
  opts_popup.is_note = false
  local _keys = M.build_keymaps(opts_popup, buf, cb)

  QfbookmarkKeymapUtils.append_active_keymaps({
    is_set = true,
    keymaps = {
      {
        desc = "Qfmark: save",
        func = function()
          Mapping.save.save_input()
        end,
        keys = "<CR>",
        mode = { "i", "n" },
        buffer = Mapping.buf,
        from_user = true,
      },
    },
  }, _keys)

  QfbookmarkKeymapUtils.set_keymaps(_keys, true)
end

---@param opts_popup QFBookmarkUiPopupCfg
---@param buf integer
function M.setup_keymap_note(opts_popup, buf)
  opts_popup.is_buffers = false
  opts_popup.is_harpoon = false
  opts_popup.is_mark_annotation = false
  opts_popup.is_note = true

  local _keys = M.build_keymaps(opts_popup, buf)

  QfbookmarkKeymapUtils.set_keymaps(_keys, true)
end

---@param opts_popup QFBookmarkUiPopupCfg
---@param buf integer
function M.setup_keymap_mark_annotation(opts_popup, buf)
  opts_popup.is_buffers = false
  opts_popup.is_harpoon = false
  opts_popup.is_note = false
  opts_popup.is_mark_annotation = true

  setup_popup_options(opts_popup, buf)

  local _keys = M.build_keymaps(opts_popup, buf)

  QfbookmarkKeymapUtils.append_active_keymaps({
    is_set = true,
    keymaps = {

      -- +-----------------------------------------------------------------------------+
      -- |                                   PREVIEW                                   |
      -- +-----------------------------------------------------------------------------+

      {
        desc = "Qfmark: scroll preview up",
        func = function()
          Mapping.mark.scroll_preview_window(-1)
        end,
        keys = Config.keymaps.actions and Config.keymaps.actions.scroll_preview_up,
        mode = "n",
        buffer = Mapping.buf,
        from_user = true,
      },

      {
        desc = "Qfmark: scroll preview down",
        func = function()
          Mapping.mark.scroll_preview_window(1)
        end,
        keys = Config.keymaps.actions and Config.keymaps.actions.scroll_preview_down,
        mode = "n",
        buffer = Mapping.buf,
        from_user = true,
      },

      {
        desc = "Qfmark: scroll preview up (fast)",
        func = function()
          Mapping.mark.scroll_preview_window(-1, 10)
        end,
        keys = Config.keymaps.actions and Config.keymaps.actions.scroll_preview_up_fast,
        mode = "n",
        buffer = Mapping.buf,
        from_user = true,
      },

      {
        desc = "Qfmark: scroll preview down (fast)",
        func = function()
          Mapping.mark.scroll_preview_window(1, 10)
        end,
        keys = Config.keymaps.actions and Config.keymaps.actions.scroll_preview_down_fast,
        mode = "n",
        buffer = Mapping.buf,
        from_user = true,
      },

      {
        desc = "Qfmark: save annotation",
        func = function()
          Mapping.save.save_input()
          if opts_popup._opts.anchor and opts_popup._opts.anchor == "editor" then
            QfbookmarkUtils.info "Added 1 item(s); skipped 0 item(s) already present."
          end
        end,
        keys = Config.keymaps.actions and Config.keymaps.actions.default,
        mode = { "i", "n" },
        buffer = Mapping.buf,
        from_user = true,
      },
    },
  }, _keys)

  QfbookmarkKeymapUtils.append_active_keymaps({
    is_set = true,
    keymaps = {
      {
        desc = "Qfmark: show helps",
        func = function()
          Mapping.show_help("QFMarkAnnotation", _keys)
        end,
        keys = "g?",
        mode = { "n" },
        buffer = Mapping.buf,
        from_user = true,
      },
    },
  }, _keys)

  QfbookmarkKeymapUtils.set_keymaps(_keys, true)
end

function M.setup_keymap_preview_mark_annotation(opts_popup, buf)
  opts_popup.is_buffers = false
  opts_popup.is_harpoon = false
  opts_popup.is_note = false
  opts_popup.is_mark_annotation = true

  setup_popup_options(opts_popup, buf)

  local _keys = M.build_keymaps(opts_popup, buf)

  local QfbookmarkMarkContext = require "qfbookmark.mark.context"

  QfbookmarkKeymapUtils.append_active_keymaps({
    is_set = true,
    keymaps = {

      -- +-----------------------------------------------------------------------------+
      -- |                                   PREVIEW                                   |
      -- +-----------------------------------------------------------------------------+

      {
        desc = "Qfmark: send dispatch",
        func = function()
          local resolve_preview_opts = QfbookmarkUIUtils.resolve_preview_context(opts_popup)
          if resolve_preview_opts.text then
            QfbookmarkMarkContext.dispatch(resolve_preview_opts.text, opts_popup.opts_mark_preview.send_target)
          end
          QfbookmarkUIUtils.close_win { Mapping.popup.win, Mapping.popup.preview and Mapping.popup.preview.win or nil }
          QfbookmarkUIUtils.clean_up(Mapping.popup)
        end,
        keys = "<CR>",
        mode = "n",
        buffer = Mapping.buf,
        from_user = true,
      },

      {
        desc = "Qfmark: toggle tab",
        func = function()
          opts_popup.current_idx = (opts_popup.current_idx % #opts_popup.names) + 1
          QfbookmarkUIUtils.render_mark_preview_annotation(opts_popup.popup.buf, opts_popup.popup.win, opts_popup)
        end,
        keys = "<TAB>",
        mode = "n",
        buffer = Mapping.buf,
        from_user = true,
      },

      {
        desc = "Qfmark: copy clipboard",
        func = function()
          local resolve_preview_opts = QfbookmarkUIUtils.resolve_preview_context(opts_popup)
          if resolve_preview_opts.text then
            QfbookmarkMarkContext.dispatch(resolve_preview_opts.text, "clipboard")
          end
          QfbookmarkUIUtils.close_win { Mapping.popup.win, Mapping.popup.preview and Mapping.popup.preview.win or nil }
          QfbookmarkUIUtils.clean_up(Mapping.popup)
        end,
        keys = "y",
        mode = "n",
        buffer = Mapping.buf,
        from_user = true,
      },
    },
  }, _keys)

  QfbookmarkKeymapUtils.append_active_keymaps({
    is_set = true,
    keymaps = {
      {
        desc = "Qfmark: show helps",
        func = function()
          Mapping.show_help("QFMarkAnnotation", _keys)
        end,
        keys = "g?",
        mode = { "n" },
        buffer = Mapping.buf,
        from_user = true,
      },
    },
  }, _keys)

  QfbookmarkKeymapUtils.set_keymaps(_keys, true)
end

---@param opts_popup QFBookmarkUiPopupCfg
---@param buf integer
function M.setup_keymap_select_category(opts_popup, buf)
  opts_popup.is_buffers = false
  opts_popup.is_harpoon = false
  opts_popup.is_note = false
  opts_popup.is_mark_annotation = true

  setup_popup_options(opts_popup, buf)

  local _keys = {}

  QfbookmarkKeymapUtils.append_active_keymaps({
    is_set = true,
    keymaps = {
      {
        desc = "Qfmark: quit",
        func = function()
          Mapping.exit_close()
        end,
        keys = Config.keymaps.actions and Config.keymaps.actions.quit,
        mode = "n",
        buffer = Mapping.buf,
        from_user = true,
      },
      {
        desc = "Qfmark: enter category",
        func = function()
          local row = vim.api.nvim_win_get_cursor(Mapping.popup.win)[1]
          Mapping.exit_close()

          Mapping.on_submit(Mapping.opts_popup.contents[row].name)
        end,
        keys = "<CR>",
        mode = { "i", "n" },
        buffer = Mapping.buf,
        from_user = true,
      },
    },
  }, _keys)

  for shortcut, name in pairs(opts_popup.keys_shortcuts) do
    QfbookmarkKeymapUtils.append_active_keymaps({
      is_set = Config.window.buffers.allow_number,
      keymaps = {
        {
          desc = "Qfmark: select category by key {" .. name .. "}",
          func = function()
            Mapping.on_submit(name)
          end,
          keys = tostring(shortcut),
          mode = "n",
          buffer = Mapping.buf,
          from_user = true,
        },
      },
    }, _keys)
  end

  QfbookmarkKeymapUtils.append_active_keymaps({
    is_set = true,
    keymaps = {
      {
        desc = "Qfmark: show helps",
        func = function()
          Mapping.show_help("QFSelectCategory", _keys)
        end,
        keys = "g?",
        mode = { "n" },
        buffer = Mapping.buf,
        from_user = true,
      },
    },
  }, _keys)

  QfbookmarkKeymapUtils.set_keymaps(_keys, true)
end

return M
