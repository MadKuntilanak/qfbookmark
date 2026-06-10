local QfbookmarkUIUtils = require "qfbookmark.ui.utils"
local QfbookmarkUIKeymaps = require "qfbookmark.ui.keymaps"
local QfbookmarkUIPopup = require "qfbookmark.ui.popup"
local QfbookmarkMarkVisual = require "qfbookmark.visual"

---@alias WinCfg { buf: integer, enter: boolean, wincfg: vim.api.keyset.win_config }
---@alias QfBookUiWinCfg {  save: QFBookUiCfg, save_footer: QFBookUiCfg, mark_preview: QFBookUiCfg, mark: QFBookUiCfg, buffer: QFBookUiCfg, note: QFBookUiCfg }
---@alias QfBookUiPopupCfg { contents: table, content_map:table<integer, string>, win_opts: WinCfg, display_lines: table, entry_start_line: table, popup?: {win?: integer, buf?:integer, preview?: {win?: integer, buf?:integer} }, is_harpoon?: boolean, is_buffers?: boolean, save: {title: string, target_path: string, is_loc:boolean, cb:function, for_what:"save"|"rename"} }

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

    -- +-----------------------------------------------------------------------------+
    -- | Rebuild both maps by scanning buffer header lines (" N  ").                 |
    -- | called by move_item_to after every reorder.                                 |
    -- +-----------------------------------------------------------------------------+
    M.rebuild_mark_maps = function()
      if not vim.api.nvim_buf_is_valid(main_buf) then
        return
      end
      local raw_lines = vim.api.nvim_buf_get_lines(main_buf, 0, -1, false)
      local new_entry_start = {}
      local new_harpoon_map = {}
      local entry_idx = 0

      for ln, line in ipairs(raw_lines) do
        local idx_str = line:match "^ (%d+) "
        if idx_str then
          -- this is a header line — start of a new entry
          entry_idx = entry_idx + 1
          new_entry_start[entry_idx] = ln
          -- new_harpoon_map[ln] = opts_popup.content_map[M.mark_harpoon_map and ln or ln]
          new_harpoon_map[ln] = opts_popup.content_map[opts_popup.content_map and ln or ln]
          -- look up harpoon value by the original idx stored in the line
          local orig_idx = tonumber(idx_str)
          local orig_start = opts_popup.entry_start_line[orig_idx]
          if orig_start then
            local hval = opts_popup.content_map[orig_start]
            -- map all consecutive lines until next header to this hval
            new_harpoon_map[ln] = hval
          end
        else
          -- detail or symbol line — same hval as the most recent header
          if entry_idx > 0 and new_entry_start[entry_idx] then
            local header_hval = new_harpoon_map[new_entry_start[entry_idx]]
            if header_hval then
              new_harpoon_map[ln] = header_hval
            end
          end
        end
      end

      -- update both M state and the closure tables in-place
      -- (in-place update so update_cursorline closure sees new values)
      for k in pairs(opts_popup.content_map) do
        opts_popup.content_map[k] = nil
      end
      for k, v in pairs(new_harpoon_map) do
        opts_popup.content_map[k] = v
      end

      for k in pairs(opts_popup.entry_start_line) do
        opts_popup.entry_start_line[k] = nil
      end
      for k, v in pairs(new_entry_start) do
        opts_popup.entry_start_line[k] = v
      end

      -- opts_popup.entry_start_line = opts_popup. entry_start_line
      -- opts_popup.content_map = harpoon_map

      -- re-apply extmark highlights with updated positions
      QfbookmarkMarkVisual.apply_entry_highlights(main_buf, opts_popup.contents, opts_popup.entry_start_line)
    end

    -- Apply syntax highlights to all entries
    QfbookmarkMarkVisual.apply_entry_highlights(main_buf, opts_popup.contents, opts_popup.entry_start_line)

    -- +-----------------------------------------------------------------------------+
    -- | Re-apply highlights after dd deletes lines                                  |
    -- +-----------------------------------------------------------------------------+
    vim.api.nvim_create_autocmd("TextChanged", {
      buffer = main_buf,
      callback = function()
        -- rebuild active mark list from remaining header lines
        local remaining = {}
        local raw_lines = vim.api.nvim_buf_get_lines(main_buf, 0, -1, false)
        for _, raw in ipairs(raw_lines) do
          local idx_str = raw:match "^ (%d+) "
          if idx_str then
            local original_idx = tonumber(idx_str)
            local hval = opts_popup.content_map[(original_idx - 1) * 2 + 1]
            if hval then
              for _, m in ipairs(opts_popup.contents) do
                if m.harpoon == hval then
                  remaining[#remaining + 1] = m
                  break
                end
              end
            end
          end
        end
        QfbookmarkMarkVisual.apply_entry_highlights(main_buf, remaining, opts_popup.entry_start_line)
      end,
    })

    -- +-----------------------------------------------------------------------------+
    -- | Multi-line cursorline: highlight all lines of the current entry             |
    -- +-----------------------------------------------------------------------------+
    local cursorline_ns = vim.api.nvim_create_namespace "qfbookmark_cursorline"
    local function update_cursorline()
      if not main_buf or not vim.api.nvim_buf_is_valid(main_buf) then
        return
      end

      vim.api.nvim_buf_clear_namespace(main_buf, cursorline_ns, 0, -1)
      local cur = vim.api.nvim_win_get_cursor(0)[1]
      local hval = opts_popup.content_map[cur]
      if not hval then
        return
      end
      -- find all lines that belong to the same entry
      for ln, h in pairs(opts_popup.content_map) do
        if h == hval then
          pcall(vim.api.nvim_buf_set_extmark, main_buf, cursorline_ns, ln - 1, 0, {
            end_col = 0,
            end_row = ln,
            hl_group = "QFBookmarkFloatCursorLine",
            hl_eol = true,
            priority = 50,
          })
        end
      end
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
    local buf, win = QfbookmarkUIPopup.new_open(opts_popup.win_opts, opts_popup.display_lines)
    if not win or not vim.api.nvim_win_is_valid(win) then
      return
    end
    if not buf or not vim.api.nvim_buf_is_valid(buf) then
      return
    end

    M.window.note.win = win
    M.window.note.buf = buf

    if not opts_popup.popup then
      opts_popup.popup = {}
      opts_popup.popup.win = M.window.note.win
      opts_popup.popup.buf = M.window.note.buf
    end

    QfbookmarkUIKeymaps.setup_keymap_note(opts_popup, buf)
  end,
}

---@param for_what "mark" | "buffer" | "save"| "note"
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
  if for_what == "buffer" or for_what == "note" then
    __popup_opts_for[for_what](opts_popup)
  elseif for_what == "save" then
    if cb then
      __popup_opts_for[for_what](opts_popup, cb)
    end
  else -- Mark
    if cb then
      __popup_opts_for[for_what](opts_popup, cb)
    end
  end
end

return M
