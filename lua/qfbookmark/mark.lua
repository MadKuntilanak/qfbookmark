local Config = require("qfbookmark.config").defaults
local QfbookmarkUtils = require "qfbookmark.utils"
local QfbookmarkTreesitter = require "qfbookmark.treesitter"
local QfbookmarkMarkVisual = require "qfbookmark.visual"
local QfbookmarkPaths = require "qfbookmark.path"
local QfbookmarkPathUtils = require "qfbookmark.path.utils"

local M = {
  extmarks_name = "QfbookmarkMark",
  ns = 0,
}

M.dirty = false

---@type integer ms timestamp of last branch check (for debounce)
local last_check = 0

---@type integer minimum ms between branch checks
local CHECK_INTERVAL = 1500

---@type uv.uv_timer_t?
M.timer = assert(vim.uv.new_timer())

---@param bufnr integer
---@param lnum integer
---@return boolean
local function is_not_valid_line(bufnr, lnum)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  return lnum >= 0 and lnum < line_count
end

---@param bufnr integer
---@param lnum integer
---@param col integer
---@return boolean
local function is_not_valid_line_and_col(bufnr, lnum, col)
  if is_not_valid_line(bufnr, lnum) then
    return false
  end

  local text = vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)[1] or ""
  local line_len = #text
  return col >= 0 and col <= line_len
end

local function insert_sign_and_extmark(mark_lists, id, mark_mode, bufnr, lnum, extmarkspec, note)
  local _, is_has_mark = M.has_mark_data(mark_lists, mark_mode, id, bufnr)
  if is_has_mark then
    if mark_mode == "NOTE" then
      if note and #note > 0 then
        local note_annotation
        if type(note) == "table" then
          note_annotation = table.concat(note, " ")
        elseif type(note) == "string" then
          note_annotation = note
        end
        QfbookmarkMarkVisual.insert_extmark(id, mark_mode, bufnr, lnum, note_annotation)
      end
    else
      -- insert sign like mark, debug, etc
      QfbookmarkMarkVisual.insert_sign(id, mark_mode, bufnr, lnum, extmarkspec)
    end
  end
end

function M.mark_dirty()
  M.dirty = true
end

---@param mark_lists QFBookmarkBufferMark
---@param s_opts { bufnr?: integer, id?: integer, no_id?: boolean }
---@return { id: integer, mark_mode: QFBookMarkMode, extmarkspec: QFBookSpec, bufnr?: integer} | nil
function M.is_current_line_got_mark(mark_lists, s_opts)
  local bufnr = s_opts.bufnr or vim.api.nvim_get_current_buf()
  local no_id = s_opts.no_id or false

  if vim.tbl_isempty(mark_lists) then
    return
  end

  local extmark, sign, has_extmark, has_valid_sign

  if no_id then
    local line_opts = QfbookmarkUtils.get_line_pos_col_buffer()

    sign = QfbookmarkMarkVisual.get_sign_at_line(bufnr, line_opts.line)
    extmark = QfbookmarkMarkVisual.get_extmark_at_line(bufnr, line_opts.line)[1]

    has_valid_sign = sign and sign.group == Config.sign_group
    has_extmark = extmark ~= nil
  end

  for mark_mode, _ in pairs(mark_lists) do
    local mode_marks = mark_lists[mark_mode]
    for _, x in pairs(mode_marks) do
      local opts
      local extmarkspec = Config.extmarks.keywords[mark_mode]
      if has_valid_sign then
        if tonumber(x.line) == tonumber(sign.lnum) and sign.group == Config.sign_group then
          opts = {
            id = x.id,
            mark_mode = mark_mode,
            extmarkspec = extmarkspec,
            bufnr = mark_lists[mark_mode][x.id].bufnr,
          }
          return opts
        end
      elseif has_extmark then
        if tonumber(x.line) == tonumber(extmark.lnum) then
          opts = {
            id = x.id,
            mark_mode = mark_mode,
            extmarkspec = extmarkspec,
            bufnr = mark_lists[mark_mode][x.id].bufnr,
          }
          return opts
        end
      else
        local id = s_opts.id
        if mark_lists[mark_mode] and mark_lists[mark_mode][id] then
          opts = {
            id = id,
            mark_mode = mark_mode,
            extmarkspec = extmarkspec,
            bufnr = mark_lists[mark_mode][id].bufnr,
          }
          return opts
        end
      end
    end
  end
end

---@param mark_lists QFBookmarkBufferMark
---@param force_refresh boolean
---@param bufnr? integer
local function refresh_mark(mark_lists, force_refresh, bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not QfbookmarkUtils.exclude_default_filetype_dan_buftype(bufnr) then
    return
  end

  if force_refresh and not M.timer:is_active() then
    -- Stop the timer if it's running (safe to call even if not running)
    M.timer:stop()

    M.timer:start(
      Config.extmarks.throttle,
      0,
      vim.schedule_wrap(function()
        M.update_mark_sign(mark_lists, bufnr)
      end)
    )
  end
end

---@param mark_lists QFbookBufferMarkEntry[]
local function __save_marks(mark_lists, target_path)
  if not QfbookmarkPathUtils.is_file(target_path) then
    QfbookmarkPathUtils.create_file(target_path)
  end

  QfbookmarkUtils.save_table_to_file(mark_lists, target_path)
end

---@param mark_lists QFbookBufferMarkEntry[]
function M.save_marks(mark_lists, target_path, is_global)
  is_global = is_global or false

  target_path = target_path or QfbookmarkPaths.get_target_file_path(is_global)

  -- Remove saved file when there are no marks left
  if #mark_lists == 0 then
    if QfbookmarkPathUtils.is_file(target_path) then
      vim.fn.delete(target_path)
    end
    return
  end

  __save_marks(mark_lists, target_path)
end

--- Save current in-memory marks to the previously active branch file,
--- then load marks for the newly active branch file, and refresh
--- extmarks in all currently open buffers.
---@param mark_lists QFbookBufferMarkEntry[]
---@param new_root string
---@param new_branch string
function M.switch_to(mark_lists, new_root, new_branch)
  local current_root = QfbookmarkPaths.path_opts.current_root
  local current_branch = QfbookmarkPaths.path_opts.current_branch
  local dirty = M.dirty

  -- Nothing changed — skip
  if new_root == current_root and new_branch == current_branch then
    return
  end

  -- Save current marks before switching, but only if something changed
  if dirty and current_root and current_branch then
    local old_path = QfbookmarkPaths.resolve_marks_path(current_root, current_branch)
    M.save_marks(mark_lists, old_path)
    M.dirty = false
  end

  local new_path = QfbookmarkPaths.resolve_marks_path(new_root, new_branch, false, true)

  local is_empty = false

  -- Offer to seed from a sensible default when no marks exist yet for this branch.
  -- Most useful right after creating a new feature branch
  if vim.fn.filereadable(new_path) == 0 and new_root then
    is_empty = true

    -- return
    --   unplan: do I need this?
    --   local seed_choice = Config.get.something --> retrieve the user's preferred choice from the config
    --   if seed_choice then
    --     local choice = vim.fn.confirm(
    --       string.format("No marks found for branch '%s'. Copy marks from previous branch?", new_branch or "?"),
    --       "&Yes\n&No, start empty",
    --       2
    --     )
    --     if choice == 1 and current_root and current_branch then
    --       local old_path = QfbookmarkPaths.resolve_marks_path(current_root, current_branch)
    --       ...copy
    --     end
    --   end
  end

  QfbookmarkPaths.path_opts.current_root = new_root
  QfbookmarkPaths.path_opts.current_branch = new_branch

  local qf = require "qfbookmark.qf"

  -- Refresh extmarks/signs in every currently loaded buffer:
  -- 1. Clean up the sign first
  qf.__remove_all_signs()

  -- 2. Load a new sign
  qf.load_mark_lists(nil, true)
  qf.__resync_setup()

  local label = new_branch and (" · " .. new_branch) or ""
  local msg = "Marks reloaded: " .. label
  if is_empty then
    msg = msg .. " is empty.\nTry adding some marks first."
    QfbookmarkUtils.warn(msg)
    return
  end
  QfbookmarkUtils.info(msg)
end

--- Check whether the active branch/root has changed since last check,
--- and switch marks accordingly. Debounced via CHECK_INTERVAL.
---@param mark_lists QFbookBufferMarkEntry[]
---@param force boolean  skip debounce, always check
function M.check_and_reload(mark_lists, force)
  local now = vim.uv.now()

  if not force and (now - last_check) < CHECK_INTERVAL then
    return
  end

  last_check = now

  local _, root, branch = QfbookmarkPaths.resolve_active_marks_file()
  if root and branch then
    M.switch_to(mark_lists, root, branch)
  end
end

local autocmds_set_once = false

---@param mark_lists QFBookmarkBufferMark
---@param force_set? boolean
function M.setup_mark_autocmds(mark_lists, force_set)
  force_set = force_set or false

  if autocmds_set_once and not force_set then
    return
  end

  autocmds_set_once = true

  QfbookmarkUtils.clear_autocmd_group(Config.sign_group .. "RefreshMark")
  local refresh_group = QfbookmarkUtils.create_augroup_name "RefreshMark"

  vim.api.nvim_create_autocmd("BufReadPost", {
    group = refresh_group,
    pattern = "*",
    callback = function(ctx)
      refresh_mark(mark_lists, true, ctx.buf)
    end,
    desc = "qfbookmark: refresh marks after read post buffer",
  })

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = refresh_group,
    pattern = "*",
    callback = function(ctx)
      refresh_mark(mark_lists, true, ctx.buf)
    end,
    desc = "qfbookmark: refresh marks after text changed or edited",
  })
end

---@param mark_lists QFBookmarkBufferMark
---@param mark_mode QFBookMarkMode
---@param extmarkspec QFBookSpec
---@param id integer
---@param bufnr? integer
---@param lnum integer
---@param col integer
---@param text string
---@param note? string[]
---@param inserted_at? integer
---@return QFBookmarkBufferMark | nil
local function register_mark(mark_lists, mark_mode, extmarkspec, id, bufnr, lnum, col, text, inserted_at, note)
  M.mark_dirty()

  note = note or {}

  bufnr = bufnr or vim.api.nvim_get_current_buf()
  inserted_at = inserted_at or os.time()

  local filename = vim.api.nvim_buf_get_name(bufnr)

  -- Validate line before registering
  if is_not_valid_line_and_col(bufnr, lnum, col) then
    return nil
  end

  if not mark_lists[mark_mode] then
    mark_lists[mark_mode] = {}
  end

  if not mark_lists[mark_mode][id] then
    local cwd = vim.uv.cwd()
    local filename_trim = filename:gsub(cwd .. "/", "")
    local harpoon = string.format("%s:%s:%s:%s", filename_trim, lnum, col, mark_mode)

    mark_lists[mark_mode][id] = {
      bufnr = bufnr,
      filename = filename,
      line = lnum,
      col = col,
      text = QfbookmarkUtils.strip_whitespace(text),
      harpoon = harpoon,
      mark_mode = mark_mode,
      fn_name = QfbookmarkTreesitter.resolve_symbol(bufnr, lnum, col or 0),
      inserted_at = inserted_at, -- Unix timestamp (seconds); consistent across sessions
      id = id,
      note = note,
    }
  end

  insert_sign_and_extmark(mark_lists, id, mark_mode, bufnr, lnum, extmarkspec, note)
  return mark_lists
end

---@param mark_lists QFBookmarkBufferMark
---@param mark_mode QFBookMarkMode
---@param extmarkspec QFBookSpec
---@param id integer
---@param bufnr? integer
---@param lnum integer
---@param col integer
---@param text string
---@param is_open_window boolean
---@return QFBookmarkBufferMark | nil
function M.place_next_mark(mark_lists, mark_mode, extmarkspec, id, bufnr, lnum, col, text, is_open_window)
  if mark_mode == "NOTE" then
    local target_mark = mark_lists[mark_mode] and mark_lists[mark_mode][id] or {}

    local QfbookmarkUI = require "qfbookmark.ui"
    QfbookmarkUI.place_mark_annotation(mark_lists, function(raw_lines)
      local note = raw_lines
      local inserted_at = os.time()
      if is_open_window then
        if mark_lists[mark_mode][id] then
          mark_lists[mark_mode][id].note = note
        end
      end
      register_mark(mark_lists, mark_mode, extmarkspec, id, bufnr, lnum, col, text, inserted_at, note)
    end, { load_chunk = is_open_window, chunk = target_mark })
    return
  end
  return register_mark(mark_lists, mark_mode, extmarkspec, id, bufnr, lnum, col, text)
end

---@param mark_lists QFBookmarkBufferMark
---@param bufnr integer
function M.update_mark_sign(mark_lists, bufnr)
  if vim.tbl_isempty(mark_lists) then
    return
  end

  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local filename = vim.api.nvim_buf_get_name(bufnr)

  for mode, mode_list in pairs(mark_lists) do
    for id, mark in pairs(mode_list) do
      -- Resolve warn type hint from id
      local _id = tonumber(id)
      if not _id then
        return
      end

      if mark.filename == filename then
        if is_not_valid_line_and_col(bufnr, mark.line, mark.col) then
          M.delete_mark(mark_lists, mode, _id, bufnr)
        else
          register_mark(
            mark_lists,
            mode,
            Config.extmarks.keywords[mode],
            _id,
            bufnr,
            mark.line,
            mark.col,
            mark.text,
            mark.inserted_at,
            mark.note
          )
        end
      end
    end
  end
end

---@param mark_lists QFBookmarkBufferMark
---@return  { id: integer, mark_mode: QFBookMarkMode, extmarkspec: QFBookSpec, bufnr?: integer} | nil
function M.get_mark_id(mark_lists)
  return M.is_current_line_got_mark(mark_lists, { no_id = true })
end

--- Check whether mark data exists in the bookmark storage.
--- This only checks the internal `mark_lists` table and does not inspect
--- placed signs or extmarks in the buffer.
---@param mark_lists QFBookmarkBufferMark
---@param mark_mode QFBookMarkMode
---@param id? integer
---@param bufnr? integer
---@return integer|nil, boolean
function M.has_mark_data(mark_lists, mark_mode, id, bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not mark_lists[mark_mode] or not mark_lists[mark_mode][id] then
    return nil, false
  end

  return id, true
end

--- Remove a mark entry and its associated sign.
--- Returns `true` when the mark exists and is successfully removed from
--- the internal storage; otherwise returns `false`.
---@param mark_lists QFBookmarkBufferMark
---@param mark_mode QFBookMarkMode
---@param id? integer
---@param bufnr? integer
---@return boolean
function M.delete_mark(mark_lists, mark_mode, id, bufnr)
  M.mark_dirty()

  local _, ok = M.has_mark_data(mark_lists, mark_mode, id, bufnr)
  if not ok or not id then
    return false
  end

  mark_lists[mark_mode][id] = nil
  QfbookmarkMarkVisual.delete_sign(id, bufnr)
  QfbookmarkMarkVisual.delete_extmark(id, bufnr)
  return true
end

--- Update an existing mark annotation using mark id
---
---@param mark_lists QFBookmarkBufferMark
---@param mark_mode QFBookMarkMode
---@param extmarkspec QFBookSpec
---@param id integer
---@return QFBookmarkBufferMark|nil
function M.update_mark_annotation(mark_lists, mark_mode, extmarkspec, id)
  local line_opts = QfbookmarkUtils.get_line_pos_col_buffer()

  local bufnr = vim.api.nvim_get_current_buf()

  if not id then
    QfbookmarkUtils.warn "Mark ID is required"
    return nil
  end

  return M.place_next_mark(
    mark_lists,
    mark_mode,
    extmarkspec,
    id,
    bufnr,
    line_opts.line,
    line_opts.col,
    line_opts.text,
    true
  )
end

--- Add a new mark at the current cursor position.
--- Uses the current buffer, line, and column to create a mark and store
--- it through `place_next_mark()`.
---@param mark_lists QFBookmarkBufferMark
---@param mark_mode QFBookMarkMode
---@param extmarkspec QFBookSpec
---@param is_open_window? boolean
---@return QFBookmarkBufferMark|nil
function M.add_mark(mark_lists, mark_mode, extmarkspec, is_open_window)
  is_open_window = is_open_window or false

  local line_opts = QfbookmarkUtils.get_line_pos_col_buffer()

  local bufnr = vim.api.nvim_get_current_buf()
  local id = tonumber(line_opts.line .. bufnr)
  if not id then
    QfbookmarkUtils.warn "Unexpected error while getting line number"
    return nil
  end

  return M.place_next_mark(
    mark_lists,
    mark_mode,
    extmarkspec,
    id,
    bufnr,
    line_opts.line,
    line_opts.col,
    line_opts.text,
    is_open_window
  )
end

---@param bufnr integer
---@param line integer
---@param col integer
---@param text string
---@param mark_mode QFBookMarkMode
function M.add_mark_at(bufnr, line, col, text, mark_mode)
  local allow_mark_mode = { "MARK", "DEBUG", "FIX", "NOTE" }
  assert(
    vim.tbl_contains(allow_mark_mode, mark_mode),
    string.format("invalid mark_mode '%s', expected one of: %s", mark_mode, table.concat(allow_mark_mode, ", "))
  )

  M.mark_dirty()

  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local id = tonumber(line .. bufnr)

  if not id then
    QfbookmarkUtils.warn "Unexpected error while getting line number"
    return
  end

  local extmarkspec = Config.extmarks.keywords[mark_mode]

  local qf = require "qfbookmark.qf"
  local mark_lists = qf.get_buffers()

  -- Check whether any marks exist before registering a new one.
  -- If this is the first mark, refresh the mark list so the new
  -- entry is displayed immediately.
  local had_marks = false

  if mark_lists then
    for _, marks in pairs(mark_lists) do
      if next(marks) ~= nil then
        had_marks = true
        break
      end
    end
  end

  if not mark_lists[mark_mode] then
    mark_lists[mark_mode] = {}
  end

  if mark_lists[mark_mode][id] then
    return false
  end

  register_mark(mark_lists, mark_mode, extmarkspec, id, bufnr, line, col, text)

  if not had_marks then
    for _, mark in pairs(mark_lists[mark_mode]) do
      qf.load_mark_lists({ mark }, true)
    end
  end

  return true
end

return M
