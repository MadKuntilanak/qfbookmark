local Config = require("qfbookmark.config").defaults

local QFbookmarkPathUtils = require "qfbookmark.path.utils"
local QfbookmarkUIUtils = require "qfbookmark.ui.utils"
local QfbookmarkUtils = require "qfbookmark.utils"
local QfbookmarkMarkVisual = require "qfbookmark.visual"

local M = {}

---@param opts_popup QFBookmarkUiPopupCfg
---@param buf_preview integer
local function update_save_footer(opts_popup, buf_preview)
  local is_loc = opts_popup.save.is_loc
  local target_path = opts_popup.save.target_path
  local main_buf = opts_popup.popup.buf

  if not QfbookmarkUtils.is_valid(main_buf) then
    return
  end

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

  QfbookmarkMarkVisual.apply_save_highlights(
    buf_preview,
    fn_opts,
    type_label,
    dir_display,
    opts_popup.popup.preview.namespace
  )
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
    if not QfbookmarkUtils.is_valid(bufnr) then
      return { "⚠ Unable to load fugitive buffer:\n" .. filename }
    end

    local ok, lines = pcall(vim.api.nvim_buf_get_lines, bufnr, 0, -1, false)
    if ok and lines and #lines > 0 then
      return lines
    end
  end

  if not bufnr then
    -- local real = QfbookmarkUtils.resolve_bufnr(filename)
    -- if real then
    --   return real
    -- end
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

---@param opts_popup QFBookmarkUiPopupCfg
---@param cur_line_nr integer
local function get_data_from_opts_popup(opts_popup, cur_line_nr)
  local harpoon_val

  cur_line_nr = cur_line_nr or vim.api.nvim_win_get_cursor(0)[1]

  for _, x in pairs(opts_popup.content_map) do
    if x.start_line == cur_line_nr then
      harpoon_val = x.hval
    end
  end

  if not harpoon_val then
    return
  end

  local entry = QfbookmarkUIUtils.get_entry_at_line(opts_popup.content_map, cur_line_nr)
  if not entry then
    return
  end

  local filename, col, line, bufnr

  for _, _entry in pairs(opts_popup.content_map) do
    local m = _entry.mark
    if m.harpoon == harpoon_val then
      filename = m.filename
      col = m.col or 0
      line = m.line or 1
      bufnr = m.bufnr
      break
    end
  end
  return { filename = filename, col = col, line = line, bufnr = bufnr }
end

--- Update the preview window based on the current cursor line.
--- Resolves the harpoon value from harpoon_map instead of parsing raw lines.
---@param opts_popup QFBookmarkUiPopupCfg
---@param buf integer
---@param win integer
---@param is_note_mark boolean
local function update_mark_preview(opts_popup, win, buf, is_note_mark)
  if not vim.api.nvim_win_is_valid(win) then
    return
  end

  local filename, col, line, bufnr

  local cur_line_nr = vim.api.nvim_win_get_cursor(0)[1]
  if not is_note_mark then
    local opts = get_data_from_opts_popup(opts_popup, cur_line_nr)
    if not opts then
      return
    end
    filename = opts.filename
    col = opts.col
    line = opts.line
    bufnr = opts.bufnr
  else
    bufnr = opts_popup.content_map[1].mark.bufnr
    line = opts_popup.content_map[1].mark.line
    col = opts_popup.content_map[1].mark.col
    filename = opts_popup.content_map[1].mark.filename
  end

  if not filename or not bufnr then
    return
  end

  ---@type string[]
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
      for _, _entry in pairs(opts_popup.content_map) do
        local m = _entry.mark
        if m.filename == filename then
          m.bufnr = new_bufnr
        end
      end
    end

    content = load_content(filename, bufnr)
  elseif buffer_status == "alive" then
    content = load_content(filename, bufnr)
  elseif buffer_status == "hidden" or buffer_status == "gone" then
    local __content = read_file(filename)
    if not __content then
      content = {
        string.format("⚠ Failed to load '%s'.", vim.fs.basename(filename)),
      }
    else
      content = __content
    end
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

    if QfbookmarkUtils.is_valid(bufnr) then
      local ok, result = pcall(vim.filetype.match, { buf = bufnr })
      if ok then
        ft = result
      end
    end

    -- fallback: resolve filetype from filename when bufnr is invalid
    -- (e.g. after `dM` deletes all buffers — status becomes "gone")
    if not ft and filename then
      local ok, result = pcall(vim.filetype.match, { filename = filename })
      if ok then
        ft = result
      end
    end

    if not ft and filename and filename:match "^fugitive://" then
      ft = QfbookmarkUtils.is_valid(bufnr) and vim.bo[bufnr].filetype or "git"
    end

    if ft then
      vim.api.nvim_set_option_value("filetype", ft, { buf = buf })

      -- Stop any existing highlighter before starting fresh,
      -- avoids stale treesitter state when the previous source
      -- buffer no longer exists
      pcall(vim.treesitter.stop, buf)
      pcall(vim.treesitter.start, buf, ft)

      vim.api.nvim_set_option_value("foldenable", false, { win = win, scope = "local" })
      vim.api.nvim_set_option_value("foldmethod", "manual", { win = win, scope = "local" })
      vim.api.nvim_set_option_value("cursorline", true, { win = win, scope = "local" })
      vim.api.nvim_set_option_value("number", true, { win = win, scope = "local" })
      vim.api.nvim_set_option_value(
        "winhighlight",
        "FloatBorder:QFBookmarkPreviewFloatBorder,"
          .. "FloatTitle:QFBookmarkPreviewFloatTitle,"
          .. "CursorLine:QFBookmarkPreviewCursorline,"
          .. "CursorLineNr:QFBookmarkPreviewFloatCursorLineNr,",
        { win = win, scope = "local" }
      )
    else
      -- nothing resolved: clear stale highlighter so the preview
      -- doesn't keep showing colors from the previous entry
      pcall(vim.treesitter.stop, buf)
      vim.api.nvim_set_option_value("filetype", "", { buf = buf })
    end
  else
    content = { "⚠ Unable to load this buffer or file" }
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)
    pcall(vim.treesitter.stop, buf)
  end
end

--- Setup CursorMoved autocmd to update the preview window on navigation.
---@param opts_popup QFBookmarkUiPopupCfg
---@param win_preview integer
---@param buf_preview integer
---@param is_note_mark? boolean
function M.setup_mark_preview_contents(opts_popup, main_buf, win_preview, buf_preview, is_note_mark)
  is_note_mark = is_note_mark or false

  -- But immediately show preview for the first entry when the popup opens
  vim.schedule(function()
    if vim.api.nvim_win_is_valid(win_preview) then
      update_mark_preview(opts_popup, win_preview, buf_preview, is_note_mark)
    end
  end)

  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = main_buf,
    callback = function()
      update_mark_preview(opts_popup, win_preview, buf_preview, is_note_mark)
    end,
  })
end

---@param main_wincfg vim.api.keyset.win_config
---@param width integer
---@param height? integer
---@param opts? {fullscreen: boolean}
---@return integer | nil, integer | nil
function M.mark_preview(main_wincfg, width, height, opts)
  opts = opts or {}
  local editor = QfbookmarkUIUtils.get_editor_size()

  local is_fullscreen = opts.fullscreen or false

  local col, row
  if is_fullscreen then
    height = editor.height
    width = math.max(editor.width - math.floor(width * 2) + QfbookmarkUIUtils.PADDING_PREVIEW + 10, 50)

    local _col = main_wincfg.col - width - QfbookmarkUIUtils.PADDING_PREVIEW
    local _col_minus = main_wincfg.col + main_wincfg.width + QfbookmarkUIUtils.PADDING_PREVIEW
    col = Config.window.mark.anchor == "NW" and _col_minus or _col
    row = main_wincfg.row - 10
  else
    height = math.max(1, math.floor(editor.height * 2 / 3.5))
    width = math.max(editor.width - math.floor(width * 2) + QfbookmarkUIUtils.PADDING_PREVIEW + 10, 50)

    local _col = main_wincfg.col - width - QfbookmarkUIUtils.PADDING_PREVIEW
    local _col_minus = main_wincfg.col + main_wincfg.width + QfbookmarkUIUtils.PADDING_PREVIEW
    col = Config.window.mark.anchor == "NW" and _col_minus or _col
    row = main_wincfg.row
  end

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

---@param opts_popup QFBookmarkUiPopupCfg
---@param main_wincfg vim.api.keyset.win_config
---@param width integer
---@param height? integer
---@return integer | nil, integer | nil
function M.mark_note_preview(opts_popup, main_wincfg, width, height)
  height = math.min(10, math.floor(main_wincfg.height * 2)) + QfbookmarkUIUtils.PADDING_PREVIEW
  width = main_wincfg.width

  local col = main_wincfg.col
  local row = main_wincfg.row - height - QfbookmarkUIUtils.PADDING_PREVIEW

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
    "NormalFloat:QFBookmarkNormalFloat,FloatBorder:QFBookmarkFloatBorder,FloatTitle:QFBookmarkFloatTitle",
    { win = win_preview }
  )

  vim.bo[buf_preview].filetype = "markdown"

  local ctx = vim.api.nvim_buf_get_lines(
    opts_popup._opts.bufnr,
    opts_popup._opts.start_line,
    opts_popup._opts.end_line + 1,
    false
  )

  ---@type string[]
  local content = {}

  if #ctx > 0 then
    vim.list_extend(content, {
      "",
      "```" .. vim.bo[opts_popup._opts.bufnr].filetype,
    })

    vim.list_extend(content, ctx)
    table.insert(content, "```")
  end

  vim.api.nvim_buf_set_lines(buf_preview, 0, -1, false, content)

  return buf_preview, win_preview
end

---@param opts_popup QFBookmarkUiPopupCfg
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
          -- update_save_footer(opts_popup, buf_preview, opts_popup.save.target_path, opts_popup.save.is_loc)
          update_save_footer(opts_popup, buf_preview)
        end
      end)
    end,
  })

  return buf_preview, win_preview
end

---@param prefix_title string
---@param keys QFBookKeys[]
function M.show_keymap_helps(prefix_title, keys)
  local editor = QfbookmarkUIUtils.get_editor_size()

  local function format_key(x)
    if not x.keys then
      return nil
    end
    if type(x.keys) == "string" then
      return x.keys
    end
    local cs = {}
    for _, y in ipairs(x.keys) do
      cs[#cs + 1] = y
    end
    return table.concat(cs, " ")
  end

  local max_key_width = 1
  for _, x in ipairs(keys) do
    local key = format_key(x)
    if key then
      max_key_width = math.max(max_key_width, vim.fn.strdisplaywidth(key))
    end
  end

  local content = {}
  for _, x in ipairs(keys) do
    local key = format_key(x)
    if key then
      local pad_needed = max_key_width - vim.fn.strdisplaywidth(key)
      content[#content + 1] = key .. string.rep(" ", pad_needed + 4) .. (x.desc or "")
    end
  end

  local height = math.min(#content, math.floor(editor.height / 2)) + QfbookmarkUIUtils.PADDING_PREVIEW
  local width = math.floor(editor.width / 2)
  local col, row = QfbookmarkUIUtils.get_center_col_row(height, width)
  local title_str = "(" .. prefix_title .. ") show keymap shortcuts"

  ---@type WinCfg
  local wincfg = {
    buf = vim.api.nvim_create_buf(false, true),
    enter = true,
    wincfg = {
      relative = "editor",
      width = width,
      height = height,
      row = row,
      col = col,
      style = "minimal",
      border = "rounded",
      title = QfbookmarkUIUtils.format_title(title_str),
      title_pos = "center",
      focusable = true,
      noautocmd = true,
    },
  }

  local main_buf, main_win = M.new_open(wincfg, {})
  vim.api.nvim_buf_set_lines(main_buf, 0, -1, false, content)
  vim.bo[main_buf].filetype = "qfbookmark_help"
  vim.wo[main_win].winhighlight = "NormalFloat:Normal,FloatFooter:QFBookmarkFloatFooter,FloatTitle:QFBookmarkFloatTitle"

  local hl_ns = vim.api.nvim_create_namespace "qfbookmark_help_hl"
  for i, x in ipairs(keys) do
    local key = format_key(x)
    if key then
      local key_len = vim.fn.strdisplaywidth(key)
      vim.api.nvim_buf_set_extmark(main_buf, hl_ns, i - 1, 0, {
        end_col = key_len or 1,
        hl_group = "@markup.raw.markdown_inline",
      })
    end
  end

  vim.api.nvim_set_option_value("readonly", true, { buf = main_buf })
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = main_buf })
  vim.api.nvim_set_option_value("modifiable", false, { buf = main_buf })

  local opts = { buffer = main_buf, nowait = true, silent = true }
  local function close()
    if vim.api.nvim_win_is_valid(main_win) then
      vim.api.nvim_win_close(main_win, true)
    end
  end
  vim.keymap.set("n", "<Esc>", close, opts)
  vim.keymap.set("n", "q", close, opts)
end

return M
