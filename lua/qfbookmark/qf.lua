local Config = require("qfbookmark.config").defaults

local QfbookmarkWindow = require "qfbookmark.window"
local QfbookmarkNav = require "qfbookmark.nav"
local QfbookmarkUtils = require "qfbookmark.utils"
local QfbookmarkBuffers = require "qfbookmark.buffers"
local QfbookmarkUI = require "qfbookmark.ui"
local QfbookmarkBookmark = require "qfbookmark.mark"
local QfbookmarkPaths = require "qfbookmark.path"

local M = { prefix_app = "QFBookmark" }
Config.ns = vim.api.nvim_create_namespace(M.prefix_app .. "Ns")
Config.sign_group = "QFBook"

local last_winid = 0
local status_autocmd_enabled = false
local MARK_MODE = vim.tbl_keys(Config.extmarks.keywords) -- { mark, debug, note .. }

---@type QFbookBufferMark
M.buffers = {}

---@type QFbookBufferMarkEntry[]
M.mark_lists = {}

---@type table <string>
M.mark_lists_harpoon = {}

---@return QFbookBufferMarkEntry[]
local function get_lists_marks()
  if vim.tbl_isempty(M.buffers) then
    return {}
  end

  ---@type QFbookBufferMarkEntry[]
  local mark_lists = {}

  for mark_mode, _ in pairs(M.buffers) do
    for _, m in pairs(M.buffers[mark_mode]) do
      mark_lists[#mark_lists + 1] = m
    end
  end

  table.sort(mark_lists, function(a, b)
    return (a.inserted_at or 0) > (b.inserted_at or 0)
  end)

  if #M.mark_lists_harpoon > 0 then
    local pos = {}
    for i, v in ipairs(M.mark_lists_harpoon) do
      v = QfbookmarkUtils.remove_idx_m_harpoon(v)
      pos[v] = i
    end

    -- Sort tabel mark_lists base on mark_lists_harpoon
    table.sort(mark_lists, function(x, y)
      if not x or not y then
        return false
      end
      local px = pos[x.harpoon]
      local py = pos[y.harpoon]
      return (px or math.huge) < (py or math.huge)
    end)
  end

  return mark_lists
end

---@param bufnr integer
---@return boolean
local function exclude_buf(bufnr)
  ---@type { buftypes: table, filetypes: table}
  local excluded = Config.extmarks.excluded
  local user_buftypes = excluded.buftypes
  local user_filetype = excluded.filetypes

  if vim.api.nvim_buf_get_name(bufnr):match "^fugitive://" then
    return true
  end

  local buftype = vim.api.nvim_get_option_value("buftype", { buf = bufnr })

  if #user_buftypes > 0 then
    user_buftypes[#user_buftypes + 1] = { "prompt", "nofile" }
  else
    user_buftypes = { "prompt", "nofile", "quickfix" }
  end
  if vim.tbl_contains(user_buftypes, buftype) then
    return false
  end
  local filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
  if vim.tbl_contains(user_filetype, filetype) then
    return false
  end

  local win = vim.api.nvim_get_current_win()
  if not QfbookmarkUtils._valid(win, bufnr) then
    return false
  end

  return true
end

local function recall_augroup()
  QfbookmarkBookmark.setup_mark_autocmds(M.buffers, true)

  QfbookmarkUtils.clear_autocmd_group(Config.sign_group .. "SaveMark")
  if status_autocmd_enabled then
    vim.api.nvim_create_autocmd({ "VimLeavePre" }, {
      group = QfbookmarkUtils.create_augroup_name "SaveMark",
      callback = function()
        local mark_lists = get_lists_marks()
        QfbookmarkBookmark.save_marks(mark_lists)
      end,
    })
  end
end

local function remove_augroup()
  if status_autocmd_enabled then
    if M.buffers and #M.buffers == 0 then
      local list_augroups = {
        Config.sign_group .. "RefreshMark",
        Config.sign_group .. "SaveMark",
      }
      for _, au_group in pairs(list_augroups) do
        QfbookmarkUtils.clear_autocmd_group(au_group)
      end
    end
    status_autocmd_enabled = false
  end
end

-- ┏╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍┓
-- ╏                                    MISC                                     ╏
-- ┗╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍┛

function M.save_or_load()
  require("qfbookmark.pickers").handle_state(Config)
end

-- ┏╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍┓
-- ╏                                    MARK                                     ╏
-- ┗╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍┛

local function reset_harpoon_list()
  local mark_entry_lists = get_lists_marks()

  if #M.mark_lists_harpoon == 0 then
    for m_idx, m in ipairs(mark_entry_lists) do
      M.mark_lists_harpoon[#M.mark_lists_harpoon + 1] = QfbookmarkUtils.add_idx_m_harpoon(m_idx, m.harpoon)
    end
  else
    -- 1. Collect the valid harpoon IDs
    local idx_lookup = {}
    for _, m in ipairs(mark_entry_lists) do
      idx_lookup[m.harpoon] = true
    end

    -- 2. Remove any harpoon entries that are no longer valid
    local i = 1
    while i <= #M.mark_lists_harpoon do
      local harp = QfbookmarkUtils.remove_idx_m_harpoon(M.mark_lists_harpoon[i])
      if not idx_lookup[harp] then
        table.remove(M.mark_lists_harpoon, i)
      else
        i = i + 1
      end
    end

    -- 3. Add any new harpoon IDs that don't already exist, insert at front (newest first)
    for _, m in ipairs(mark_entry_lists) do
      local id = m.harpoon
      local exists = false
      for _, v in ipairs(M.mark_lists_harpoon) do
        local harp = QfbookmarkUtils.remove_idx_m_harpoon(v)
        if id == harp then
          exists = true
          break
        end
      end
      if not exists then
        table.insert(M.mark_lists_harpoon, 1, QfbookmarkUtils.add_idx_m_harpoon(1, id))
      end
    end

    -- 4. Re-index all entries after modification
    for idx, v in ipairs(M.mark_lists_harpoon) do
      local harp = QfbookmarkUtils.remove_idx_m_harpoon(v)
      M.mark_lists_harpoon[idx] = QfbookmarkUtils.add_idx_m_harpoon(idx, harp)
    end
  end

  -- QfbookmarkBookmark.save_marks(M.buffers)
end
local function sync_marks_harpoon()
  reset_harpoon_list()

  if #M.mark_lists_harpoon > 0 then
    status_autocmd_enabled = true
    recall_augroup()
  else
    remove_augroup()
  end
end

local function clean_up_marks_harpoon()
  local mark_entry_lists = get_lists_marks()

  local idx_lookup = {}
  for _, id in ipairs(M.mark_lists_harpoon) do
    idx_lookup[id] = true
  end

  local mark_keep = {}
  for _, m in pairs(mark_entry_lists) do
    if idx_lookup[m.harpoon] then
      mark_keep[#mark_keep + 1] = m.harpoon
    end
  end

  M.mark_lists_harpoon = mark_keep
end

function M.setup_autocmds()
  local qfhighlights = require "qfbookmark.highlights"
  qfhighlights(M.prefix_app)

  vim.api.nvim_create_autocmd("ColorScheme", {
    callback = function()
      vim.schedule(function()
        require "qfbookmark.highlights"(M.prefix_app)
      end)
    end,
  })

  if status_autocmd_enabled then
    vim.schedule(function()
      recall_augroup()
    end)
  end

  if not status_autocmd_enabled then
    vim.schedule(function()
      local mark_lists = QfbookmarkPaths.get_data_marks_from_local_project()
      if not mark_lists or vim.tbl_isempty(mark_lists) then
        return
      end

      -- fix old bufnr and support fugitive
      for _, m in pairs(mark_lists) do
        m.bufnr = QfbookmarkUtils.resolve_bufnr(m.filename)
      end

      -- Sort by inserted_at before loading into M.buffers (newest first)
      local sorted_marks = {}
      for m_idx, m in pairs(mark_lists) do
        sorted_marks[#sorted_marks + 1] = { idx = m_idx, data = m }
      end
      table.sort(sorted_marks, function(a, b)
        return (a.data.inserted_at or 0) > (b.data.inserted_at or 0)
      end)

      for _, entry in ipairs(sorted_marks) do
        local m_idx, m = entry.idx, entry.data

        if not M.buffers[m.mark_mode] then
          M.buffers[m.mark_mode] = {}
        end

        M.buffers[m.mark_mode][m.id] = {
          bufnr = m.bufnr,
          filename = m.filename,
          line = m.line,
          col = m.col,
          text = m.text,
          harpoon = m.harpoon,
          mark_mode = m.mark_mode,
          fn_name = m.fn_name,
          id = m.id,
          note = m.note,
          inserted_at = (m.inserted_at and m.inserted_at < 1e13) and m.inserted_at or 0, -- preserve from saved file; reject stale hrtime values (> 1e13 = nanoseconds, not Unix seconds)
        }

        M.mark_lists_harpoon[#M.mark_lists_harpoon + 1] = QfbookmarkUtils.add_idx_m_harpoon(m_idx, m.harpoon)
      end

      sync_marks_harpoon()
      M.invalidate_mark_cache()

      for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(bufnr) then
          QfbookmarkBookmark.update_mark_sign(M.buffers, bufnr)
        end
      end
    end)
  end
end

local _cache_mark = false
local _cache_dirty = true

function M.invalidate_mark_cache()
  _cache_dirty = true
end

function M.status_mark()
  if _cache_dirty then
    reset_harpoon_list()
    _cache_mark = #M.mark_lists_harpoon > 0
    _cache_dirty = false
  end
  return _cache_mark
end

--- plan: toggle a mark sign on the current line.
--- - Empty line: add the given mark mode
--- - Update note annnotation, open the note window (no delete)
--- - Same mode already present (non-NOTE): delete (toggle off)
--- - Different non-NOTE mode present (e.g. FIX → press MARK): delete existing
--- - NOTE present: block adding MARK/FIX/DEBUG on the same line

---@param mark_mode QFBookMarkMode
local function add_sign(mark_mode)
  local mark_tbl = M.buffers
  local bufnr = vim.api.nvim_get_current_buf()

  if not exclude_buf(bufnr) then
    QfbookmarkUtils.warn "Can't perform this action. This buffer is excluded."
    return
  end

  local extmarkspec = Config.extmarks.keywords[mark_mode]

  local _, has_note = QfbookmarkBookmark.has_mark_data(mark_tbl, "NOTE")
  local _, has_same_mode = QfbookmarkBookmark.has_mark_data(mark_tbl, mark_mode)

  local has_other_mark = false
  for _, mode in pairs(MARK_MODE) do
    if mode ~= "NOTE" and mode ~= mark_mode then
      local _, has = QfbookmarkBookmark.has_mark_data(mark_tbl, mode)
      if has then
        has_other_mark = true
        break
      end
    end
  end

  -- Open the note window instead of toggling,
  -- to update note data_annotation
  if has_same_mode and mark_mode == "NOTE" then
    QfbookmarkBookmark.add_mark(mark_tbl, mark_mode, extmarkspec, true)
    sync_marks_harpoon()
    M.invalidate_mark_cache()
    vim.schedule(function()
      local mark_lists = get_lists_marks()
      QfbookmarkBookmark.save_marks(mark_lists)
    end)
    return
  end

  -- Toggle delete: same mode already exists (non-NOTE)
  if has_same_mode then
    M.delete_mark()
    return
  end

  -- Delete existing: a different mark mode exists (e.g. FIX present, pressing MARK)
  if has_other_mark then
    M.delete_mark()
    return
  end

  -- NOTE exists: cannot add MARK/FIX/DEBUG on the same line
  if has_note and mark_mode ~= "NOTE" then
    QfbookmarkUtils.warn("Can't add `" .. mark_mode .. "`: sign NOTE already exists on this line.")
    return
  end

  -- fresh line: add the mark
  QfbookmarkBookmark.add_mark(mark_tbl, mark_mode, extmarkspec, false)
  sync_marks_harpoon()
  M.invalidate_mark_cache()

  vim.schedule(function()
    local mark_lists = get_lists_marks()
    QfbookmarkBookmark.save_marks(mark_lists)
  end)
end

function M.add_mark_sign()
  add_sign "MARK"
end
function M.add_fix_sign()
  add_sign "FIX"
end
function M.add_debug_sign()
  add_sign "DEBUG"
end
function M.add_note_sign()
  add_sign "NOTE"
end

local function delete_mark_builtin()
  local marks = {}
  for i = string.byte "a", string.byte "z" do
    local mark = string.char(i)
    local mark_line = vim.fn.line("'" .. mark)
    if mark_line == vim.fn.line "." then
      table.insert(marks, mark)
    end
  end

  if #marks > 0 then
    vim.cmd("delmarks " .. table.concat(marks, ""))
  end

  -- Delete marks that have uppercase letters
  vim.cmd "delmarks A-Z"
end

function M.delete_mark()
  delete_mark_builtin()

  local bufnr = vim.api.nvim_get_current_buf()
  local pos = vim.api.nvim_win_get_cursor(0)

  local line = pos[1]
  local id = tonumber(line .. bufnr)
  if not id then
    return
  end

  local mark_lists = M.buffers

  local opts = QfbookmarkBookmark.is_current_line_got_mark(mark_lists, { no_id = true })
  if not opts then
    return
  end

  local is_delete = QfbookmarkBookmark.delete_mark(mark_lists, opts.mark_mode, opts.id)
  if not is_delete then
    QfbookmarkUtils.warn(
      string.format(
        "Failed to delete mark (mode: %s, id: %s). Please check your input.",
        tostring(opts.mark_mode),
        tostring(opts.id)
      )
    )
  end

  vim.schedule(function()
    clean_up_marks_harpoon()
    reset_harpoon_list()
    M.invalidate_mark_cache()
  end)
end
---@param bufnr? integer
function M.delete_mark_buffer(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local filename = vim.fs.normalize(vim.api.nvim_buf_get_name(bufnr))

  local to_delete = {}

  for mode_mark, marks in pairs(M.buffers) do
    for id, mark in pairs(marks) do
      if vim.fs.normalize(mark.filename) == filename then
        table.insert(to_delete, {
          mode_mark = mode_mark,
          id = tonumber(id),
        })
      end
    end
  end

  for _, item in ipairs(to_delete) do
    QfbookmarkBookmark.delete_mark(M.buffers, item.mode_mark, item.id)
  end

  vim.cmd "delmarks!"

  vim.schedule(function()
    clean_up_marks_harpoon()
    M.invalidate_mark_cache()
  end)
end

---@param is_prev_or_next boolean
local function next_prev_mark(is_prev_or_next)
  local status_mark = M.status_mark()
  if not status_mark then
    QfbookmarkUtils.echo_emtpy_mark()
    return
  end
  local mark_lists = get_lists_marks()
  QfbookmarkNav.handle_nav_mark(mark_lists, is_prev_or_next)
end

function M.next_mark()
  next_prev_mark(false)
end
function M.prev_mark()
  next_prev_mark(true)
end

-- ┏╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍┓
-- ╏                                   BUFFERS                                   ╏
-- ┗╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍┛

---@param is_prev? boolean
local function load_buffers(is_prev)
  local list_buffers = QfbookmarkBuffers.load_buffers(is_prev)
  QfbookmarkUI.buffers_popup(list_buffers)
end

function M.open_buffers()
  load_buffers()
end

-- ┏╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍┓
-- ╏                                   HARPOON                                   ╏
-- ┗╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍┛

-- Delete this func!
function M.debug_qf()
  QfbookmarkUtils.info(vim.inspect(M.buffers))
  QfbookmarkUtils.info(vim.inspect(M.mark_lists))
  QfbookmarkUtils.info(vim.inspect(M.mark_lists_harpoon))
end

function M.get_buffers()
  local status_mark = M.status_mark()
  if not status_mark then
    return {}
  end
  return M.buffers
end

function M.open_mark_harpoon_window()
  sync_marks_harpoon()
  M.invalidate_mark_cache()

  local mark_entry_lists = get_lists_marks()

  local old_harpoon = {}
  for _, harp in ipairs(M.mark_lists_harpoon) do
    old_harpoon[#old_harpoon + 1] = QfbookmarkUtils.remove_idx_m_harpoon(harp)
  end

  QfbookmarkUI.mark_harpoon_popup(mark_entry_lists, function(harpoon_vals)
    if type(harpoon_vals) == "string" then
      return
    end

    if harpoon_vals.selected then
      local selected_marks = harpoon_vals.data
      if Config.window.mark.on_send then
        Config.window.mark.on_send(selected_marks)
      end
      return
    end

    if #old_harpoon ~= #harpoon_vals then
      local idx_lookup = {}
      for _, x in pairs(harpoon_vals) do
        idx_lookup[x] = true
      end

      local harp_need_delete = {}
      for _, x in pairs(old_harpoon) do
        if not idx_lookup[x] then
          harp_need_delete[#harp_need_delete + 1] = x
        end
      end

      for _, m in ipairs(mark_entry_lists) do
        for _, x in ipairs(harp_need_delete) do
          if m.harpoon == x then
            local mark_lists = M.buffers

            local _, is_has_mark = QfbookmarkBookmark.has_mark_data(mark_lists, m.mark_mode, m.id, m.bufnr)

            if not is_has_mark then
              goto continue
            end

            if not m.bufnr or not vim.api.nvim_buf_is_valid(m.bufnr) then
              QfbookmarkBookmark.delete_mark(mark_lists, m.mark_mode, m.id, m.bufnr)
              goto continue
            end

            local ok = QfbookmarkBookmark.delete_mark(mark_lists, m.mark_mode, m.id, m.bufnr)

            if not ok then
              QfbookmarkUtils.warn "Something went wrong"
            end

            ::continue::
          end
        end
      end

      sync_marks_harpoon()
      M.invalidate_mark_cache()
    end

    -- Rebuild mark_lists_harpoon dengan idx prefix baru
    local new_lines = {}
    for idx, hval in ipairs(harpoon_vals) do
      new_lines[#new_lines + 1] = QfbookmarkUtils.add_idx_m_harpoon(idx, hval)
    end
    M.mark_lists_harpoon = new_lines

    local mark_lists = get_lists_marks()
    QfbookmarkBookmark.save_marks(mark_lists)
  end)
end

---@param idx integer
function M.goto_mark_index(idx)
  local status_mark = M.status_mark()
  if not status_mark then
    QfbookmarkUtils.warn("No registered signmark exists for index `" .. tostring(idx) .. "`")
    return
  end

  local mark_entry_lists = get_lists_marks()

  local mark_harpoon_idx = M.mark_lists_harpoon[idx]

  if not mark_harpoon_idx then
    if Config.window.notify.mark then
      QfbookmarkUtils.warn("No registered signmark exists for index `" .. tostring(idx) .. "`")
    end
    return
  end

  local harpoon_idx = QfbookmarkUtils.remove_idx_m_harpoon(mark_harpoon_idx)

  for _, m in pairs(mark_entry_lists) do
    if m.harpoon == harpoon_idx then
      QfbookmarkNav.jump_to {
        filename = m.filename,
        col = m.col,
        line = m.line,
      }
    end
  end
end

-- ┏╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍┓
-- ╏                                  QUICKFIX                                   ╏
-- ┗╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍┛

---@param list_type QFBookListType
local function add_item(list_type)
  local bufnr = vim.api.nvim_get_current_buf()

  if not exclude_buf(bufnr) then
    QfbookmarkUtils.warn "Can’t perform this action. This buffer is excluded."
    return
  end

  local is_location_target = list_type == "loclist"
  local cmd_ = is_location_target and { "lclose", Config.window.quickfix.lopen, "loclist" }
    or { "cclose", Config.window.quickfix.copen, "qflist" }

  local title = QfbookmarkUtils.get_title_qf(QfbookmarkUtils.is_loclist())
  if title and title:match "setqflist" or #title == 0 then
    title = "Add item into " .. (is_location_target and "lf" or "qf")
  end

  local pos = vim.api.nvim_win_get_cursor(0)
  local lnum = pos[1]
  local col = pos[2]

  ---@type QFBookLists
  local list_items = {
    items = {
      {
        bufnr = vim.api.nvim_get_current_buf(),
        lnum = lnum,
        col = col,
        -- text = extmarkspec.alt .. QfbookmarkUtils.strip_whitespace(vim.api.nvim_get_current_line()),
        text = QfbookmarkUtils.strip_whitespace(vim.api.nvim_get_current_line()),
        line = vim.api.nvim_get_current_line(),
      },
    },
    title = title,
  }

  if is_location_target then
    QfbookmarkUtils.save_to_qf(list_items, true, "a")
  else
    QfbookmarkUtils.save_to_qf(list_items, false, "a")
  end

  if Config.window.quickfix.enabled then
    local is_open, _ = QfbookmarkUtils.is_vim_list_open(true)
    if not is_open then
      vim.cmd(cmd_[2])
      vim.cmd "wincmd p"
    end
  end
end

function M.add_item_qflist()
  add_item "quickfix"
end
function M.add_item_loclist()
  add_item "loclist"
end

---@param list_type QFBookListType
local function rename_header(list_type)
  local is_location_target = list_type == "loclist"
  local cmd = is_location_target and { Config.window.quickfix.lopen, "LocList" }
    or { Config.window.quickfix.copen, "QuickFix" }

  if QfbookmarkUtils.is_loclist() then
    QfbookmarkUtils.warn("Renaming the title is not supported in the " .. cmd[2] .. ",\nOnly in Quickfix")
    return
  end

  local title = string.format("📝 Rename %s Title", cmd[2])
  QfbookmarkUI.saveqf_popup(title, "", "rename", is_location_target, function(input_msg)
    if input_msg == "" or input_msg == nil then
      return
    end
    vim.fn.setqflist({}, "r", { title = input_msg })
    vim.cmd(cmd[1])
  end)
end

function M.rename_title_qf()
  if QfbookmarkUtils.is_loclist() then
    rename_header "loclist"
    return
  end
  rename_header "quickfix"
end

---@param list_type QFBookListType
---@param force_close? boolean
local function toggle_list(list_type, force_close)
  force_close = force_close or false

  local is_location_target = list_type == "loclist"
  local cmd_ = is_location_target and { "lclose", Config.window.quickfix.lopen }
    or { "cclose", Config.window.quickfix.copen }
  local is_open, qf_or_loclist = QfbookmarkUtils.is_vim_list_open(true)

  if (is_open and (list_type == qf_or_loclist)) or force_close then
    vim.fn.win_gotoid(last_winid)
    vim.cmd(cmd_[1])
    return
  end

  if vim.bo.filetype == "qf" then
    vim.cmd.wincmd "p"
  end

  local list = QfbookmarkUtils.get_list_qf(is_location_target)
  if not vim.tbl_isempty(list.items) then
    last_winid = vim.fn.win_getid()
    vim.cmd(cmd_[2])
    return
  end

  local msg_prefix = (is_location_target and "LocList" or "QuickFix")
  QfbookmarkUtils.warn(msg_prefix .. " items is empty")

  if vim.bo[0].filetype == "qf" then
    vim.cmd.wincmd "p"
  end
end

function M.toggle_open_qflist()
  toggle_list "quickfix"
end
function M.toggle_open_loclist()
  toggle_list "loclist"
end

function M.open_item_qf()
  local list_type = QfbookmarkUtils.is_loclist() and "loclist" or "quickfix"
  local is_center = Config.window.quickfix.actions.auto_center
  local is_ispanded = Config.window.quickfix.actions.auto_unfold
  QfbookmarkNav.handle_open("default", is_center, is_ispanded)

  if Config.keymaps.open_item.default.auto_close then
    toggle_list(list_type, true)
  end
end
function M.open_item_in_tab()
  local list_type = QfbookmarkUtils.is_loclist() and "loclist" or "quickfix"
  local is_center = Config.window.quickfix.actions.auto_center
  local is_ispanded = Config.window.quickfix.actions.auto_unfold
  QfbookmarkNav.handle_open("tabnew", is_center, is_ispanded)

  if Config.keymaps.open_item.tab.auto_close then
    toggle_list(list_type, true)
  end
end
function M.open_item_in_split()
  local list_type = QfbookmarkUtils.is_loclist() and "loclist" or "quickfix"
  local is_center = Config.window.quickfix.actions.auto_center
  local is_ispanded = Config.window.quickfix.actions.auto_unfold
  QfbookmarkNav.handle_open("split", is_center, is_ispanded)

  if Config.keymaps.open_item.split.auto_close then
    toggle_list(list_type, true)
  end
end
function M.open_item_in_vsplit()
  local list_type = QfbookmarkUtils.is_loclist() and "loclist" or "quickfix"
  local is_center = Config.window.quickfix.actions.auto_center
  local is_ispanded = Config.window.quickfix.actions.auto_unfold
  QfbookmarkNav.handle_open("vsplit", is_center, is_ispanded)

  if Config.keymaps.open_item.vsplit.auto_close then
    toggle_list(list_type, true)
  end
end

function M.next_item()
  local is_center = Config.window.quickfix.actions.auto_center
  local is_ispanded = Config.window.quickfix.actions.auto_unfold
  QfbookmarkNav.handle_nav(false, "open", is_center, is_ispanded, false)
end
function M.prev_item()
  local is_center = Config.window.quickfix.actions.auto_center
  local is_ispanded = Config.window.quickfix.actions.auto_unfold
  QfbookmarkNav.handle_nav(true, "open", is_center, is_ispanded, false)
end
function M.next_hist_qf()
  QfbookmarkNav.handle_hist(Config.window.notify.plugin)
end
function M.prev_hist_qf()
  QfbookmarkNav.handle_hist(Config.window.notify.plugin, true)
end

local function clear_all_items_qflist()
  QfbookmarkUtils.info "✅ The item list has been cleared"
  vim.fn.setqflist {}
  vim.cmd.cclose()
end
local function clear_all_items_loclist()
  QfbookmarkUtils.info "✅ The item list has been cleared"
  vim.fn.setloclist(0, {}, "r")
  vim.cmd.lclose()
end

function M.delete_all_items()
  if QfbookmarkUtils.is_loclist() then
    clear_all_items_loclist()
  else
    clear_all_items_qflist()
  end
end
function M.delete_item()
  local curqfidx = vim.fn.line "."

  local data_lists = {}
  data_lists = QfbookmarkUtils.get_list_qf(QfbookmarkUtils.is_loclist()).items

  local close_cmd = QfbookmarkUtils.is_loclist() and "lclose" or "cclose"
  local open_cmd = QfbookmarkUtils.is_loclist() and Config.window.quickfix.lopen or Config.window.quickfix.copen

  local count = vim.v.count
  if count == 0 then
    count = 1
  end
  if count > #data_lists then
    count = #data_lists
  end

  local item = vim.api.nvim_win_get_cursor(0)[1]
  for _ = item, item + count - 1 do
    table.remove(data_lists, item)
  end

  if #data_lists ~= 0 then
    local title = QfbookmarkUtils.get_title_qf(QfbookmarkUtils.is_loclist())

    ---@type QFBookLists
    local list_items = {
      items = data_lists,
      title = title,
    }
    QfbookmarkUtils.save_to_qf(list_items, QfbookmarkUtils.is_loclist())

    if QfbookmarkUtils.is_loclist() then
      vim.cmd(string.format("%slfirst", curqfidx))
    else
      vim.cmd(string.format("%scfirst", curqfidx))
    end

    vim.schedule(function()
      vim.cmd(open_cmd)
    end)
  elseif #data_lists == 0 then
    vim.api.nvim_command(close_cmd)
  end
end

-- ┏╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍┓
-- ╏                                INTEGRATIONS                                 ╏
-- ┗╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍┛

function M.integrations_trouble_qflist()
  if Config.keymaps.integrations.trouble.enabled then
    local trouble = require "qfbookmark.integrations.trouble"
    if vim.bo.filetype == "qf" then
      trouble.handle_toggle_qf(false, "quickfix")
    end
    if vim.bo.filetype == "trouble" then
      trouble.handle_toggle_qf(true, "quickfix")
    end
  end
end
function M.integrations_trouble_loclist()
  if Config.keymaps.integrations.trouble.enabled then
    local trouble = require "qfbookmark.integrations.trouble"
    if vim.bo.filetype == "qf" then
      if QfbookmarkUtils.is_loclist() then
        trouble.handle_toggle_qf(false, "loclist")
      end
    end
    if vim.bo.filetype == "trouble" then
      trouble.handle_toggle_qf(true, "loclist", true)
    end
  end
end
function M.integrations_grugfar()
  local keymap_grugfar_opts = Config.keymaps.integrations.grugfar
  if keymap_grugfar_opts.enabled then
    local grugfar = require "qfbookmark.integrations.grugfar"
    if QfbookmarkUtils.is_loclist() then
      grugfar.handle_toggle_qf("loclist", false, true)
    else
      grugfar.handle_toggle_qf("quickfix", false)
    end
  end
end
function M.integrations_copyline()
  local bufnr = vim.api.nvim_get_current_buf()
  if not exclude_buf(bufnr) then
    QfbookmarkUtils.warn "Can’t perform this action. This buffer is excluded."
    return
  end

  local keymap_copyline_opts = Config.keymaps.integrations.copyline
  if keymap_copyline_opts.enabled then
    local line_opts = QfbookmarkUtils.get_line_pos_col_buffer()
    local filename = vim.api.nvim_buf_get_name(bufnr)

    local line_format = string.format("%s:%s:%s", filename, line_opts.line, line_opts.col)
    vim.fn.setreg("+", line_format, "c")

    QfbookmarkUtils.info "Line under cursor copied!"
  end
end

-- ┏╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍┓
-- ╏                                    NOTE                                     ╏
-- ┗╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍┛

local is_open_global_note
local window_command

local function __note()
  local note = require "qfbookmark.note"
  local cfg_note = Config.window.note
  note.handle_open(is_open_global_note, window_command, cfg_note)
end
function M.toggle_open_note_global()
  if not window_command and type(Config.window.note.open_cmd) ~= "table" then
    window_command = QfbookmarkWindow.get_size_note_window(Config.window.note)
  end

  is_open_global_note = true
  __note()
end
function M.toggle_open_note_local()
  if not window_command and type(Config.window.note.open_cmd) ~= "table" then
    window_command = QfbookmarkWindow.get_size_note_window(Config.window.note)
  end
  is_open_global_note = false
  __note()
end

-- ┏╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍┓
-- ╏                                   LAYOUT                                    ╏
-- ┗╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍┛

function M.move_layout_qf_up()
  if not Config.window.quickfix.enabled then
    return
  end
  QfbookmarkWindow.move_to("above", function(list_type)
    toggle_list(list_type, false)
  end)
end
function M.move_layout_qf_down()
  if not Config.window.quickfix.enabled then
    return
  end
  QfbookmarkWindow.move_to("bottom", function(list_type)
    toggle_list(list_type, false)
  end)
end

local was_warn = false

function M.toggle_rotate_note_window()
  if type(Config.window.note.open_cmd) == "table" and Config.window.note.open_cmd.mode == "float" then
    if not was_warn then
      QfbookmarkUtils.warn "This action is cancelled because a floating note window is in use"
      was_warn = true
    end
    return
  end

  local next_win_layout = QfbookmarkWindow.get_next_rotate_note_window()

  window_command = next_win_layout
  __note()
end

return M
