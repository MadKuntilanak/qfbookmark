local Config = require("qfbookmark.config").defaults

local QFbookmarkPathUtils = require "qfbookmark.path.utils"
local QfbookmarkUIUtils = require "qfbookmark.ui.utils"
local QfbookmarkMarkVisual = require "qfbookmark.visual"

local M = {}

---@param main_buf integer
---@param buf_preview integer
---@param target_path string
---@param is_loc? boolean
local function update_save_footer(main_buf, buf_preview, target_path, is_loc)
  is_loc = is_loc or false
  local getlines = vim.api.nvim_buf_get_lines(main_buf, 0, -1, false)

  if not target_path then
    return
  end

  local fn_opts = QFbookmarkPathUtils.reformat_filename_json(table.concat(getlines, " "), target_path, is_loc)
  if not fn_opts then
    return
  end

  local target_dir = vim.split(fn_opts.full_path, "/")
  local part2 = target_dir[#target_dir - 1] or ""

  local type_label = fn_opts.is_loc and "LocList" or "QuickFix"

  -- Truncate long directory hashes to keep the footer readable
  local dir_display = #part2 > 32 and (part2:sub(1, 14) .. "…" .. part2:sub(-10)) or part2

  local footer_text = {
    type_label,
    "",
    "  filename   " .. fn_opts.filename,
    "  directory  " .. dir_display,
  }
  vim.api.nvim_buf_set_lines(buf_preview, 0, -1, false, footer_text)

  QfbookmarkMarkVisual.apply_save_highlights(buf_preview, fn_opts, type_label, dir_display)
end

---@param win_opts WinCfg
---@param lines? table
---@return integer, integer
function M.new_open(win_opts, lines)
  lines = lines or {}

  local opts = win_opts

  if not opts.buf then
    opts.buf = vim.api.nvim_create_buf(false, true)
  end

  vim.api.nvim_buf_set_lines(opts.buf, 0, -1, false, lines)

  local win = vim.api.nvim_open_win(opts.buf, opts.enter, opts.wincfg)
  return opts.buf, win
end

---@param path string
---@return table<string> | nil
local function read_file(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local t = {}
  for line in f:lines() do
    t[#t + 1] = line
  end
  f:close()
  return t
end

---@param filename string
---@param bufnr? integer
local function load_content(filename, bufnr)
  -- Handle fugitive virtual buffers
  if filename and filename:match "^fugitive://" then
    if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
      return { "⚠ Unable to load fugitive buffer:\n" .. filename }
    end

    local ok, lines = pcall(vim.api.nvim_buf_get_lines, bufnr, 0, -1, false)
    if ok and lines and #lines > 0 then
      return lines
    end
  end

  if not bufnr then
    local real = read_file(filename)
    if real then
      return real
    end
    return { "⚠ Unable to load content. Buffer not found." }
  end

  local bt = vim.bo[bufnr].buftype

  -- Virtual buffer (git, octo, lsp, prompt, terminal, etc)
  if bt ~= "" and bt ~= "file" then
    return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  end

  -- Try read file from disk
  local real = read_file(filename)
  if real then
    return real
  end

  -- Fallback if path invalid
  return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
end

--- Update the preview window based on the current cursor line.
--- Resolves the harpoon value from harpoon_map instead of parsing raw lines.
---@param opts_popup QfBookUiPopupCfg
---@param buf integer
---@param win integer
local function update_mark_preview(opts_popup, win, buf)
  local cur_line_nr = vim.api.nvim_win_get_cursor(0)[1]
  local harpoon_val = opts_popup.content_map[cur_line_nr]

  if not harpoon_val then
    return
  end

  if not vim.api.nvim_win_is_valid(win) then
    return
  end

  local filename, col, line, bufnr

  for _, m in pairs(opts_popup.contents) do
    if m.harpoon == harpoon_val then
      filename = m.filename
      col = m.col or 0
      line = m.line or 1
      bufnr = m.bufnr
      break
    end
  end

  if not filename or not bufnr then
    return
  end

  local content
  local buffer_status = QfbookmarkUIUtils.get_buffer_status(bufnr)

  if filename:match "^fugitive://" then
    local new_bufnr = vim.fn.bufnr(filename)

    if new_bufnr == -1 then
      new_bufnr = vim.fn.bufadd(filename)
    end

    if new_bufnr ~= -1 then
      if not vim.api.nvim_buf_is_loaded(new_bufnr) then
        vim.api.nvim_buf_call(new_bufnr, function()
          vim.cmd("doautocmd BufReadCmd " .. vim.fn.fnameescape(filename))
          vim.api.nvim_set_option_value("filetype", "git", { buf = new_bufnr })
        end)
      end

      bufnr = new_bufnr
      for _, m in pairs(opts_popup.contents) do
        if m.filename == filename then
          m.bufnr = new_bufnr
        end
      end
      content = load_content(filename, bufnr)
    end
    content = load_content(filename, bufnr)
  elseif buffer_status == "alive" then
    content = load_content(filename, bufnr)
  elseif buffer_status == "hidden" or buffer_status == "gone" then
    content = read_file(filename)
  end

  if content then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)

    local buf_line_count = vim.api.nvim_buf_line_count(buf)
    line = math.max(1, math.min(line, buf_line_count))
    col = math.max(0, col)
    if line and col then
      vim.api.nvim_win_set_cursor(win, { line, col })
    end

    local ft
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
      local ok, result = pcall(vim.filetype.match, { buf = bufnr })
      if ok then
        ft = result
      end
    end

    -- Fallback filetype for fugitive buffers
    if not ft and filename and filename:match "^fugitive://" then
      ft = bufnr and vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].filetype or "git"
    end

    if ft then
      vim.api.nvim_set_option_value("filetype", ft, { buf = buf })
      pcall(vim.treesitter.start, buf, ft)

      vim.api.nvim_set_option_value("foldenable", false, { win = win, scope = "local" })
      vim.api.nvim_set_option_value("foldmethod", "manual", { win = win, scope = "local" })
      vim.api.nvim_set_option_value("cursorline", true, { win = win, scope = "local" })
      vim.api.nvim_set_option_value("number", true, { win = win, scope = "local" })
      vim.api.nvim_set_option_value(
        "winhighlight",
        "FloatBorder:QFBookmarkPreviewFloatBorder,"
          .. "FloatTitle:QFBookmarkPreviewFloatTitle,"
          -- .. "Cursor:QFBookmarkPreviewFloatCursor,"
          .. "CursorLine:QFBookmarkPreviewCursorline,"
          .. "CursorLineNr:QFBookmarkPreviewFloatCursorLineNr,",

        { win = win, scope = "local" }
      )
    end
  else
    -- Fallback if content cannot be loaded
    content = { "⚠ Unable to load this buffer or file" }
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)
  end

  local cfg = vim.api.nvim_win_get_config(win)
  cfg.title = QfbookmarkUIUtils.format_title("🔍 " .. vim.fn.fnamemodify(filename, ":~:."))
  vim.api.nvim_win_set_config(win, cfg)
end

--- Setup CursorMoved autocmd to update the preview window on navigation.
---@param opts_popup QfBookUiPopupCfg
---@param win_preview integer
---@param buf_preview integer
function M.setup_mark_preview_contents(opts_popup, main_buf, win_preview, buf_preview)
  -- But immediately show preview for the first entry when the popup opens
  vim.schedule(function()
    if vim.api.nvim_win_is_valid(win_preview) then
      update_mark_preview(opts_popup, win_preview, buf_preview)
    end
  end)

  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = main_buf,
    callback = function()
      update_mark_preview(opts_popup, win_preview, buf_preview)
    end,
  })
end

---@param main_wincfg vim.api.keyset.win_config
---@param width integer
---@param height? integer
---@return integer | nil, integer | nil
function M.mark_preview(main_wincfg, width, height)
  local editor = QfbookmarkUIUtils.get_editor_size()

  height = height or math.max(1, math.floor(editor.height * 2 / 3.5))
  width = math.max(editor.width - math.floor(width * 2) + QfbookmarkUIUtils.PADDING_PREVIEW + 10, 50)

  local _col = main_wincfg.col - width - QfbookmarkUIUtils.PADDING_PREVIEW - 12
  local _col_minus = main_wincfg.col + main_wincfg.width + QfbookmarkUIUtils.PADDING_PREVIEW
  local col = Config.window.mark.anchor == "NW" and _col_minus or _col
  local row = main_wincfg.row

  ---@type WinCfg
  local wincfg = {
    buf = vim.api.nvim_create_buf(false, true),
    enter = false,
    wincfg = {
      relative = "editor",
      width = width,
      height = height,
      row = row,
      col = col,
      style = "minimal",
      border = "rounded",
      title = QfbookmarkUIUtils.format_title "Preview",
      title_pos = "center",
      focusable = false,
      noautocmd = true,
    },
  }

  local buf_preview, win_preview = M.new_open(wincfg, { "" })

  vim.api.nvim_set_option_value("winblend", 0, { win = win_preview })
  vim.api.nvim_set_option_value(
    "winhighlight",
    "NormalFloat:QFBookmarkNormalFloat,FloatBorder:QFBookmarkFloatBorder,",
    { win = win_preview }
  )

  return buf_preview, win_preview
end

---@param opts_popup QfBookUiPopupCfg
---@param main_cfg vim.api.keyset.win_config_ret
---@return integer, integer
function M.save_footer(opts_popup, main_cfg)
  local row = main_cfg.row + main_cfg.height + QfbookmarkUIUtils.PADDING_PREVIEW
  local footer_col = main_cfg.col

  local win_buf = vim.api.nvim_create_buf(false, true)

  local win_config = {
    buf = win_buf,
    enter = false,
    wincfg = {
      style = "minimal",
      relative = "editor",
      row = row,
      col = footer_col,
      width = main_cfg.width,
      height = 5,
      border = "rounded",
      focusable = false,
      noautocmd = true,
    },
  }

  local buf_preview, win_preview = M.new_open(win_config, {})

  vim.api.nvim_set_option_value("winblend", 0, { win = win_preview })
  vim.api.nvim_set_option_value("winhighlight", "FloatBorder:QFBookmarkFloatBorder", { win = win_preview })

  vim.api.nvim_buf_attach(opts_popup.popup.buf, false, {
    on_lines = function()
      vim.schedule(function()
        if opts_popup.save.target_path then
          update_save_footer(opts_popup.popup.buf, buf_preview, opts_popup.save.target_path, opts_popup.save.is_loc)
        end
      end)
    end,
  })

  return buf_preview, win_preview
end

return M
