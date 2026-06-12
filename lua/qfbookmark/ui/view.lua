local QfbookmarkUIUtils = require "qfbookmark.ui.utils"
local QfbookmarkUIKeymaps = require "qfbookmark.ui.keymaps"
local QfbookmarkUIPopup = require "qfbookmark.ui.popup"
local QfbookmarkMarkVisual = require "qfbookmark.visual"

---@alias WinCfg { buf: integer, enter: boolean, wincfg: vim.api.keyset.win_config }

local M = {}

M.filetype = "qfbookmark"

---@type QfBookUiWinCfg
M.window = {
  save = {
    augroup = "WinSavePopup",
    win = nil,
    buf = nil,
  },
  save_footer = {
    augroup = "WinMarkSaveFooter",
    win = nil,
    buf = nil,
  },
  mark = {
    augroup = "WinMarkPopup",
    win = nil,
    buf = nil,
  },
  mark_preview = {
    augroup = "WinMarkPreview",
    win = nil,
    buf = nil,
  },
  buffer = {
    augroup = "WinMarkBuffer",
    win = nil,
    buf = nil,
  },
  note = {
    augroup = "WinMarkNote",
    win = nil,
    buf = nil,
  },
  mark_annotation = {
    augroup = "WinMarkNoteMark",
    win = nil,
    buf = nil,
  },
  mark_annotation_preview = {
    augroup = "WinMarkNoteMarkPreview",
    win = nil,
    buf = nil,
  },
}

---@param win integer
---@param buf integer
---@param is_editable? boolean
local function setup_option_main_popup(win, buf, is_editable)
  is_editable = is_editable or false

  vim.api.nvim_set_option_value("filetype", M.filetype, { buf = buf })

  if not is_editable then
    vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
    vim.api.nvim_set_option_value("readonly", true, { buf = buf })
    vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
  end

  vim.api.nvim_set_option_value("cursorline", true, { win = win, scope = "local" })

  vim.api.nvim_set_option_value(
    "winhighlight",
    "Normal:Error,"
      .. "NormalFloat:QFBookmarkNormalFloat,"
      .. "FloatBorder:QFBookmarkFloatBorder,"
      .. "FloatTitle:QFBookmarkFloatTitle,"
      .. "FloatFooter:QFBookmarkFloatFooter,"
      .. "CursorLine:QFBookmarkFloatCursorLine,",
    { win = win, scope = "local" }
  )
end

local __popup_opts_for = {
  ---@param opts_popup QfBookUiPopupCfg
  ---@param cb function
  ["mark"] = function(opts_popup, cb)
    local main_buf, main_win = QfbookmarkUIPopup.new_open(opts_popup.win_opts, opts_popup.display_lines)

    if not main_win or not vim.api.nvim_win_is_valid(main_win) then
      return
    end
    if not main_buf or not vim.api.nvim_buf_is_valid(main_buf) then
      return
    end

    M.window.mark.win = main_win
    M.window.mark.buf = main_buf

    setup_option_main_popup(main_win, main_buf)

    QfbookmarkMarkVisual.apply_entry_highlights(
      main_buf,
      opts_popup.content_map,
      opts_popup.selected,
      opts_popup.active
    )

    -- Update title if there are selected marks
    local total_selected = #opts_popup.content_map
    QfbookmarkUIUtils.update_title_mark_harpoon_popup(main_win, total_selected, opts_popup.selected)

    -- +-----------------------------------------------------------------------------+
    -- | Re-apply highlights after dd deletes lines                                  |
    -- +-----------------------------------------------------------------------------+
    vim.api.nvim_create_autocmd("TextChanged", {
      buffer = main_buf,
      callback = function()
        QfbookmarkMarkVisual.apply_entry_highlights(
          main_buf,
          opts_popup.content_map,
          opts_popup.selected,
          opts_popup.active
        )
      end,
    })

    -- +-----------------------------------------------------------------------------+
    -- | Multi-line cursorline: highlight all lines of the current entry             |
    -- +-----------------------------------------------------------------------------+

    local function update_cursorline()
      local cursorline_ns = vim.api.nvim_create_namespace "qfbookmark_cursorline"
      vim.api.nvim_buf_clear_namespace(main_buf, cursorline_ns, 0, -1)

      if not main_buf or not vim.api.nvim_buf_is_valid(main_buf) then
        return
      end

      local cur = vim.api.nvim_win_get_cursor(main_win)[1]
      local entries = opts_popup.content_map
      if not entries then
        return
      end

      local active = nil
      for _, e in ipairs(entries) do
        local start = e.start_line
        local finish = start + (e.line_count or 1) - 1
        if cur >= start and cur <= finish then
          active = e
          break
        end
      end

      if not active then
        return
      end

      local start = active.start_line
      local finish = start + active.line_count - 1

      vim.api.nvim_buf_set_extmark(main_buf, cursorline_ns, start - 1, 0, {
        end_row = finish,
        hl_group = "QFBookmarkFloatCursorLine",
        hl_eol = true,
        priority = 50,
      })

      -- Rebuild all checkboxes with the correct cursor_hval
      opts_popup.active = active.hval
      QfbookmarkMarkVisual.apply_entry_highlights(main_buf, opts_popup.content_map, opts_popup.selected, active.hval)
    end

    vim.api.nvim_create_autocmd("CursorMoved", {
      buffer = main_buf,
      callback = update_cursorline,
    })

    -- Trigger immediately on open
    vim.schedule(update_cursorline)

    -- +-----------------------------------------------------------------------------+
    -- | PREVIEW WIN                                                                 |
    -- +-----------------------------------------------------------------------------+
    local main_win_cfg = vim.api.nvim_win_get_config(main_win)

    local buf_preview, win_preview = QfbookmarkUIPopup.mark_preview(main_win_cfg, opts_popup.win_opts.wincfg.width)
    if not win_preview or not buf_preview then
      return
    end

    M.window.mark_preview.buf = buf_preview
    M.window.mark_preview.win = win_preview

    -- Wire up CursorMoved preview with the new harpoon_map
    QfbookmarkUIPopup.setup_mark_preview_contents(opts_popup, main_buf, win_preview, buf_preview)

    if not opts_popup.popup then
      opts_popup.popup = {}
      opts_popup.popup.win = M.window.mark.win
      opts_popup.popup.buf = M.window.mark.buf
    end

    if not opts_popup.popup.preview then
      opts_popup.popup.preview = {}
      opts_popup.popup.preview.buf = M.window.mark_preview.buf
      opts_popup.popup.preview.win = M.window.mark_preview.win
    end

    -- Callback wrapper: convert Harpoon values (plain) into the format expected by qf.lua,
    -- including idx prefix via add_idx_m_harpoon
    local function cb_wrapper(harpoon_vals)
      if cb then
        cb(harpoon_vals)
      end
    end

    QfbookmarkUIKeymaps.setup_keymap_mark(opts_popup, main_buf, cb_wrapper)
  end,
  ---@param opts_popup QfBookUiPopupCfg
  ["buffer"] = function(opts_popup)
    local buf, win = QfbookmarkUIPopup.new_open(opts_popup.win_opts, opts_popup.display_lines)
    if not win or not vim.api.nvim_win_is_valid(win) then
      return
    end
    if not buf or not vim.api.nvim_buf_is_valid(buf) then
      return
    end

    M.window.buffer.win = win
    M.window.buffer.buf = buf

    setup_option_main_popup(win, buf)

    -- apply syntax highlights to all entries
    QfbookmarkMarkVisual.apply_entry_buffer_highlights(buf)

    if not opts_popup.popup then
      opts_popup.popup = {}
      opts_popup.popup.win = M.window.buffer.win
      opts_popup.popup.buf = M.window.buffer.buf
    end

    QfbookmarkUIKeymaps.setup_keymap_buffers(opts_popup, buf)
  end,
  ---@param opts_popup QfBookUiPopupCfg
  ["save"] = function(opts_popup, cb)
    local buf, win = QfbookmarkUIPopup.new_open(opts_popup.win_opts, opts_popup.display_lines)
    if not win or not vim.api.nvim_win_is_valid(win) then
      return
    end
    if not buf or not vim.api.nvim_buf_is_valid(buf) then
      return
    end

    M.window.save.win = win
    M.window.save.buf = buf

    if not opts_popup.popup then
      opts_popup.popup = {}
      opts_popup.popup.win = M.window.save.win
      opts_popup.popup.buf = M.window.save.buf
    end

    setup_option_main_popup(win, buf, true)

    -- Show a preview before saving a quickfix list.
    if opts_popup.save.for_what == "save" then
      local main_win_cfg = vim.api.nvim_win_get_config(win)

      local buf_preview, win_preview = QfbookmarkUIPopup.save_footer(opts_popup, main_win_cfg)
      if not win_preview or not buf_preview then
        return
      end

      M.window.save_footer.buf = buf_preview
      M.window.save_footer.win = win_preview

      if not opts_popup.popup.preview then
        opts_popup.popup.preview = {}
        opts_popup.popup.preview.buf = M.window.save_footer.buf
        opts_popup.popup.preview.win = M.window.save_footer.win
      end
    end

    -- unplan: I don't think this popup needs syntax highlighting..:(
    QfbookmarkUIKeymaps.setup_keymap_save_input(opts_popup, buf, cb)
  end,
  ["note"] = function(opts_popup)
    local main_buf, main_win = QfbookmarkUIPopup.new_open(opts_popup.win_opts, opts_popup.display_lines)
    if not main_win or not vim.api.nvim_win_is_valid(main_win) then
      return
    end
    if not main_buf or not vim.api.nvim_buf_is_valid(main_buf) then
      return
    end

    M.window.note.buf = main_buf
    M.window.note.win = main_win

    if not opts_popup.popup then
      opts_popup.popup = {}
      opts_popup.popup.buf = M.window.note.buf
      opts_popup.popup.win = M.window.note.win
    end

    local Config = require("qfbookmark.config").defaults
    local filetype = Config.window.note and Config.window.note.filetype or ""
    if #filetype > 0 then
      vim.api.nvim_set_option_value("filetype", filetype, { buf = main_buf })
    end

    QfbookmarkUIKeymaps.setup_keymap_note(opts_popup, main_buf)
  end,
  ---@param opts_popup QfBookUiPopupCfg
  ---@param cb function
  ["mark_annotation"] = function(opts_popup, cb)
    local main_buf, main_win = QfbookmarkUIPopup.new_open(opts_popup.win_opts, opts_popup.display_lines)
    if not main_win or not vim.api.nvim_win_is_valid(main_win) then
      return
    end
    if not main_buf or not vim.api.nvim_buf_is_valid(main_buf) then
      return
    end

    M.window.mark_annotation.win = main_win
    M.window.mark_annotation.buf = main_buf

    if not opts_popup.popup then
      opts_popup.popup = {}
      opts_popup.popup.win = M.window.mark_annotation.win
      opts_popup.popup.buf = M.window.mark_annotation.buf
    end

    local main_win_cfg = vim.api.nvim_win_get_config(main_win)

    local buf_preview, win_preview = QfbookmarkUIPopup.mark_note_preview(main_win_cfg, opts_popup.win_opts.wincfg.width)
    if not win_preview or not buf_preview then
      return
    end

    M.window.mark_annotation_preview.buf = buf_preview
    M.window.mark_annotation_preview.win = win_preview

    if not opts_popup.popup.preview then
      opts_popup.popup.preview = {}
      opts_popup.popup.preview.buf = M.window.mark_annotation_preview.buf
      opts_popup.popup.preview.win = M.window.mark_annotation_preview.win
    end

    -- Wire up CursorMoved preview with the new harpoon_map
    QfbookmarkUIPopup.setup_mark_preview_contents(opts_popup, main_buf, win_preview, buf_preview, true)

    QfbookmarkUIKeymaps.setup_keymap_mark_annotation(opts_popup, main_buf, cb)

    vim.api.nvim_buf_call(main_buf, function()
      vim.cmd.startinsert()

      if opts_popup.data_annotation and opts_popup.data_annotation.load_chunk then
        local mark_data = opts_popup.data_annotation.chunk
        local data_lines = mark_data.note or {}
        local lines
        if type(data_lines) == "string" then
          lines = { data_lines }
        else
          lines = data_lines
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
      end
    end)
  end,
}

---@param for_what "mark" | "buffer" | "save"| "note" | "mark_annotation"
---@param opts_popup QfBookUiPopupCfg
---@param is_editable? boolean
---@param cb? function | nil
function M.build_popup(for_what, opts_popup, cb, is_editable)
  cb = cb or nil
  is_editable = is_editable or false

  -- Clean up leftover windows and buffers before opening the popup.
  M.window = QfbookmarkUIUtils.clean_up(M.window)
  if opts_popup.popup then
    opts_popup.popup = nil
  end

  -- Call popup open window
  if vim.tbl_contains({ "buffer", "note" }, for_what) then
    __popup_opts_for[for_what](opts_popup)
  elseif vim.tbl_contains({ "mark", "mark_annotation", "save" }, for_what) then
    if cb then
      __popup_opts_for[for_what](opts_popup, cb)
    end
  end
end

return M
