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

---@type QFBookmarkBufferMark
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

  if not status_autocmd_enabled then
    return
  end

  QfbookmarkUtils.clear_autocmd_group(Config.sign_group .. "SaveMark")
  local save_group = QfbookmarkUtils.create_augroup_name "SaveMark"

  vim.api.nvim_create_autocmd({ "VimLeavePre" }, {
    group = save_group,
    callback = function()
      local mark_lists = get_lists_marks()
      QfbookmarkBookmark.save_marks(mark_lists)
    end,
  })

  QfbookmarkUtils.clear_autocmd_group(Config.sign_group .. "BranchWatch")
  local path_group = QfbookmarkUtils.create_augroup_name "BranchWatch"

  --- unplan: no need this?
  --- DirChanged fires immediately on `:cd`, `:lcd`, or `:tcd` — covers the
  --- case where the user explicitly changes Neovim's working directory.
  -- vim.api.nvim_create_autocmd("DirChanged", {
  --   group = path_group,
  --   callback = function()
  --     M.check_and_reload(mark_lists, true)
  --   end,
  --   desc = "qfbookmark: reload marks when cwd changes",
  -- })

  --- FocusGained fires when Neovim regains focus (e.g. switching back from
  --- a terminal where `git checkout` was run). Debounced to avoid running
  --- git commands on every alt-tab.
  vim.api.nvim_create_autocmd("FocusGained", {
    group = path_group,
    callback = function()
      QfbookmarkBookmark.check_and_reload(M.get_current_mark_lists(), false)
    end,
    desc = "qfbookmark: reload marks when regaining focus (debounced)",
  })

  --- BufEnter covers the case where the user opens a file belonging to a
  --- different git repository than the one they were just working in,
  --- without ever leaving Neovim's focus (e.g. via :edit, telescope, etc).
  vim.api.nvim_create_autocmd("BufEnter", {
    group = path_group,
    callback = function(args)
      -- skip special buffers (popups, terminals, quickfix, etc.)
      local buftype = vim.bo[args.buf].buftype
      if buftype ~= "" then
        return
      end
      QfbookmarkBookmark.check_and_reload(M.get_current_mark_lists(), false)
    end,
    desc = "qfbookmark: reload marks when entering a buffer from a different project",
  })
end

local function remove_augroup()
  if not status_autocmd_enabled then
    if M.buffers and #M.buffers == 0 then
      local list_augroups = { "RefreshMark", "SaveMark", "BranchWatch" }
      for _, au_group in pairs(list_augroups) do
        QfbookmarkUtils.clear_autocmd_group(Config.sign_group .. au_group)
      end
    end
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
end
local function sync_marks_harpoon()
  reset_harpoon_list()

  if #M.mark_lists_harpoon > 0 then
    status_autocmd_enabled = true
    recall_augroup()
  else
    status_autocmd_enabled = false
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

function M.__remove_all_signs()
  local mark_lists_master = M.get_buffers()

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
      goto continue
    end

    local filename = vim.api.nvim_buf_get_name(bufnr)

    for mode, mode_list in pairs(mark_lists_master) do
      for id, mark in pairs(mode_list) do
        local mark_id = tonumber(id)

        if mark_id and mark.filename == filename then
          -- if is_not_valid_line_and_col(bufnr, mark.line, mark.col) then
          QfbookmarkBookmark.delete_mark(mark_lists_master, mode, mark_id, bufnr)
          -- end
        end
      end
    end
    ::continue::
  end
end

---@param mark_lists? QFbookBufferMarkEntry[]
---@param is_renew? boolean
function M.load_mark_lists(mark_lists, is_renew)
  is_renew = is_renew or false

  mark_lists = mark_lists or QfbookmarkPaths.get_data_marks_from_local_project(is_renew)

  if not mark_lists or vim.tbl_isempty(mark_lists) then
    return
  end

  if is_renew then
    M.buffers = {}
    M.mark_lists = {}
    M.mark_lists_harpoon = {}
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
end

--- Performs initial mark synchronization during setup.
--- Loads existing marks, refreshes the mark cache, and updates bookmark
--- signs for all loaded buffers.
function M.__resync_setup()
  sync_marks_harpoon()
  M.invalidate_mark_cache()

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      QfbookmarkBookmark.update_mark_sign(M.buffers, bufnr)
    end
  end
end

function M.setup_autocmds()
  QfbookmarkBookmark.mark_dirty()

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
      M.load_mark_lists()
      M.__resync_setup()
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

---@param mark_mode QFBookMarkMode
local function add_sign(mark_mode)
  local mark_lists = M.buffers
  local bufnr = vim.api.nvim_get_current_buf()

  if not exclude_buf(bufnr) then
    QfbookmarkUtils.warn "Can't perform this action. This buffer is excluded."
    return
  end

  local extmarkspec = Config.extmarks.keywords[mark_mode]

  local __mark = QfbookmarkBookmark.get_mark_id(mark_lists)
  local id
  if __mark then
    id = __mark.id
  end

  local _, has_note = QfbookmarkBookmark.has_mark_data(mark_lists, "NOTE", id)
  local _, has_same_mode = QfbookmarkBookmark.has_mark_data(mark_lists, mark_mode, id)

  local has_other_mark = false
  for _, mode in pairs(MARK_MODE) do
    if mode ~= "NOTE" and mode ~= mark_mode then
      local _, has = QfbookmarkBookmark.has_mark_data(mark_lists, mode, id)
      if has then
        has_other_mark = true
        break
      end
    end
  end

  -- Open the note window instead of toggling,
  -- to update note data_annotation
  if has_same_mode and mark_mode == "NOTE" then
    QfbookmarkBookmark.update_mark_annotation(mark_lists, mark_mode, extmarkspec, id)
    sync_marks_harpoon()
    M.invalidate_mark_cache()
    vim.schedule(function()
      mark_lists = get_lists_marks()
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
  QfbookmarkBookmark.add_mark(mark_lists, mark_mode, extmarkspec, false)
  sync_marks_harpoon()
  M.invalidate_mark_cache()

  vim.schedule(function()
    mark_lists = get_lists_marks()
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

  local mark_lists = M.get_buffers()

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
    QfbookmarkUtils.echo_empty_mark()
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
-- function M.debug_qf()
--   QfbookmarkUtils.info(vim.inspect(M.buffers))
--   QfbookmarkUtils.info(vim.inspect(M.mark_lists))
--   QfbookmarkUtils.info(vim.inspect(M.mark_lists_harpoon))
-- end

---@return QFBookmarkBufferMark
function M.get_buffers()
  local status_mark = M.status_mark()
  if not status_mark then
    return {}
  end
  return M.buffers
end

--- Flatten the current in-memory M.buffers (keyed by mark_mode -> id) into
--- a plain array.
--- Always call this right before saving or comparing marks, rather than
--- capturing a stale snapshot in a closure, M.buffers mutates continuously as
--- marks are added/deleted/cleared.
---@return QFbookBufferMarkEntry[]
function M.get_current_mark_lists()
  local list = {}
  for _, marks_by_id in pairs(M.buffers) do
    for _, m in pairs(marks_by_id) do
      list[#list + 1] = m
    end
  end
  return list
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

    -- if harpoon_vals.selected then
    --   local selected_marks = harpoon_vals.data
    --   if Config.window.mark.on_send then
    --     Config.window.mark.on_send(selected_marks)
    --   end
    --   return
    -- end

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

local qf_selected = {}

---@param is_loc boolean
---@return QFBookmarkLists
local function __get_data(is_loc)
  local qf_result

  if is_loc then
    local data = QfbookmarkUtils.get_data_qf(true)
    qf_result = data.location
  else
    local data = QfbookmarkUtils.get_data_qf()
    qf_result = data.quickfix
  end

  return qf_result
end

function M.qf_toggle_selection()
  local cur_line_nr = vim.api.nvim_win_get_cursor(0)[1]

  local is_loc = QfbookmarkUtils.is_loclist()

  local qf_result = __get_data(is_loc)

  local item = qf_result.items[cur_line_nr]
  if not item then
    return
  end

  -- Unique key per item
  local key = cur_line_nr

  if qf_selected[key] then
    qf_selected[key] = nil
  else
    qf_selected[key] = true
  end

  local QfbookmarkMarkVisual = require "qfbookmark.visual"
  QfbookmarkMarkVisual.apply_qf_selection_highlights(qf_selected, is_loc)
end

---@return table[]  selected quickfix items
function M.get_qf_selected()
  local is_loc = QfbookmarkUtils.is_loclist()

  local qf_result = __get_data(is_loc)

  local result = {}

  for idx, item in ipairs(qf_result.items) do
    if qf_selected[idx] then
      result[#result + 1] = item
    end
  end

  if #result == 0 then
    local cur_line_nr = vim.api.nvim_win_get_cursor(0)[1]
    result = { qf_result.items[cur_line_nr] }
  end

  return result
end

function M.diselect_all()
  local is_loc = QfbookmarkUtils.is_loclist()

  local qf_result = __get_data(is_loc)

  for idx, _ in ipairs(qf_result.items) do
    if qf_selected[idx] then
      qf_selected[idx] = nil
    end
  end

  local QfbookmarkMarkVisual = require "qfbookmark.visual"
  QfbookmarkMarkVisual.apply_qf_selection_highlights(qf_selected, is_loc)
end

---@param list_type QFBookListType
local function add_item(list_type)
  local bufnr = vim.api.nvim_get_current_buf()

  if not exclude_buf(bufnr) then
    QfbookmarkUtils.warn "Can’t perform this action. This buffer is excluded."
    return
  end

  local is_location_target = list_type == "loclist"
  local cmd_ = is_location_target and { "lclose", Config.window.quickfix.actions.lopen, "loclist" }
    or { "cclose", Config.window.quickfix.actions.copen, "qflist" }

  local title = QfbookmarkUtils.get_title_qf(QfbookmarkUtils.is_loclist())
  if title and title:match "setqflist" or #title == 0 then
    title = "Add item into " .. (is_location_target and "lf" or "qf")
  end

  local pos = vim.api.nvim_win_get_cursor(0)
  local lnum = pos[1]
  local col = pos[2]

  ---@type QFBookmarkLists
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
  local is_loc = list_type == "loclist"
  local cmd = is_loc and { Config.window.quickfix.actions.lopen, "LocList" }
    or { Config.window.quickfix.actions.copen, "QuickFix" }

  if QfbookmarkUtils.is_loclist() then
    QfbookmarkUtils.warn("Renaming the title is not supported in the " .. cmd[2] .. ",\nOnly in Quickfix")
    return
  end

  local title = string.format("📝 Rename %s Title", cmd[2])
  QfbookmarkUI.saveqf_popup(title, "", "rename", is_loc, function(input_msg)
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

  local is_loc = list_type == "loclist"
  local cmd_ = is_loc and { "lclose", Config.window.quickfix.actions.lopen }
    or { "cclose", Config.window.quickfix.actions.copen }
  local is_open, qf_or_loclist = QfbookmarkUtils.is_vim_list_open(true)

  if (is_open and (list_type == qf_or_loclist)) or force_close then
    vim.fn.win_gotoid(last_winid)
    vim.cmd(cmd_[1])
    return
  end

  if vim.bo.filetype == "qf" then
    vim.cmd.wincmd "p"
  end

  local list = QfbookmarkUtils.get_list_qf(is_loc)

  if not vim.tbl_isempty(list.items) then
    last_winid = vim.fn.win_getid()
    vim.cmd(cmd_[2])
    return
  end

  local msg_prefix = (is_loc and "LocList" or "QuickFix")
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

  if Config.window.quickfix.actions.default.auto_close then
    toggle_list(list_type, true)
  end
end
function M.open_item_in_tab()
  local list_type = QfbookmarkUtils.is_loclist() and "loclist" or "quickfix"
  local is_center = Config.window.quickfix.actions.auto_center
  local is_ispanded = Config.window.quickfix.actions.auto_unfold
  QfbookmarkNav.handle_open("tabnew", is_center, is_ispanded)

  if Config.window.quickfix.actions.tab.auto_close then
    toggle_list(list_type, true)
  end
end
function M.open_item_in_split()
  local list_type = QfbookmarkUtils.is_loclist() and "loclist" or "quickfix"
  local is_center = Config.window.quickfix.actions.auto_center
  local is_ispanded = Config.window.quickfix.actions.auto_unfold
  QfbookmarkNav.handle_open("split", is_center, is_ispanded)

  if Config.window.quickfix.actions.split.auto_close then
    toggle_list(list_type, true)
  end
end
function M.open_item_in_vsplit()
  local list_type = QfbookmarkUtils.is_loclist() and "loclist" or "quickfix"
  local is_center = Config.window.quickfix.actions.auto_center
  local is_ispanded = Config.window.quickfix.actions.auto_unfold
  QfbookmarkNav.handle_open("vsplit", is_center, is_ispanded)

  if Config.window.quickfix.actions.vsplit.auto_close then
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
  local selected = M.get_qf_selected()
  if #selected > 0 then
    M.diselect_all()
  end

  QfbookmarkNav.handle_hist(Config.window.notify.plugin)
end

function M.prev_hist_qf()
  local selected = M.get_qf_selected()
  if #selected > 0 then
    M.diselect_all()
  end

  QfbookmarkNav.handle_hist(Config.window.notify.plugin, true)
end

local function clear_all_items_qflist()
  QfbookmarkUtils.info "✅ The item list has been cleared"
  vim.fn.setqflist {}
  vim.cmd.cclose()
  M.diselect_all()
end
local function clear_all_items_loclist()
  QfbookmarkUtils.info "✅ The item list has been cleared"
  vim.fn.setloclist(0, {}, "r")
  vim.cmd.lclose()
  M.diselect_all()
end

function M.delete_all_items()
  if QfbookmarkUtils.is_loclist() then
    clear_all_items_loclist()
  else
    clear_all_items_qflist()
  end
end
function M.delete_item()
  local is_loc = QfbookmarkUtils.is_loclist()

  local data_lists = QfbookmarkUtils.get_list_qf(is_loc).items

  local mode = vim.fn.mode(1) -- :h mode()

  local selected = M.get_qf_selected()

  local is_visual = false

  if mode == "v" or mode == "V" then
    local from, to
    from, to = vim.fn.line ".", vim.fn.line "v"
    if from > to then
      from, to = to, from
    end

    for i = from, to do
      local item = data_lists[i]
      if item then
        data_lists[i] = nil
      end
    end

    is_visual = true
  elseif #selected > 0 then
    for dlist_idx, dlist in pairs(data_lists) do
      for _, sel in pairs(selected) do
        if
          sel.filename == vim.api.nvim_buf_get_name(dlist.bufnr)
          and sel.col == dlist.col
          and sel.lnum == dlist.lnum
        then
          if data_lists[dlist_idx] then
            data_lists[dlist_idx] = nil
          end
          if qf_selected[dlist_idx] then
            qf_selected[dlist_idx] = nil
          end
        end
      end
    end

    local QfbookmarkMarkVisual = require "qfbookmark.visual"
    QfbookmarkMarkVisual.apply_qf_selection_highlights(qf_selected, is_loc)
  else
    local count = vim.v.count

    if count == 0 then
      count = 1
    end
    if count > #data_lists then
      count = #data_lists
    end

    local cur_line_nr = vim.api.nvim_win_get_cursor(0)[1]

    for _ = cur_line_nr, cur_line_nr + count - 1 do
      table.remove(data_lists, cur_line_nr)
    end
  end

  local curqfidx = vim.fn.line "."

  local title = QfbookmarkUtils.get_title_qf(is_loc)

  ---@type QFBookmarkLists
  local list_items = {
    items = data_lists,
    title = title,
  }

  -- Exit visual mode before refreshing the quickfix list.
  if is_visual then
    vim.api.nvim_input "<Esc>"
  end

  QfbookmarkUtils.save_to_qf(list_items, is_loc)

  if #data_lists > 0 then
    local target_line = math.min(curqfidx, #data_lists)
    pcall(vim.api.nvim_win_set_cursor, 0, { target_line, 0 })

    if #selected > 0 then
      local QfbookmarkMarkVisual = require "qfbookmark.visual"
      QfbookmarkMarkVisual.apply_qf_selection_highlights(qf_selected, is_loc)
    end
  elseif #data_lists == 0 then
    local close_cmd = is_loc and "lclose" or "cclose"
    vim.api.nvim_command(close_cmd)
    M.diselect_all()
  end
end

-- ┏╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍┓
-- ╏                                INTEGRATIONS                                 ╏
-- ┗╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍┛

function M.integrations_trouble_qflist()
  if not Config.keymaps.quickfix.integrations.trouble.enabled then
    return
  end

  local trouble = require "qfbookmark.integrations.trouble"
  if vim.bo.filetype == "qf" then
    trouble.handle_toggle_qf(false, "quickfix")
  end
  if vim.bo.filetype == "trouble" then
    trouble.handle_toggle_qf(true, "quickfix")
  end
end
function M.integrations_trouble_loclist()
  if not Config.keymaps.quickfix.integrations.trouble.enabled then
    return
  end

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
function M.integrations_grugfar()
  if not Config.keymaps.quickfix.integrations.grugfar.enabled then
    return
  end

  local grugfar = require "qfbookmark.integrations.grugfar"
  if QfbookmarkUtils.is_loclist() then
    grugfar.handle_toggle_qf("loclist", false, true)
  else
    grugfar.handle_toggle_qf("quickfix", false)
  end
end
function M.integrations_copyline()
  local bufnr = vim.api.nvim_get_current_buf()
  if not exclude_buf(bufnr) then
    QfbookmarkUtils.warn "Can’t perform this action. This buffer is excluded."
    return
  end

  local keymap_copyline_opts = Config.keymaps.quickfix.integrations.copyline
  if keymap_copyline_opts and keymap_copyline_opts.enabled then
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

local window_command

local function __note(is_global, is_add_to)
  is_global = is_global or false
  is_add_to = is_add_to or false

  local note = require "qfbookmark.note"
  local cfg_note = Config.window.note

  if not window_command and cfg_note.mode ~= "float" then
    window_command = QfbookmarkWindow.get_size_note_window(Config.window.note)
  end

  local is_insert_to = false
  if is_add_to then
    is_insert_to = true
    note.add_to_note "todo"
  end

  note.handle_open(is_global, cfg_note, is_insert_to, window_command)
end
function M.add_note_to_global()
  if not Config.window.note.enabled then
    return
  end
  __note(true, true)
end
function M.add_note_to_local()
  if not Config.window.note.enabled then
    return
  end
  __note(false, true)
end
function M.toggle_open_note_global()
  if not Config.window.note.enabled then
    return
  end
  __note(true)
end
function M.toggle_open_note_local()
  if not Config.window.note.enabled then
    return
  end
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

function M.toggle_rotate_note_window()
  if not Config.window.note.enabled then
    return
  end

  if Config.window.note.mode == "float" then
    QfbookmarkUtils.warn "This action is cancelled because a floating note window is in use"
    return
  end

  local next_win_layout = QfbookmarkWindow.get_next_rotate_note_window()

  window_command = next_win_layout

  __note()
end

return M
