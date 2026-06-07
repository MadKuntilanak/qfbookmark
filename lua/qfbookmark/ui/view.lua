local QfbookmarkUIUtils = require "qfbookmark.ui.utils"
local QfbookmarkUIKeymaps = require "qfbookmark.ui.keymaps"
local QfbookmarkUIPopup = require "qfbookmark.ui.popup"
local QfbookmarkMarkVisual = require "qfbookmark.visual"

---@alias WinCfg { buf: integer, enter: boolean, wincfg: vim.api.keyset.win_config }
---@alias QfBookUiWinCfg {  save: QFBookUiCfg, save_footer: QFBookUiCfg, mark_preview: QFBookUiCfg, mark: QFBookUiCfg, buffer: QFBookUiCfg  }
---@alias QfBookUiPopupCfg { contents: table, content_map:table<integer, string>, win_opts: WinCfg, display_lines: table, popup?: {win?: integer, buf?:integer, preview?: {win?: integer, buf?:integer} }, is_harpoon?: boolean, is_buffers?: boolean, save: {title: string, target_path: string, is_loc:boolean, cb:function, for_what:"save"|"rename"} }

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
}

---@param win integer
-- local setup_ui_autocmd = function(augroup, win)
--   -- keep the cursor locked inside the floating window
--   local group = QfbookmarkUtils.create_augroup_name(augroup)
--   vim.api.nvim_create_autocmd({ "WinLeave", "BufLeave" }, {
--     group = group,
--     callback = function()
--       if vim.api.nvim_win_is_valid(win) then
--         vim.defer_fn(function()
--           if vim.api.nvim_win_is_valid(win) then
--             vim.api.nvim_set_current_win(win)
--           end
--         end, 10)
--       end
--     end,
--   })
-- end

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

    -- apply syntax highlights to all entries
    QfbookmarkMarkVisual.apply_entry_highlights(main_buf, opts_popup.contents)

    -- re-apply highlights after dd deletes lines
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
        QfbookmarkMarkVisual.apply_entry_highlights(main_buf, remaining)
      end,
    })

    --- PREVIEW WIN
    local main_win_cfg = vim.api.nvim_win_get_config(main_win)

    local buf_preview, win_preview = QfbookmarkUIPopup.mark_preview(main_win_cfg, opts_popup.win_opts.wincfg.width)
    if not win_preview or not buf_preview then
      return
    end

    M.window.mark_preview.buf = buf_preview
    M.window.mark_preview.win = win_preview

    -- wire up CursorMoved preview with the new harpoon_map
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

    -- local keymap_harpoon = Config.keymaps.actions.mark_win_open
    QfbookmarkUIKeymaps.setup_keymap_mark(opts_popup, main_buf, cb_wrapper)

    -- bind the toggle key to close the popup
    -- local keys = {}
    -- if type(keymap_harpoon) == "string" then
    --   keys[#keys + 1] = keymap_harpoon
    -- elseif type(keymap_harpoon) == "table" then
    --   for _, x in pairs(keymap_harpoon) do
    --     keys[#keys + 1] = x
    --   end
    -- end
    --
    -- if #keys > 0 then
    --   for _, key in pairs(keys) do
    --     vim.keymap.set("n", key, function()
    --       QfbookmarkUIPopup.close_win(win, preview_win)
    --       QfbookmarkUIPopup.clean_up(M.window.mark_win)
    --     end, { buffer = buf, nowait = true })
    --   end
    -- end
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
}

---@param for_what "mark" | "buffer" | "save"
---@param opts_popup QfBookUiPopupCfg
---@param is_editable? boolean
---@param cb? function | nil
function M.build_popup(for_what, opts_popup, cb, is_editable)
  cb = cb or nil
  is_editable = is_editable or false

  ---Clean up leftover windows and buffers before opening the popup.
  M.window = QfbookmarkUIUtils.clean_up(M.window)
  if opts_popup.popup then
    opts_popup.popup = nil
  end

  -- Call popup open window
  if for_what == "buffer" then
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
