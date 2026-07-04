local M = {}

-- ├─────────────────────────────────┤ NOTIFY ├─────────────────────────────────┤

---@param module_or_message string
---@param message? string
local function notify(hl, module_or_message, message)
  local module

  if message == nil then
    message = module_or_message
  else
    module = module_or_message
  end

  local prefix = module and ("QFBookmark." .. module) or "QFBookmark"

  vim.api.nvim_echo({
    { ("(%s) "):format(prefix), hl },
    { message },
  }, true, {})
end

function M.info(module_or_message, message)
  notify("Directory", module_or_message, message)
end

function M.warn(module_or_message, message)
  notify("WarningMsg", module_or_message, message)
end

function M.error(module_or_message, message)
  notify("ErrorMsg", module_or_message, message)
end

---@param msg? string
function M.not_implemented_yet(msg)
  if msg == nil then
    msg = ""
  end
  if #msg > 0 then
    msg = "Not impelemented, -> " .. msg
  else
    msg = "Not impelemented yet"
  end
  M.warn(msg)
end

function M.echo_empty_mark()
  M.info "Marks is empty!"
end

-- ═════════════════════════════════════════════════════════════════════════════

M.__IS_WINDOWS = vim.fn.has "win32" == 1 or vim.fn.has "win64" == 1

---@type QFBookListResults
local results = {
  quickfix = {
    title = "",
    items = {},
  },
  location = {
    title = "",
    items = {},
  },
}

---@param list_items QFBookmarkLists
local build_qf_opts = function(list_items)
  local opts = {
    items = list_items.items,
    title = list_items.title,
  }

  local data_context = list_items.context
  if type(data_context) == "table" then
    opts.context = vim.deepcopy(data_context)
  else
    opts.context = list_items.context
  end
  return opts
end

---@param list_items QFBookmarkLists
---@param is_loc? boolean
---@param winid? integer
---@param mode? string
function M.save_to_qf(list_items, is_loc, mode, winid)
  is_loc = is_loc or false
  mode = mode or " "

  local opts = build_qf_opts(list_items)

  if not is_loc then
    vim.fn.setqflist({}, mode, opts)
    return
  end

  winid = winid or vim.api.nvim_get_current_win()
  vim.fn.setloclist(winid, {}, mode, opts)
end

---@param is_loc? boolean
---@return string
function M.get_title_qf(is_loc)
  is_loc = is_loc or false

  if not is_loc then
    return vim.fn.getqflist({ title = 0 }).title
  end
  return vim.fn.getloclist(0, { title = 0 }).title
end

---@param is_loc? boolean
---@return integer
function M.get_current_qf_idx(is_loc)
  is_loc = is_loc or M.is_loclist()

  if not is_loc then
    return vim.fn.getqflist({ idx = 0 }).idx
  end

  return vim.fn.getloclist(0, { idx = 0 }).idx
end

---@param winnr integer
---@return boolean
function M.is_quickfix_win(winnr)
  return vim.fn.getwinvar(winnr, "&buftype") == "quickfix"
end

---@param winnr integer
---@return boolean
function M.is_loclist_win(winnr)
  local wininfo = vim.fn.getwininfo(vim.fn.win_getid(winnr))[1]
  return M.is_quickfix_win(winnr) and wininfo.loclist == 1
end

---@param buf? integer
function M.is_loclist(buf)
  buf = buf or 0
  return vim.fn.getloclist(buf, { filewinid = 1 }).filewinid ~= 0
end

---@param is_loc? boolean
---@param context_name? string
---@return QFBookmarkLists
function M.get_list_qf(is_loc, context_name)
  is_loc = is_loc or false
  context_name = context_name or ""

  local list, ctx_list

  if not is_loc then
    if #context_name > 0 then
      ctx_list = vim.fn.getqflist({ context = 1 }).context
      for _, ctx in ipairs(ctx_list) do
        if ctx.name == context_name then
          list = vim.fn.getqflist { id = ctx.id }
          return list
        end
      end
      return {}
    end
    return vim.fn.getqflist { all = 1 }
  end

  local winid = vim.api.nvim_get_current_win()
  if #context_name > 0 then
    ctx_list = vim.fn.getloclist(winid, { context = 1 }).context
    for _, ctx in ipairs(ctx_list) do
      if ctx.name == context_name then
        list = vim.fn.getloclist(winid, { id = ctx.id })
        return list
      end
    end
    return {}
  end

  return vim.fn.getloclist(winid, { all = 1 })
end

---@param is_loc? boolean
---@param context_name? string
---@return QFBookListResults
function M.__debug_get_data_qf(is_loc, context_name)
  local data_tbl = M.get_list_qf(is_loc, context_name).items
  if #data_tbl > 0 then
    results.quickfix.items = data_tbl
  end
  return results
end

---@param is_loc? boolean
---@param context_name? string
---@return QFBookListResults
function M.get_data_qf(is_loc, context_name)
  is_loc = is_loc or false

  if not is_loc then
    local qf_list = M.get_list_qf(is_loc, context_name)
    local qf_title = M.get_title_qf()
    if #qf_list.items > 0 then
      results.quickfix.title = qf_title
      if qf_list.id then
        results.quickfix.id = qf_list.id
      end
      local qf_list_context = qf_list.context
      results.quickfix.context = (type(qf_list_context) == "table") and vim.deepcopy(qf_list_context) or qf_list_context
      results.quickfix.items = vim.tbl_map(function(item)
        return {
          filename = item.bufnr and vim.api.nvim_buf_get_name(item.bufnr),
          module = item.module,
          lnum = item.lnum,
          end_lnum = item.end_lnum,
          col = item.col,
          end_col = item.end_col,
          vcol = item.vcol,
          nr = item.nr,
          pattern = item.pattern,
          text = item.text,
          type = item.type,
          valid = item.valid,
        }
      end, qf_list.items)
    end
  else
    local loc_list = M.get_list_qf(true, context_name)
    local loc_title = M.get_title_qf(true)
    if #loc_list.items > 0 then
      results.location.title = loc_title
      if loc_list.id then
        results.location.id = loc_list.id
      end
      local loc_list_context = loc_list.context
      results.location.context = (type(loc_list_context) == "table") and vim.deepcopy(loc_list_context)
        or loc_list_context
      results.location.items = vim.tbl_map(function(item)
        return {
          filename = item.bufnr and vim.api.nvim_buf_get_name(item.bufnr),
          module = item.module,
          lnum = item.lnum,
          end_lnum = item.end_lnum,
          col = item.col,
          end_col = item.end_col,
          vcol = item.vcol,
          nr = item.nr,
          pattern = item.pattern,
          text = item.text,
          type = item.type,
          valid = item.valid,
        }
      end, loc_list.items)
    end
  end

  return results
end

---@param is_loc? boolean
---@return QFBookmarkLists | nil
function M.get_populate_data_qf(is_loc)
  is_loc = is_loc or false
  local qf_list = {}
  local data_lists = M.get_data_qf(is_loc)
  if is_loc then
    qf_list = data_lists.location
  else
    qf_list = data_lists.quickfix
  end

  if vim.tbl_isempty(qf_list.items) then
    return
  end

  return qf_list
end

---@param str string
---@return string
local rstrip_whitespace = function(str)
  str = string.gsub(str, "%s+$", "")
  return str
end

---@param str string
---@param limit? string|nil
---@return string
local lstrip_whitespace = function(str, limit)
  if limit ~= nil then
    local num_found = 0
    while num_found < limit do
      str = string.gsub(str, "^%s", "")
      num_found = num_found + 1
    end
  else
    str = string.gsub(str, "^%s+", "")
  end
  return str
end

---@param str string
---@return string
function M.strip_whitespace(str)
  if str then
    return rstrip_whitespace(lstrip_whitespace(str))
  end
  return ""
end

---@param list_items QFBookmarkLists
---@param cmd_open string
---@param is_loc? boolean
---@param winid? string
function M.save_to_qf_and_auto_open_qf(list_items, cmd_open, is_loc, winid)
  M.save_to_qf(list_items, is_loc, winid)
  vim.cmd(cmd_open)
end

local function is_float(win)
  return vim.api.nvim_win_get_config(win).relative ~= ""
end

---@param winid integer
---@param exclude_filetypes string[]
---@return {found: boolean, winbufnr: integer, winnr: integer, ft: string} | nil
local function check_window(winid, exclude_filetypes)
  if not vim.api.nvim_win_is_valid(winid) then
    return nil
  end

  local bufnr = vim.api.nvim_win_get_buf(winid)

  if bufnr == 0 then
    return nil
  end

  local ft = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
  local bt = vim.api.nvim_get_option_value("buftype", { buf = bufnr })

  if vim.tbl_contains(exclude_filetypes, ft) or vim.tbl_contains(exclude_filetypes, bt) then
    return {
      found = true,
      winbufnr = bufnr,
      winnr = winid,
      winid = winid,
      ft = ft,
    }
  end

  return nil
end

---@param filetypes string|string[]
---@param is_tab? boolean
---@param is_more_guard? boolean
---@return table
function M.windows_is_opened(filetypes, is_tab, is_more_guard)
  is_tab = is_tab or false

  local exclude_filetypes = { "incline" }

  if type(filetypes) == "table" then
    for _, x in ipairs(filetypes) do
      table.insert(exclude_filetypes, x)
    end
  elseif type(filetypes) == "string" then
    table.insert(exclude_filetypes, filetypes)
  end

  local tab = vim.api.nvim_get_current_tabpage()
  local winids = is_tab and vim.api.nvim_tabpage_list_wins(tab) or vim.api.nvim_list_wins()

  -- Prioritize floating windows when the guard is disabled
  if not is_more_guard then
    for _, winid in ipairs(winids) do
      if is_float(winid) then
        local result = check_window(winid, exclude_filetypes)
        if result then
          return result
        end
      end
    end
  end

  -- Then check the remaining windows
  for _, winid in ipairs(winids) do
    if is_more_guard and is_float(winid) then
      goto continue
    end

    local result = check_window(winid, exclude_filetypes)
    if result then
      return result
    end

    ::continue::
  end

  return {
    found = false,
    winbufnr = 0,
    winnr = 0,
    winid = 0,
    ft = "",
  }
end

function M.normalize_path(path)
  if not vim.startswith(path, "/") then
    path = vim.fn.fnamemodify(path, ":p")
  end

  return vim.fs.normalize(path)
end

function M.denormalize_path(path)
  return vim.fn.fnamemodify(path, ":~")
end

---@param exclude_filetypes? string[]
---@return integer | nil
function M.windows_is_opened_by_name(filename, exclude_filetypes)
  exclude_filetypes = exclude_filetypes or {}

  local buffers = vim.api.nvim_list_bufs()

  local _buf = nil

  for _, buf in ipairs(buffers) do
    -- local ft = vim.bo[buf].filetype
    -- if vim.tbl_contains(exclude_filetypes, ft) or vim.tbl_contains(exclude_filetypes, bt) then
    -- end
    local bufname = vim.api.nvim_buf_get_name(buf)

    local bufname_normalize = M.normalize_path(bufname)
    local filename_normalize = M.normalize_path(filename)

    if bufname_normalize == filename_normalize then
      _buf = buf
      break
    end
  end
  return _buf
end

---@param filename string
---@return integer|nil
function M.find_window_by_filename(filename)
  local filename_normalized = M.normalize_path(filename)

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    local bufname = vim.api.nvim_buf_get_name(buf)

    if M.normalize_path(bufname) == filename_normalized then
      return win
    end
  end

  return nil
end

---@param filename string
---@return integer | nil
local function is_file_in_buffers(filename)
  return M.windows_is_opened_by_name(filename)
end

local function delete_bufnr(buf)
  vim.api.nvim_buf_delete(buf, { force = true })
end

---@param filename string
function M.delete_buffer_by_name(filename)
  local buf = is_file_in_buffers(filename)
  if buf then
    delete_bufnr(buf)
    return true
  end
  return false
end

---@param key string
---@param mode? KeyMode
function M.feedkey(key, mode)
  mode = mode or "n"
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(key, true, true, true), mode, true)
end

---@return boolean, QFBookListType
function M.is_vim_list_open(is_tab)
  is_tab = is_tab or false

  local tab = vim.api.nvim_get_current_tabpage()
  local buf = vim.api.nvim_get_current_buf()
  local wins = is_tab and vim.api.nvim_tabpage_list_wins(tab) or vim.api.nvim_list_wins()

  for _, win in ipairs(wins) do
    local winbuf = vim.api.nvim_win_get_buf(win)
    if buf == winbuf then
      if M.is_loclist(win) then
        return true, "loclist"
      end
      if vim.bo[winbuf].filetype == "qf" then
        return true, "quickfix"
      end
    end
  end

  return false, "none"
end

---@param bufnr? integer
function M.exclude_default_filetype_dan_buftype(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local is_buftype = vim.tbl_contains({ "help", "prompt", "nofile" }, vim.bo[bufnr].buftype)
  local is_filetype = vim.tbl_contains({
    "DiffviewFileHistory",
    "DiffviewFiles",
    "Outline",
    "Trouble",
    "dashboard",
    "fugitive",
    "fzf",
    "gitcommit",
    "packer",
    "snacks_dashboard",
    "toggleterm",
    "orgagenda",
  }, vim.bo[bufnr].filetype)

  if is_float(vim.api.nvim_get_current_win()) or is_buftype or is_filetype then
    return false
  end

  return true
end

---@return { pos: integer, line: integer, col: integer, text: string}
function M.get_line_pos_col_buffer()
  local pos = vim.api.nvim_win_get_cursor(0)

  local line = pos[1]
  local col = pos[2]

  local text = vim.api.nvim_buf_get_lines(0, line - 1, line, false)[1]
  return {
    pos = pos,
    line = line,
    col = col,
    text = text,
  }
end

---@param win integer
---@param buf integer
---@param check_float? boolean
---@return boolean
function M._valid(win, buf, check_float)
  check_float = check_float or false

  if not win or not buf then
    return false
  end
  if not vim.api.nvim_win_is_valid(win) or not vim.api.nvim_buf_is_valid(buf) then
    return false
  end
  if vim.api.nvim_win_get_buf(win) ~= buf then
    return false
  end
  if check_float and (vim.api.nvim_win_get_config(win).relative ~= "") then
    return false
  end

  return true
end

---@param buf? integer
---@param win? integer
---@return boolean
function M.is_valid(buf, win)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return false
  end

  if win and buf then
    return M._valid(win, buf)
  end

  return true
end

---@alias QFbookFoundWin { found: boolean, winid: integer|nil, bufnr: integer|nil}

---@param opts { bufnr: integer?, filename: string?}
---@return QFbookFoundWin
function M.find_win_ls(opts)
  local win_found = { found = false, winid = nil, bufnr = nil }

  local current_buf = vim.api.nvim_get_current_buf()
  local current_win = vim.api.nvim_get_current_win()
  local current_filename = vim.api.nvim_buf_get_name(current_buf)

  -- Return false immediately if the filename is the same
  if opts.filename and opts.filename == current_filename then
    return win_found
  end

  -- Get all windows from tabs
  -- local wins = vim.api.nvim_list_wins()

  -- Get all windows only from current tab
  local wins = vim.api.nvim_tabpage_list_wins(0)

  for _, winid in ipairs(wins) do
    local buf = vim.api.nvim_win_get_buf(winid)
    if not M._valid(winid, buf, true) then
      goto continue
    end

    -- Check bufnr
    if opts.bufnr and buf == opts.bufnr then
      return { found = true, winid = winid, bufnr = buf }
    end

    -- Check filename
    if opts.filename then
      local buf_filename = vim.api.nvim_buf_get_name(buf)
      if opts.filename == buf_filename then
        -- kalau cuma 1 window di tab ini, jangan dianggap found
        if #wins == 1 and winid == current_win then
          return { found = false, winid = nil, bufnr = nil }
        end

        return { found = true, winid = winid, bufnr = buf }
      end
    end

    ::continue::
  end

  return win_found
end

---@param harp string
---@return string
function M.remove_idx_m_harpoon(harp)
  local harp_str = vim.split(harp, " ")
  if harp_str[2] then
    return M.strip_whitespace(harp_str[2])
  end
  return harp
end

---@param idx integer
---@param harp string
---@return string
function M.add_idx_m_harpoon(idx, harp)
  local line = M.remove_idx_m_harpoon(harp)
  return "[" .. idx .. "] " .. line
end

---@param name string
---@param opts? {sign_group: string}
function M.create_augroup_name(name, opts)
  opts = opts or { sign_group = "QFBook" }
  return vim.api.nvim_create_augroup(opts.sign_group .. name, { clear = true })
end

---@param augroup_name string
function M.clear_autocmd_group(augroup_name)
  pcall(vim.api.nvim_clear_autocmds, { group = augroup_name })
  pcall(vim.api.nvim_del_augroup_by_name, augroup_name)
end

--- | ---- | ------------------------------- |
--- | `m`  | Remap keys (ikuti mapping)      |
--- | `n`  | No remap                        |
--- | `t`  | Handle sebagai typed input      |
--- | `i`  | Insert di depan typeahead       |
--- | `x`  | Execute sampai typeahead kosong |

---@alias ModeFeedKey "m" | "n" | "t" | "x" | "mt"

---@param key string
---@param mode? ModeFeedKey
local function feedkey(key, mode)
  mode = mode or "n"
  if mode == "" then
    mode = "n"
  end

  local tc = vim.api.nvim_replace_termcodes(key, true, false, true)
  vim.api.nvim_feedkeys(tc, mode, false)
end

---@param contents QFBookmarkBufferMark
---@param filename string
function M.save_table_to_file(contents, filename)
  local file = io.open(filename, "w")
  if file then
    file:write "return "
    file:write(tostring(vim.inspect(contents)))
    file:close()
  else
    M.warn "Failed to save data table to file"
  end
end

---@return string
function M.resolve_key_shortcut_keymaps()
  local cfg = require("qfbookmark.config").defaults.keymaps.actions.show_help or "g?"
  if type(cfg) == "table" then
    return cfg[1]
  end
  return cfg
end

-- ╓─────────────────────────────────────────────────────────────────────────────╖
-- ║                                 NOTES UTILS                                 ║
-- ╙─────────────────────────────────────────────────────────────────────────────╜

-- Adapted from fzf-lua: https://github.com/ibhagwan/fzf-lua/blob/6ee73fdf2a79bbd74ec56d980262e29993b46f2b/lua/fzf-lua/utils.lua#L434-L466
-- this will exit visual mode
-- use 'gv' to reselect the text
---@param opts? { strict: boolean, exit_from_visual: boolean }
---@return QFBookmarkLines | nil
function M.get_visual_selection(opts)
  opts = opts or {}

  local _, csrow, cscol, cerow, cecol

  local bufnr = vim.api.nvim_get_current_buf()
  local filename = vim.api.nvim_buf_get_name(bufnr)

  local mode = vim.fn.mode()

  if opts.strict and not vim.endswith(string.lower(mode), "v") then
    return
  end

  if mode == "v" or mode == "V" or mode == "" then
    -- if we are in visual mode use the live position
    _, csrow, cscol, _ = unpack(vim.fn.getpos ".")
    _, cerow, cecol, _ = unpack(vim.fn.getpos "v")
    if mode == "V" then
      -- visual line doesn't provide columns
      cscol, cecol = 0, 999
    end
    if not opts.exit_from_visual then
      -- exit visual mode
      feedkey "<Esc>"
    end
  else
    -- otherwise, use the last known visual position
    _, csrow, cscol, _ = unpack(vim.fn.getpos "'<")
    _, cerow, cecol, _ = unpack(vim.fn.getpos "'>")
  end

  -- Swap vars if needed
  if cerow < csrow then
    csrow, cerow = cerow, csrow
    cscol, cecol = cecol, cscol
  elseif cerow == csrow and cecol < cscol then
    cscol, cecol = cecol, cscol
  end

  local lines = vim.fn.getline(csrow, cerow)
  assert(type(lines) == "table")
  if vim.tbl_isempty(lines) then
    return
  end

  -- When the whole line is selected via visual line mode ("V"), cscol / cecol
  -- will be equal to "v:maxcol" for some odd reason. So change that to what
  -- they should be here. See ':h getpos' for more info.
  local maxcol = vim.api.nvim_get_vvar "maxcol"
  if cscol == maxcol then
    cscol = string.len(lines[1])
  end
  if cecol == maxcol then
    cecol = string.len(lines[#lines])
  end

  ---@type string
  local selection
  local n = #lines
  if n <= 0 then
    selection = ""
  elseif n == 1 then
    selection = string.sub(lines[1], cscol, cecol)
  elseif n == 2 then
    selection = string.sub(lines[1], cscol) .. "\n" .. string.sub(lines[n], 1, cecol)
  else
    selection = string.sub(lines[1], cscol)
      .. "\n"
      .. table.concat(lines, "\n", 2, n - 1)
      .. "\n"
      .. string.sub(lines[n], 1, cecol)
  end

  return {
    lines = lines,
    selection = selection,
    filename = filename,
    csrow = csrow,
    cscol = cscol,
    cerow = cerow,
    cecol = cecol,
  }
end

--- Check whether the captured lines contain any non-whitespace content.
---@param lines string[]
---@return boolean
function M.has_content(lines)
  for _, line in ipairs(lines) do
    if line:match "%S" then
      return true
    end
  end
  return false
end

-- ╓─────────────────────────────────────────────────────────────────────────────╖
-- ║                                BUFFER UTILS                                 ║
-- ╙─────────────────────────────────────────────────────────────────────────────╜

---@param filename string
---@return integer | nil
function M.resolve_bufnr(filename)
  if not filename then
    return nil
  end

  if filename:match "^fugitive://" then
    local bufnr = vim.fn.bufnr(filename)
    if bufnr == -1 then
      bufnr = vim.fn.bufadd(filename)
    end
    return bufnr ~= -1 and bufnr or nil
  end

  if vim.fn.filereadable(filename) == 1 then
    local bufnr = vim.fn.bufnr(filename)
    if bufnr == -1 then
      bufnr = vim.fn.bufadd(filename)
    end
    vim.fn.bufload(bufnr)
    return bufnr
  end

  return nil
end

function M.is_buf_readonly(buf)
  buf = buf or 0
  return not vim.bo[buf].modifiable or vim.bo[buf].readonly
end

function M.tbl_isempty(T)
  assert(type(T) == "table", string.format("Expected table, got %s", type(T)))
  return next(T) == nil
end

---@param bufnr integer
---@param bufinfo table?
---@return string?
function M.nvim_buf_get_name(bufnr, bufinfo)
  assert(not vim.in_fast_event())
  if not M.is_valid(bufnr) then
    return
  end
  if bufinfo and bufinfo.name and #bufinfo.name > 0 then
    return bufinfo.name
  end
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  if #bufname == 0 then
    if vim.bo[bufnr].buftype == "nofile" then
      bufname = "[Scratch]"
    else
      local is_loc = M.is_loclist(bufnr)
      bufname = is_loc and "[Quickfix List]" or "[Location List]"
    end
  end
  assert(#bufname > 0)
  return bufname
end

---@class BufInfoEx : vim.fn.getbufinfo.ret.item
---@field col? integer

---@param bufnr? integer
---@return vim.fn.getbufinfo.ret.item & { col?: integer }
function M.getbufinfo(bufnr)
  local info = vim.fn.getbufinfo(bufnr)[1] or {}

  ---@cast info BufInfoEx

  if not M.is_valid(bufnr) then
    return info
  end

  local winid = vim.fn.bufwinid(bufnr)

  if winid ~= -1 then
    local pos = vim.api.nvim_win_get_cursor(winid)

    info.lnum = pos[1]
    info.col = pos[2]
  else
    ---@cast bufnr integer
    local mark = vim.api.nvim_buf_get_mark(bufnr, '"')

    if mark[1] > 0 then
      info.lnum = mark[1]
      info.col = mark[2]
    end
  end

  return info
end

function M.is_term_bufname(bufname)
  if bufname and bufname:match "term://" then
    return true
  end
  return false
end

---@param bufnr integer
---@return boolean
function M.is_term_buffer(bufnr)
  if M.is_valid(bufnr) then
    return vim.bo[bufnr].buftype == "terminal"
  end
  return false
end

---@param selected integer | { bufnr: integer, info: table, flag: string, readonly: boolean, loaded: boolean }
function M.buf_del(selected)
  if type(selected) == "number" then
    delete_bufnr(selected)
    return
  end

  if type(selected) == "table" then
    -- prefer bufnr directly; fall back to resolving from info.name
    local bufnr = selected.bufnr
    if not M.is_valid(bufnr) then
      local filename = selected.info and selected.info.name
      local buf = M.resolve_bufnr(filename)
      if not buf then
        ---@cast buf integer
        bufnr = buf
      end
    end

    if M.is_valid(bufnr) then
      delete_bufnr(bufnr)
    end
  end
end

return M
