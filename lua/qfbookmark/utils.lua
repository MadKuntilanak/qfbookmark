local M = {}

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

---@param list_items QFBookLists
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

---@param list_items QFBookLists
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

---@param is_loc? boolean
---@param context_name? string
---@return QFBookLists
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
---@return QFBookLists | nil
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

---@param buf? integer
function M.is_loclist(buf)
  buf = buf or 0
  return vim.fn.getloclist(buf, { filewinid = 1 }).filewinid ~= 0
end

---@param title? string
local function get_prefix_notify_title(title)
  if not title or (title == "") then
    title = "QFBookmark"
  end
  return title
end

---@param msg string|table
---@param title? string
function M.info(msg, title)
  title = get_prefix_notify_title(title)
  if type(msg) == "table" then
    vim.api.nvim_echo(msg, false, {})
    return
  end
  vim.notify(msg, vim.log.levels.INFO, { title = title })
end

---@param msg string
---@param title? string
function M.warn(msg, title)
  title = get_prefix_notify_title(title)
  vim.notify(msg, vim.log.levels.WARN, { title = title })
end

---@param msg string
---@param title? string
function M.error(msg, title)
  title = get_prefix_notify_title(title)
  vim.notify(msg, vim.log.levels.WARN, { title = title })
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

---@param list_items QFBookLists
---@param cmd_open string
---@param is_loc? boolean
---@param winid? string
function M.save_to_qf_and_auto_open_qf(list_items, cmd_open, is_loc, winid)
  M.save_to_qf(list_items, is_loc, winid)
  vim.cmd(cmd_open)
end

---@param wins string|string[]
---@return { found: boolean, winbufnr: integer, winnr: integer, winid: integer, ft: string }
function M.windows_is_opened(wins)
  local ft_wins = { "incline" }

  if type(wins) == "table" then
    if #wins > 0 then
      for _, x in pairs(wins) do
        ft_wins[#ft_wins + 1] = x
      end
    end
  end

  if type(wins) == "string" then
    ft_wins[#ft_wins + 1] = wins
  end

  local outline_tbl = { found = false, winbufnr = 0, winnr = 0, winid = 0, ft = "" }
  for _, winnr in ipairs(vim.api.nvim_list_wins()) do
    local win_bufnr = vim.api.nvim_win_get_buf(winnr)

    if tonumber(win_bufnr) == 0 then
      return outline_tbl
    end

    local buf_ft = vim.api.nvim_get_option_value("filetype", { buf = win_bufnr })
    local buf_buftype = vim.api.nvim_get_option_value("buftype", { buf = win_bufnr })

    local winid = vim.fn.win_findbuf(win_bufnr)[1] -- example winid: 1004, 1005

    if vim.tbl_contains(ft_wins, buf_ft) or vim.tbl_contains(ft_wins, buf_buftype) then
      outline_tbl = { found = true, winbufnr = win_bufnr, winnr = winnr, winid = winid, ft = buf_ft }
    end
  end

  return outline_tbl
end

---@param filename string
---@return integer | nil
local function is_file_in_buffers(filename)
  local buffers = vim.api.nvim_list_bufs()

  for _, buf in ipairs(buffers) do
    local bufname = vim.api.nvim_buf_get_name(buf)
    if bufname == filename then
      return buf
    end
  end

  return nil
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
function M.is_vim_list_open()
  local curbuf = vim.api.nvim_get_current_buf()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if curbuf == buf then
      if M.is_loclist(win) then
        return true, "loclist"
      end
      if vim.bo[buf].filetype == "qf" then
        return true, "quickfix"
      end
    end
  end
  return false, "none"
end

---@param bufnr? integer
function M.exclude_default_filetype_dan_buftype(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local is_float = vim.api.nvim_win_get_config(0).relative ~= ""
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

  if is_float or is_buftype or is_filetype then
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
---@return boolean
function M._valid(win, buf)
  if not win or not buf then
    return false
  end
  if not vim.api.nvim_win_is_valid(win) or not vim.api.nvim_buf_is_valid(buf) then
    return false
  end
  if vim.api.nvim_win_get_buf(win) ~= buf then
    return false
  end
  if vim.api.nvim_win_get_config(win).relative ~= "" then
    return false
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
    if not M._valid(winid, buf) then
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

---@param bufnr integer
---@return "gone" | "alive" | "hidden"
function M.get_buffer_status(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return "gone"
  end

  local buffers = vim.api.nvim_list_bufs()
  for _, b in ipairs(buffers) do
    if b == bufnr then
      return "alive"
    end
  end

  -- buffer still valid, but hidden (bdelete, bwipeout)
  return "hidden"
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

---@param contents QFbookBufferMark
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

---@param bufnr integer
function M.ensure_treesitter(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local ft = vim.bo[bufnr].filetype
  if ft == "" then
    return
  end

  -- Cek apakah filetype punya mapping language treesitter
  local ok = pcall(vim.treesitter.language.get_lang, ft)
  if not ok then
    return
  end

  -- Start ulang hanya jika belum aktif
  -- if not vim.treesitter.highlighter.active[bufnr] and can_start_treesitter(bufnr) then
  if not vim.treesitter.highlighter.active[bufnr] then
    pcall(vim.treesitter.start, bufnr)
  end
end

-- ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
-- ┃                      BUFFER UTILS                       ┃
-- ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

function M.is_buf_readonly(buf)
  buf = buf or 0
  return not vim.bo[0].modifiable or vim.bo[0].readonly
end

function M.tbl_isempty(T)
  assert(type(T) == "table", string.format("Expected table, got %s", type(T)))
  return next(T) == nil
end

-- returns:
--   1 for qf list
--   2 for loc list
---@param winid integer
---@return 1|2|false
function M.win_is_qf(winid)
  local winty = vim.api.nvim_win_is_valid(winid) and vim.fn.win_gettype(winid) or nil
  return winty == "quickfix" and 1 or winty == "loclist" and 2 or false
end

---@param bufnr integer
---@param bufinfo (vim.fn.getbufinfo.ret.item|vim.fn.getbufinfo.ret.item[]|false|table)?
---@return 1|2|false
function M.buf_is_qf(bufnr, bufinfo)
  bufinfo = bufinfo or (vim.api.nvim_buf_is_valid(bufnr) and M.getbufinfo(bufnr))
  if
    bufinfo
    and bufinfo.variables
    and bufinfo.variables.current_syntax == "qf"
    and not M.tbl_isempty(bufinfo.windows)
  then
    local window = bufinfo
      .windows --[[@cast -?]]
      [1]
    ---@cast window integer
    return M.win_is_qf(window)
  end
  return false
end

---@param bufnr integer
---@param bufinfo table?
---@return string?
function M.nvim_buf_get_name(bufnr, bufinfo)
  assert(not vim.in_fast_event())
  if not vim.api.nvim_buf_is_valid(bufnr) then
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
      local is_qf = M.buf_is_qf(bufnr, bufinfo)
      if is_qf then
        bufname = is_qf == 1 and "[Quickfix List]" or "[Location List]"
      else
        bufname = "[No Name]"
      end
    end
  end
  assert(#bufname > 0)
  return bufname
end

---@param bufnr? integer
---@return vim.fn.getbufinfo.ret.item
function M.getbufinfo(bufnr)
  return vim.fn.getbufinfo(bufnr)[1] or {} ---@as vim.fn.getbufinfo.ret.item
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
  return vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].buftype == "terminal"
end

function M.buf_del(selected)
  if type(selected) == "number" then
    delete_bufnr(selected)
    return
  end

  if type(selected) == "table" then
    if selected.text then
      local bufnr = vim.fn.bufnr(selected.text)
      delete_bufnr(bufnr)
    end
  end
end

return M
