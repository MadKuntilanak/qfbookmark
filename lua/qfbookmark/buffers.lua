local QfbookmarkUtils = require "qfbookmark.utils"
local QfbookmarkPathUtils = require "qfbookmark.path.utils"

local M = {}

---@alias QFBuffersCfg {
---sort_lastused: boolean,
---current_buffer_only?: boolean,
---current_tab_only?: boolean,
---buffers: nil,
---show_unlisted?: boolean ,
---show_unloaded?:boolean,
---ignore_current_buffer?: boolean,
---no_term_buffers?: boolean,
---cwd_only?: boolean,
---cwd?: string,
---filter?: function,
---show_quickfix?: boolean,
---}

M.get = function()
  return {
    alt_bufnr = vim.fn.bufnr "#",
    bufnr = vim.api.nvim_get_current_buf(),
  }
end

---@param buf integer
---@return { bufnr: integer, flag: string, info: table, readonly: boolean }
local getbuf = function(buf)
  return {
    bufnr = buf,
    flag = (buf == M.get().bufnr and "%") or (buf == M.get().alt_bufnr and "#") or "",
    info = QfbookmarkUtils.getbufinfo(buf),
    readonly = vim.bo[buf].readonly,
    loaded = vim.api.nvim_buf_is_loaded(buf),
  }
end

---@param b integer
local function is_valid_buf(b)
  return vim.api.nvim_buf_is_valid(b)
    and vim.bo[b].buftype ~= "nofile"
    and vim.bo[b].buftype ~= "prompt"
    and vim.bo[b].buftype ~= "terminal"
    and vim.api.nvim_buf_get_name(b) ~= ""
end

---@param opts QFBuffersCfg
---@param unfiltered integer[]|fun():integer[]
---@return integer[], table, integer
local filter_buffers = function(opts, unfiltered)
  if type(unfiltered) == "function" then
    unfiltered = unfiltered()
  end

  local function cwd()
    return assert(vim.uv.cwd())
  end

  local curtab_bufnrs = {}
  if opts.current_tab_only then
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      local b = vim.api.nvim_win_get_buf(w)
      curtab_bufnrs[b] = true
    end
  end

  local excluded = {}
  local max_bufnr = 0
  local bufnrs = vim.tbl_filter(function(b)
    if not is_valid_buf(b) then
      excluded[b] = true
      return false
    end

    local bt = vim.bo[b].buftype
    local name = vim.api.nvim_buf_get_name(b)

    if bt ~= "" then
      excluded[b] = true
      return false
    end

    if name:match "^term://" then
      excluded[b] = true
      return false
    end

    if not opts.show_unlisted and b ~= M.get().bufnr and vim.fn.buflisted(b) ~= 1 then
      excluded[b] = true
      return false
    end

    if opts.ignore_current_buffer and b == M.get().bufnr then
      excluded[b] = true
      return false
    end

    if opts.current_tab_only and not curtab_bufnrs[b] then
      excluded[b] = true
      return false
    end

    if opts.no_term_buffers and QfbookmarkUtils.is_term_buffer(b) then
      excluded[b] = true
      return false
    end

    if opts.cwd_only and not QfbookmarkPathUtils.is_relative_to(name, cwd()) then
      excluded[b] = true
      return false
    end

    if opts.cwd and not QfbookmarkPathUtils.is_relative_to(name, opts.cwd) then
      excluded[b] = true
      return false
    end

    if type(opts.filter) == "function" then
      if not opts.filter(b) then
        excluded[b] = true
        return false
      end
    end

    max_bufnr = math.max(max_bufnr, b)
    return true
  end, unfiltered)

  return bufnrs, excluded, max_bufnr
end

---@param opts QFBuffersCfg
---@param bufnrs integer[]
local function get_list_buffers(opts, bufnrs)
  ---@type table[]
  local buffers = {}
  -- Filter invalid buffers (#2519)
  bufnrs = vim.tbl_filter(function(b)
    return vim.api.nvim_buf_is_valid(b)
  end, bufnrs)
  for _, bufnr in ipairs(bufnrs) do
    local buf = getbuf(bufnr)

    -- Get the name for missing/quickfix/location list buffers
    -- NOTE: we get it here due to `gen_buffer_entry` called within a fast event
    if not buf.info.name or #buf.info.name == 0 then
      local __buf_name = QfbookmarkUtils.nvim_buf_get_name(buf.bufnr, buf.info)
      if not vim.tbl_contains({ "[No Name]", "[Quickfix List]", "[Location List]" }, __buf_name) then
        buf.info.name = __buf_name
      end
    end

    -- Use vim.b.term_title where possible (#2456)
    if QfbookmarkUtils.is_term_bufname(buf.info.name) then
      local term_title = vim.b[bufnr].term_title ---@type string?
      if term_title and term_title ~= buf.info.name then
        buf.info.name = "term://" .. term_title:gsub("^term://", "")
      end
    end

    table.insert(buffers, buf)
  end

  -- switching buffers and opening 'buffers' in quick succession
  -- can lead to incorrect sort as 'lastused' isn't updated fast
  -- enough (neovim bug?), this makes sure the current buffer is
  -- always on top (#646)
  -- Hopefully this gets solved before the year 2100
  -- DON'T FORCE ME TO UPDATE THIS HACK NEOVIM LOL
  -- NOTE: reduced to 2038 due to 32bit sys limit (#1636)
  local _FUTURE = os.time { year = 2038, month = 1, day = 1, hour = 0, minute = 00 }
  ---@param buf table
  ---@return integer
  local get_unixtime = function(buf)
    if buf.flag == "%" then
      return _FUTURE
    elseif buf.flag == "#" then
      return _FUTURE - 1
    else
      return buf.info.lastused
    end
  end

  if opts.sort_lastused then
    table.sort(buffers, function(a, b)
      return get_unixtime(a) > get_unixtime(b)
    end)
  end
  return buffers
end

---@type QFBuffersCfg
local buffer_opts = {
  show_unlisted = false,
  current_tab_only = false,
  sort_lastused = true,
  current_buffer_only = false,
  show_unloaded = false,
}

---@param is_prev? boolean
function M.load_buffers(is_prev)
  is_prev = is_prev or false

  local buflist = vim.api.nvim_list_bufs()

  local filtered, _, _ = filter_buffers(buffer_opts, buflist)
  local list_buffers = get_list_buffers(buffer_opts, filtered)

  return list_buffers
end

return M
