local QfbookmarkNav = require "qfbookmark.nav"
local QFbookmarkPathUtils = require "qfbookmark.path.utils"
local QfbookmarkUtils = require "qfbookmark.utils"
local Config = require("qfbookmark.config").defaults

local M = {}
local PADDING = 2

---@alias WinSizeCfg { row: integer, col: integer, height: integer, width: integer, title: string, title_pos: string, buf?: integer}
---@alias WinCfg { buf: integer, enter: boolean, wincfg: vim.api.keyset.win_config }
---@alias QfBookUiWinCfg { primary: QfBookUiWinPopup, secondary: QfBookUiWinPopup }

---@type QfBookUIWin
M.window = {
  save_win = {
    augroup = "WinSavePopup",
    win = nil,
    buf = nil,
  },
  save_footer = {
    augroup = "WinMarkSaveFooter",
    win = nil,
    buf = nil,
  },
  mark_win = {
    augroup = "WinMarkPopup",
    win = nil,
    buf = nil,
  },
  footer_win = {
    augroup = "WinMarkFooter",
    win = nil,
    buf = nil,
  },
}

---@param title string
local function format_title(title)
  return " " .. title .. " "
end

local function get_editor_size()
  local ui = vim.api.nvim_list_uis()[1]
  return {
    width = ui.width,
    height = ui.height,
  }
end

---@param is_input? boolean
---@param lines? table
---@return WinSizeCfg
local function get_win_width(is_input, lines)
  is_input = is_input or false

  lines = lines or vim.api.nvim_get_option_value("lines", { scope = "global" })
  local columns = vim.api.nvim_get_option_value("columns", { scope = "global" })

  local win_height = math.ceil((lines / 2) - 8)
  local win_width = math.ceil(columns / 2)
  local row_base = 2

  -- The `is_input` flag is used for `input_popup`,
  -- and `input_popup` requires a small width.
  if is_input then
    row_base = 3
    win_height = 1
    win_width = win_width - 5
  end

  local ui = vim.api.nvim_list_uis()[1]
  local row = math.floor((ui.height - win_height) / row_base)
  local col = math.floor((ui.width - win_width) / 2)

  return { row = row, col = col, width = win_width, height = win_height }
end

---@param tbl_contents table[]
---@param is_harpoon? boolean
---@param default_win_width? number
---@param max_width? number
---@return number
local function get_max_width_contents(tbl_contents, is_harpoon, default_win_width, max_width)
  is_harpoon = is_harpoon or false
  default_win_width = default_win_width or 50
  max_width = max_width or 70 -- safety agar tidak kelebaran layar

  local width = default_win_width

  for _, item_content in ipairs(tbl_contents) do
    local item = ""

    if is_harpoon then
      local t = type(item_content) == "table" and item_content.harpoon or ""
      item = type(t) == "string" and t or ""
    else
      item = type(item_content) == "string" and item_content or ""
    end

    local len = vim.fn.strdisplaywidth(item)

    if is_harpoon then
      len = len + 10
    end

    width = math.max(width, len)
  end

  -- clamp biar tidak keluar layar
  if width > max_width then
    width = max_width
  end

  return width
end

---@param opts table
---@param second_buf integer
---@param target_path string
---@param is_loc? boolean
local function update_preview(opts, second_buf, target_path, is_loc)
  is_loc = is_loc or false
  local getlines = vim.api.nvim_buf_get_lines(second_buf, 0, -1, false)

  if not target_path then
    return
  end

  local fn_opts = QFbookmarkPathUtils.reformat_filename_json(table.concat(getlines, " "), target_path, is_loc)
  if not fn_opts then
    return
  end

  local target_dir = vim.split(fn_opts.full_path, "/")
  local part2 = target_dir[#target_dir - 1]

  local title_qf = fn_opts.is_loc and "LocList" or "QuickFix"

  local footer_text = {
    title_qf,
    "",
    "T.Fn: " .. fn_opts.filename,
    "T.Dir: " .. part2,
  }
  vim.api.nvim_buf_set_lines(opts.buf, 0, -1, false, footer_text)
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
  if not bufnr then
    local real = read_file(filename)
    if real then
      return real
    end
    return { "⚠ Tidak dapat memuat konten. Buffer tidak ditemukan." }
  end

  local bt = vim.bo[bufnr].buftype

  -- buffer virtual (git, octo, lsp, prompt, terminal, dsb)
  if bt ~= "" and bt ~= "file" then
    return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  end

  -- try read file from hardisk
  local real = read_file(filename)
  if real then
    return real
  end

  -- fallback if path invalid
  return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
end

---@param mark_lists QFbookBufferMarkEntry[]
---@param opts {buf: integer}
---@param secondary_win integer
local function update_preview_harpoon(mark_lists, opts, secondary_win)
  local getlines = vim.api.nvim_get_current_line()
  getlines = QfbookmarkUtils.remove_idx_m_harpoon(getlines)

  local filename, col, line, bufnr
  for _, m in pairs(mark_lists) do
    if m.harpoon == getlines then
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
  local buffer_status = QfbookmarkUtils.get_buffer_status(bufnr)

  if buffer_status == "alive" then
    content = load_content(filename, bufnr)
  elseif buffer_status == "hidden" or buffer_status == "gone" then
    content = read_file(filename)
  end

  if content then
    vim.api.nvim_buf_set_lines(opts.buf, 0, -1, false, content)

    local buf_line_count = vim.api.nvim_buf_line_count(opts.buf)
    line = math.max(1, math.min(line, buf_line_count))
    col = math.max(0, col) -- minimal 0
    if line and col then
      vim.api.nvim_win_set_cursor(secondary_win, { line, col })
    end

    local ft
    if vim.api.nvim_buf_is_valid(bufnr) then
      ft = vim.filetype.match { buf = bufnr }
    end

    if ft then
      vim.api.nvim_set_option_value("filetype", ft, { buf = opts.buf })
      pcall(vim.treesitter.start, opts.buf, ft)

      vim.api.nvim_set_option_value("foldenable", false, { win = secondary_win, scope = "local" })
      vim.api.nvim_set_option_value("foldmethod", "manual", { win = secondary_win, scope = "local" })
      vim.api.nvim_set_option_value("cursorline", true, { win = secondary_win, scope = "local" })
      vim.api.nvim_set_option_value("number", true, { win = secondary_win, scope = "local" })
      vim.api.nvim_set_option_value(
        "winhighlight",
        "CursorLine:QFBookmarkPreviewCursorline,"
          .. "FloatTitle:QFBookmarkPreviewFloatTitle,"
          .. "Cursor:QFBookmarkPreviewFloatCursor,",

        { win = secondary_win, scope = "local" }
      )
    end
  else
    -- Fallback if content cannot be loaded
    content = { "⚠ Unable to load this buffer or file" }
    vim.api.nvim_buf_set_lines(opts.buf, 0, -1, false, content)
  end

  local cfg = vim.api.nvim_win_get_config(secondary_win)
  cfg.title = format_title("🔍 " .. vim.fn.fnamemodify(filename, ":~:."))

  vim.api.nvim_win_set_config(secondary_win, cfg)
end

---@param wincfg WinCfg
---@param lines? table
---@param second_buf? integer
---@param target_path? string
---@param is_harpoon? boolean
---@param is_two_win? boolean
---@param is_loc? boolean
---@return { win: integer, buf: integer}
local function open_win(wincfg, lines, second_buf, is_two_win, is_harpoon, target_path, is_loc)
  is_two_win = is_two_win or false
  is_harpoon = is_harpoon or false
  is_loc = is_loc or false
  target_path = target_path or nil
  lines = lines or {}

  local opts = wincfg

  if not opts.buf then
    opts.buf = vim.api.nvim_create_buf(false, true)
  end

  if #lines > 0 or second_buf then
    if is_two_win and second_buf then
      if not is_harpoon then
        vim.api.nvim_buf_attach(second_buf, false, {
          on_lines = function()
            vim.schedule(function()
              if target_path then
                update_preview(opts, second_buf, target_path, is_loc)
              end
            end)
          end,
        })
      end
    else
      vim.api.nvim_buf_set_lines(opts.buf, 0, -1, false, lines)
    end
  end

  local win = vim.api.nvim_open_win(opts.buf, opts.enter, opts.wincfg)

  return { win = win, buf = opts.buf }
end

---@param opts_win QfBookUiWinPopup
local function clean_up(opts_win)
  if type(opts_win) == "table" then
    for _, v in pairs(opts_win) do
      if type(v) == "table" then
        if v.augroup then
          local augroup = Config.sign_group .. v.augroup
          QfbookmarkUtils.clear_autocmd_group(augroup)
        end
        v.buf = nil
        v.win = nil
      end
    end
  else
    if opts_win.augroup then
      local augroup = Config.sign_group .. opts_win.augroup
      QfbookmarkUtils.clear_autocmd_group(augroup)
    end
    opts_win.buf = nil
    opts_win.win = nil
  end
end

---@param main_win integer
---@param secondary_win? integer
local function close_win(main_win, secondary_win)
  secondary_win = secondary_win or nil

  if main_win then
    if vim.api.nvim_win_is_valid(main_win) then
      vim.api.nvim_win_close(main_win, true)
    end
  end

  if secondary_win then
    if vim.api.nvim_win_is_valid(secondary_win) then
      vim.api.nvim_win_close(secondary_win, true)
    end
  end
end

---@param mark_lists QFbookBufferMarkEntry[]
---@param win_popup QfBookUiWinCfg
---@param buf integer
---@param cb? function
---@param is_harpoon? boolean
---@param is_buffers? boolean
local function setup_keymaps(mark_lists, win_popup, buf, cb, is_harpoon, is_buffers)
  cb = cb or nil
  is_harpoon = is_harpoon or false
  is_buffers = is_buffers or false

  local function _exit_fun_mapping()
    if is_harpoon then
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false) -- get all lines
      close_win(win_popup.primary.win, win_popup.secondary.win)

      vim.schedule(function()
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", true)
        if #lines == 1 and #lines[1] == 0 then
          lines = {}
        end

        if cb then
          cb(lines)
        end
        clean_up(win_popup)
      end)
    else
      close_win(win_popup.primary.win, win_popup.secondary.win)
      clean_up(win_popup)
    end

    vim.cmd.stopinsert()
  end

  local function save_input()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local input = lines[1] or ""
    close_win(win_popup.primary.win, win_popup.secondary.win)

    vim.schedule(function()
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", true)
      if input == "" then
        return
      end

      if cb then
        cb(input)
      end
      clean_up(win_popup)
    end)
  end

  ---@param key string
  local function press_normal_key(key, is_with_bracket)
    is_with_bracket = is_with_bracket or false

    local pkey = function()
      if is_with_bracket then
        return "<" .. key .. ">"
      end
      return key
    end

    if QfbookmarkUtils.is_buf_readonly(buf) then
      vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
      vim.api.nvim_set_option_value("readonly", false, { buf = buf })
    end

    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(pkey(), true, false, true), "n", true)
  end

  -- ---@param key string
  -- local function press_norm_key(key)
  --   if QfbookmarkUtils.is_buf_readonly(buf) then
  --     vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
  --     vim.api.nvim_set_option_value("readonly", false, { buf = buf })
  --   end
  --   vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(key, true, false, true), "n", true)
  -- end

  ---@param open_mode OpenMode
  local function setup_open_key(open_mode)
    local line_opts = QfbookmarkUtils.get_line_pos_col_buffer()
    close_win(win_popup.primary.win, win_popup.secondary.win)

    vim.schedule(function()
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", true)

      if is_harpoon then
        for _, m in pairs(mark_lists) do
          local line = QfbookmarkUtils.remove_idx_m_harpoon(line_opts.text)
          if m.harpoon == line then
            QfbookmarkNav.jump_to {
              filename = m.filename,
              col = m.col,
              line = m.line,
              mode_open = open_mode,
            }
          end
        end
      end

      if is_buffers then
        QfbookmarkNav.jump_to {
          filename = line_opts.text,
          col = line_opts.col,
          line = 0, -- force jump to last cursor position
          mode_open = open_mode,
        }
      end

      clean_up(win_popup)
    end)
  end

  ---@param scroll_mode "up" | "down"
  local function scroll_preview_window(scroll_mode)
    -- local function scroll_half_down(win)
    --   vim.api.nvim_win_call(win, function()
    --     vim.cmd "normal! <C-d>"
    --   end)
    -- end
    --
    -- local function scroll_half_up(win)
    --   vim.api.nvim_win_call(win, function()
    --     vim.cmd "normal! <C-u>"
    --   end)
    -- end

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
      scroll_up(win_popup.secondary.win)
    else
      scroll_down(win_popup.secondary.win)
    end
  end

  local _keys = {
    ["<CR>"] = {
      mode = { "n", "i" },
      fun = function()
        if is_harpoon or is_buffers then
          setup_open_key "default"
        else
          save_input()
        end
      end,
    },
    ["q"] = {
      mode = "n",
      fun = _exit_fun_mapping,
    },
    ["<Esc>"] = {
      mode = { "n", "i" },
      fun = _exit_fun_mapping,
    },
    ["<C-c>"] = {
      mode = "n",
      fun = _exit_fun_mapping,
    },
    ["<C-q>"] = {
      mode = "n",
      fun = _exit_fun_mapping,
    },

    ["<C-i>"] = {
      mode = "n",
      fun = _exit_fun_mapping,
    },
    ["<C-o>"] = {
      mode = "n",
      fun = _exit_fun_mapping,
    },
  }

  local nav_keys = {
    -- Navigation
    ["<c-p>"] = {
      mode = "n",
      fun = function()
        press_normal_key("up", true)
      end,
    },
    ["<c-k>"] = {
      mode = "n",
      fun = function()
        press_normal_key("up", true)
      end,
    },
    ["<c-n>"] = {
      mode = "n",
      fun = function()
        press_normal_key("down", true)
      end,
    },
    ["<c-j>"] = {
      mode = "n",
      fun = function()
        press_normal_key("down", true)
      end,
    },
    -- Mode open
    ["<c-y>"] = {
      mode = "n",
      fun = function()
        setup_open_key "buffer"
      end,
    },
    ["<c-s>"] = {
      mode = "n",
      fun = function()
        setup_open_key "split"
      end,
    },
    ["<c-v>"] = {
      mode = "n",
      fun = function()
        setup_open_key "vsplit"
      end,
    },
    ["<c-t>"] = {
      mode = "n",
      fun = function()
        setup_open_key "tabnew"
      end,
    },

    ["<c-u>"] = {
      mode = "n",
      fun = function()
        scroll_preview_window "up"
      end,
    },
    ["<c-d>"] = {
      mode = "n",
      fun = function()
        scroll_preview_window "down"
      end,
    },
  }

  if is_harpoon then
    nav_keys["dd"] = {
      mode = "n",
      fun = function()
        press_normal_key "dd"
      end,
    }

    for nav_key, nav_val in pairs(nav_keys) do
      if not _keys[nav_key] then
        _keys[nav_key] = nav_val
      end
    end
  end

  if is_buffers then
    nav_keys["gp"] = {
      mode = "n",
      fun = function()
        press_normal_key("up", true)
      end,
    }
    nav_keys["gn"] = {
      mode = "n",
      fun = function()
        press_normal_key("down", true)
      end,
    }

    nav_keys["dd"] = {
      mode = "n",
      fun = function()
        press_normal_key "dd"

        local line_opts = QfbookmarkUtils.get_line_pos_col_buffer()
        QfbookmarkUtils.buf_del(line_opts)
      end,
    }

    nav_keys["<c-d>"] = nil
    nav_keys["<c-u>"] = nil

    for nav_key, nav_val in pairs(nav_keys) do
      if not _keys[nav_key] then
        _keys[nav_key] = nav_val
      end
    end
  end

  for i, x in pairs(_keys) do
    vim.keymap.set(x.mode, i, x.fun, { buffer = buf, nowait = true })
  end
end

---@param qfpopup QfBookUiWinPopup
---@param lines table
---@param wincfg WinCfg
---@param is_editable? boolean
local function build_popup(qfpopup, wincfg, lines, is_editable)
  local buf, win

  is_editable = is_editable or false

  local winopts = open_win(wincfg, lines)
  qfpopup.buf = winopts.buf
  qfpopup.win = winopts.win

  buf = qfpopup.buf
  win = qfpopup.win

  if not win or not buf then
    return
  end

  -- keep the cursor locked inside the floating window
  local group = QfbookmarkUtils.create_augroup_name(qfpopup.augroup)
  vim.api.nvim_create_autocmd({ "WinLeave", "BufLeave" }, {
    group = group,
    callback = function()
      if vim.api.nvim_win_is_valid(win) then
        vim.defer_fn(function()
          if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_set_current_win(win)
          end
        end, 10)
      end
    end,
  })

  vim.api.nvim_set_option_value("filetype", "qfbookmark", { buf = buf })

  -- make buffer non-editable
  if not is_editable then
    vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
    vim.api.nvim_set_option_value("readonly", true, { buf = buf })
    vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
  end

  vim.api.nvim_set_option_value("cursorline", true, { win = win, scope = "local" })

  vim.api.nvim_set_option_value(
    "winhighlight",
    "FloatBorder:QFBookmarkFloatBorder,"
      .. "Normal:QFBookmarkFloatNormal,"
      .. "NormalFloat:QFBookmarkFloatNormal,"
      .. (is_editable and "FloatTitle:QFBookmarkFloatTitleBuffers," or "FloatTitle:QFBookmarkFloatTitle,")
      .. "FloatFooter:QFBookmarkFloatFooter,"
      .. "CursorLine:QFBookmarkFloatCursorLine,",
    { win = qfpopup.win, scope = "local" }
  )

  return win, buf
end

---@param opts_win QfBookUiWinPopup
---@param target_path string
---@param main_cfg table
---@param main_buf integer
---@param is_loc boolean
local function save_footer(opts_win, main_cfg, target_path, main_buf, is_loc)
  local win_opts = get_win_width(true)

  local footer_row = math.floor((win_opts.row + main_cfg.height) + 2)
  local footer_col = main_cfg.col

  local win_buf = vim.api.nvim_create_buf(false, true)

  local win_config = {
    buf = win_buf,
    enter = false,
    wincfg = {
      style = "minimal",
      relative = "editor",
      row = footer_row,
      col = footer_col,
      width = win_opts.width,
      height = 5,
      border = "rounded",
      focusable = false,
      noautocmd = true,
    },
  }

  local winopts = open_win(win_config, {}, main_buf, true, false, target_path, is_loc)

  vim.api.nvim_set_option_value("winblend", 0, { win = winopts.win })
  vim.api.nvim_set_option_value("winhighlight", "FloatBorder:QFBookmarkFloatBorder", { win = winopts.win })

  opts_win.buf = winopts.buf
  opts_win.win = winopts.win

  return opts_win.win, opts_win.buf
end

---@param title string
---@param target_path string
---@param cb function
---@param is_loc boolean
---@param for_what "save" | "rename"
local function input_popup(title, target_path, for_what, is_loc, cb)
  local lines = {}

  local is_input = true
  local win_opts = get_win_width(is_input)
  local win_buf = vim.api.nvim_create_buf(false, true)

  ---@type WinCfg
  local wincfg = {
    buf = win_buf,
    enter = true,
    wincfg = {
      relative = "editor",
      width = win_opts.width,
      height = win_opts.height,

      row = win_opts.row,
      col = win_opts.col,

      style = "minimal",
      border = "rounded",

      title = format_title(title),
      title_pos = "center",

      footer = " <C-q>/<Esc> Quit ",
      footer_pos = "center",
    },
  }

  local win, buf = build_popup(M.window.save_win, wincfg, lines, true)
  if not win or not buf then
    return
  end

  local main_win_cfg = vim.api.nvim_win_get_config(win)

  if for_what == "save" then
    local footer_win, footer_buf = save_footer(M.window.save_footer, main_win_cfg, target_path, buf, is_loc)
    if not footer_win or not footer_buf then
      return
    end
  end

  local qf_win_popup = {
    primary = M.window.save_win,
    secondary = M.window.save_footer,
  }

  setup_keymaps({}, qf_win_popup, buf, cb)

  -- Paksa start insert mode
  vim.api.nvim_set_current_win(win)
  vim.defer_fn(function()
    if vim.api.nvim_win_is_valid(win) then
      -- Paksa modifiable
      vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
      vim.cmd "startinsert!"
    end
  end, 10) -- Jeda 10ms
end

---@param qfpopup QfBookUiWinPopup
---@param secondary_buf integer
---@param main_win_cfg vim.api.keyset.win_config
local function harpoon_preview(qfpopup, secondary_buf, main_win_cfg, main_width)
  local win_buf = vim.api.nvim_create_buf(false, true)

  local win_opts = get_win_width()
  local padding = PADDING

  local height = math.max(1, math.floor(win_opts.height * 2))
  local preview_width = math.floor(main_width * 1.2)

  local row = main_win_cfg.row
  local col = main_win_cfg.col - preview_width - padding

  -- safety: prevent going off-screen
  if col < 0 then
    col = padding
  end

  ---@type WinCfg
  local wincfg = {
    buf = win_buf,
    enter = false,
    wincfg = {
      relative = "editor",
      width = preview_width,
      height = height,

      row = row,
      col = col,

      style = "minimal",
      border = "rounded",

      title = format_title "Preview Harpoon",
      title_pos = "center",

      focusable = false,
      noautocmd = true,
    },
  }
  local winopts = open_win(wincfg, {}, secondary_buf, true, true)

  vim.api.nvim_set_option_value("winblend", 0, { win = winopts.win })
  vim.api.nvim_set_option_value(
    "winhighlight",
    "NormalFloat:QFBookmarkFloatNormal," .. "FloatBorder:QFBookmarkFloatBorder,",
    { win = winopts.win }
  )

  qfpopup.buf = winopts.buf
  qfpopup.win = winopts.win

  return qfpopup.win, qfpopup.buf
end

---@param mark_lists QFbookBufferMarkEntry[]
---@param main_buf integer
---@param preview_buf integer
---@param preview_win integer
local function setup_harpoon_preview(mark_lists, main_buf, preview_buf, preview_win)
  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = main_buf,
    callback = function()
      update_preview_harpoon(mark_lists, { buf = preview_buf }, preview_win)
    end,
  })
end

---@param mark_lists QFbookBufferMarkEntry[]
---@param keymap_harpoon string|string[]
---@param harpoon_lines table
---@param cb function
local function mark_harpoon_popup(mark_lists, keymap_harpoon, harpoon_lines, cb)
  local win_opts = get_win_width()
  local win_buf = vim.api.nvim_create_buf(false, true)

  local editor = get_editor_size()
  local padding = PADDING

  local height = math.max(1, math.floor(win_opts.height / 2))
  local width = get_max_width_contents(mark_lists, true)

  local row = padding
  local col = editor.width - width - padding

  ---@type WinCfg
  local wincfg = {
    buf = win_buf,
    enter = true,
    wincfg = {
      relative = "editor",
      width = width,
      height = height,

      row = row,
      col = col,

      style = "minimal",
      border = "rounded",

      title = format_title "📌 QFMarks",
      title_pos = "center",

      footer = " <C-q> Quit | <C-y/v/s/t> Enter/V/Split/Tab ",
      footer_pos = "center",
    },
  }

  local win, buf = build_popup(M.window.mark_win, wincfg, harpoon_lines)
  if not win or not buf then
    return
  end

  local main_win_cfg = vim.api.nvim_win_get_config(win)

  local preview_win, preview_buf = harpoon_preview(M.window.footer_win, buf, main_win_cfg, width)
  if not preview_win or not preview_buf then
    return
  end

  local main_buf = buf
  setup_harpoon_preview(mark_lists, main_buf, preview_buf, preview_win)

  local is_harpoon = true
  local qf_win_popup = {
    primary = M.window.mark_win,
    secondary = M.window.footer_win,
  }

  setup_keymaps(mark_lists, qf_win_popup, buf, cb, is_harpoon)

  local keys = {}

  if type(keymap_harpoon) == "string" then
    keys[#keys + 1] = keymap_harpoon
  elseif type(keymap_harpoon) == "table" then
    for _, x in pairs(keymap_harpoon) do
      keys[#keys + 1] = x
    end
  end

  if #keys > 0 then
    for _, key in pairs(keys) do
      vim.keymap.set("n", key, function()
        close_win(win, preview_win)
        clean_up(M.window.mark_win)
      end, { buffer = buf, nowait = true })
    end
  end
end

---@param buffer_lists string[]
---@param cb function
---@param is_prev? boolean
local function buffers_popup(buffer_lists, cb, is_prev)
  is_prev = is_prev or false

  local win_opts = get_win_width()
  local win_buf = vim.api.nvim_create_buf(false, true)

  local ui = vim.api.nvim_list_uis()[1]

  local height = math.floor(win_opts.height / 2)
  local width = get_max_width_contents(buffer_lists)

  local padding = 2

  local row = padding
  local col = ui.width - width - padding

  if height < 1 then
    height = 1
  end

  ---@type WinCfg
  local wincfg = {
    buf = win_buf,
    enter = true,
    wincfg = {
      relative = "editor",
      width = width,
      height = height,

      row = row,
      col = col,

      style = "minimal",
      border = "rounded",

      title = format_title "📑 QFBuffers",
      title_pos = "center",

      footer = " <C-q> Quit | <C-y/v/s/t> Enter/V/Split/Tab ",
      footer_pos = "center",
    },
  }

  local win, buf = build_popup(M.window.mark_win, wincfg, buffer_lists)

  if not win or not buf then
    return
  end

  local is_buffers = true
  local qf_win_popup = {
    primary = M.window.mark_win,
    secondary = M.window.footer_win,
  }

  setup_keymaps(buffer_lists, qf_win_popup, buf, cb, false, is_buffers)
end

return {
  _mark_harpoon_popup = mark_harpoon_popup,
  _input_popup = input_popup,
  _select_buffer = buffers_popup,
}
