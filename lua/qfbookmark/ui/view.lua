local QfbookmarkUIUtils = require "qfbookmark.ui.utils"
local QfbookmarkUIKeymaps = require "qfbookmark.ui.keymaps"
local QfbookmarkUIPopup = require "qfbookmark.ui.popup"
local QfbookmarkMarkVisual = require "qfbookmark.visual"
local QfbookmarkUtils = require "qfbookmark.utils"

---@alias WinCfg { buf: integer, enter: boolean, wincfg: vim.api.keyset.win_config }

local M = {}

M.filetype = "qfbookmark"

---@type QFBookmarkWinCfg
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
    namespace = "qfbookmark_popup_footer",
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
    namespace = "qfbookmark_popup_buffer",
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
  select_category = {
    augroup = "WinMarkNoteMark",
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
  ---@param opts_popup QFBookmarkUiPopupCfg
  ---@param cb function
  ["mark"] = function(opts_popup, cb)
    local main_buf, main_win = QfbookmarkUIPopup.new_open(opts_popup.win_opts, opts_popup.display_lines)
    if not QfbookmarkUtils.is_valid(main_buf, main_win) then
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
    QfbookmarkUIUtils.update_title_win_popup(main_win, total_selected, opts_popup.selected)

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

      if not QfbookmarkUtils.is_valid(main_buf, main_win) then
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
        priority = 10,
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

    local buf_preview, win_preview = QfbookmarkUIPopup.mark_preview(
      main_win_cfg,
      opts_popup.win_opts.wincfg.width,
      nil,
      { fullscreen = require("qfbookmark.config").defaults.window.mark.preview_fullscreen }
    )
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

      opts_popup.popup.preview.fullscreen = require("qfbookmark.config").defaults.window.mark.preview_fullscreen
        or false

      local preview_win_cfg = vim.api.nvim_win_get_config(win_preview)
      opts_popup.popup.preview.wincfg = preview_win_cfg
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
  ---@param opts_popup QFBookmarkUiPopupCfg
  ["buffer"] = function(opts_popup)
    local buf, win = QfbookmarkUIPopup.new_open(opts_popup.win_opts, opts_popup.display_lines)

    if not QfbookmarkUtils.is_valid(buf, win) then
      return
    end

    M.window.buffer.win = win
    M.window.buffer.buf = buf

    setup_option_main_popup(win, buf)

    if not opts_popup.popup then
      opts_popup.popup = {}
      opts_popup.popup.win = M.window.buffer.win
      opts_popup.popup.buf = M.window.buffer.buf
      opts_popup.popup.namespace = M.window.buffer.namespace
    end

    -- apply syntax highlights to all entries
    QfbookmarkMarkVisual.apply_entry_buffer_highlights(
      buf,
      opts_popup.contents,
      opts_popup.buffer_selected,
      opts_popup.popup.namespace
    )

    QfbookmarkUIKeymaps.setup_keymap_buffers(opts_popup, buf)
  end,
  ---@param opts_popup QFBookmarkUiPopupCfg
  ["save"] = function(opts_popup, cb)
    local buf, win = QfbookmarkUIPopup.new_open(opts_popup.win_opts, opts_popup.display_lines)

    if not QfbookmarkUtils.is_valid(buf, win) then
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
        opts_popup.popup.preview.namespace = M.window.save_footer.namespace
      end
    end

    -- unplan: I don't think this popup needs syntax highlighting..:(
    QfbookmarkUIKeymaps.setup_keymap_save_input(opts_popup, buf, cb)
  end,
  ["note"] = function(opts_popup)
    local main_buf, main_win = QfbookmarkUIPopup.new_open(opts_popup.win_opts, opts_popup.display_lines)

    if not QfbookmarkUtils.is_valid(main_buf, main_win) then
      return
    end

    M.window.note.buf = main_buf
    M.window.note.win = main_win

    if not opts_popup.popup then
      opts_popup.popup = {}
      opts_popup.popup.buf = M.window.note.buf
      opts_popup.popup.win = M.window.note.win
    end

    QfbookmarkUIKeymaps.setup_keymap_note(opts_popup, main_buf)

    vim.schedule(function()
      if vim.api.nvim_win_is_valid(main_win) then
        vim.api.nvim_win_call(main_win, function()
          vim.cmd("edit " .. vim.fn.fnameescape(opts_popup.note_path))
        end)
      end
    end)
  end,
  ---@param opts_popup QFBookmarkUiPopupCfg
  ["mark_annotation"] = function(opts_popup)
    local main_buf, main_win = QfbookmarkUIPopup.new_open(opts_popup.win_opts, opts_popup.display_lines)

    if not QfbookmarkUtils.is_valid(main_buf, main_win) then
      return
    end

    M.window.mark_annotation.win = main_win
    M.window.mark_annotation.buf = main_buf

    if not opts_popup.popup then
      opts_popup.popup = {}
      opts_popup.popup.win = M.window.mark_annotation.win
      opts_popup.popup.buf = M.window.mark_annotation.buf
    end

    setup_option_main_popup(main_win, main_buf, true)

    local main_win_cfg = vim.api.nvim_win_get_config(main_win)

    local buf_preview, win_preview =
      QfbookmarkUIPopup.mark_note_preview(opts_popup, main_win_cfg, opts_popup.win_opts.wincfg.width)
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

    if opts_popup._opts and opts_popup._opts.keyword_def then
      local hl = opts_popup._opts.keyword_def.hl_group
      vim.wo[main_win].winhighlight = "NormalFloat:Normal,FloatFooter:QFBookmarkFloatFooter,FloatTitle:"
        .. (hl or "QFBookmarkFloatTitle")
    end

    vim.bo[main_buf].filetype = "qfbookmark"
    vim.bo[main_buf].buftype = ""
    vim.bo[main_buf].bufhidden = "wipe"

    QfbookmarkUIKeymaps.setup_keymap_mark_annotation(opts_popup, main_buf)

    if opts_popup.data_annotation and opts_popup.data_annotation.load_chunk then
      local raw_lines = opts_popup.data_annotation.chunk.note

      -- insert after prompt_setcallback/startinsert so it lands after "> "
      -- and cursor ends up at the end, ready to keep typing/editing
      vim.api.nvim_buf_set_lines(main_buf, -2, -1, false, raw_lines)
      vim.api.nvim_win_set_cursor(main_win, { 1, #raw_lines })
    end

    vim.cmd "startinsert!"
  end,
  ["select_category"] = function(opts_popup)
    local buf, win = QfbookmarkUIPopup.new_open(opts_popup.win_opts, opts_popup.display_lines)

    if not QfbookmarkUtils.is_valid(buf, win) then
      return
    end

    M.window.select_category.buf = buf
    M.window.select_category.win = win

    if not opts_popup.popup then
      opts_popup.popup = {}
      opts_popup.popup.buf = M.window.select_category.buf
      opts_popup.popup.win = M.window.select_category.win
    end

    setup_option_main_popup(win, buf)

    local QfbookmarkMarkUtils = require "qfbookmark.mark.utils"
    local ns = QfbookmarkMarkUtils.register_namespace "qfbookmark_extmark_dropdown"
    QfbookmarkMarkUtils.del_namespace(buf, ns)

    for i, item in ipairs(opts_popup.contents) do
      vim.api.nvim_buf_set_extmark(buf, ns, i - 1, 2, {
        end_col = 5,
        hl_group = item.def.hl_group or "Comment",
      })
    end

    QfbookmarkUIKeymaps.setup_keymap_select_category(opts_popup, buf)
  end,
  ["preview_mark_annotation"] = function(opts_popup)
    local main_buf, main_win = QfbookmarkUIPopup.new_open(opts_popup.win_opts, opts_popup.display_lines)

    if not QfbookmarkUtils.is_valid(main_buf, main_win) then
      return
    end

    M.window.mark_annotation.win = main_win
    M.window.mark_annotation.buf = main_buf

    if not opts_popup.popup then
      opts_popup.popup = {}
      opts_popup.popup.win = M.window.mark_annotation.win
      opts_popup.popup.buf = M.window.mark_annotation.buf
    end

    if not opts_popup.names then
      local QfbookmarkMarkUtils = require "qfbookmark.mark.utils"
      opts_popup.names = QfbookmarkMarkUtils.template_names()
    end

    if #opts_popup.names == 0 then
      QfbookmarkUtils.warn "no context templates available"
      return
    end

    opts_popup.current_idx = 1
    if opts_popup.opts_mark_preview.default_template then
      for i, n in ipairs(opts_popup.names) do
        if n == opts_popup.opts_mark_preview.default_template.default_template then
          opts_popup.current_idx = i
        end
      end
    end

    vim.bo[main_buf].filetype = "markdown"

    QfbookmarkUIKeymaps.setup_keymap_preview_mark_annotation(opts_popup, main_buf)

    QfbookmarkUIUtils.render_mark_preview_annotation(main_buf, main_win, opts_popup)
  end,
}

---@param for_what "mark" | "buffer" | "save"| "note" | "mark_annotation" | "select_category" | "preview_mark_annotation"
---@param opts_popup QFBookmarkUiPopupCfg
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
  if
    vim.tbl_contains({ "buffer", "note", "select_category", "mark_annotation", "preview_mark_annotation" }, for_what)
  then
    __popup_opts_for[for_what](opts_popup)
  end

  if vim.tbl_contains({ "mark", "save" }, for_what) then
    if cb then
      __popup_opts_for[for_what](opts_popup, cb)
    end
  end
end

return M
