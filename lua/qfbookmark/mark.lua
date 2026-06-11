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
      QfbookmarkMarkVisual.insert_sign(id, mark_mode, bufnr, lnum, extmarkspec)
    end
  end
end

---@param mark_lists QFbookBufferMark
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

---@param mark_lists QFbookBufferMark
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

local is_setup_path = false

---@param mark_lists QFbookBufferMarkEntry[]
local function __save_marks(mark_lists)
  local is_save_global_mark = false
  if #mark_lists == 0 then
    local path_local_cwd = QfbookmarkPaths.get_target_path_with_gitcwd(is_save_global_mark)
    if QfbookmarkPathUtils.is_file(path_local_cwd) then
      vim.system { "rm", path_local_cwd }
    end
    return
  end

  if not is_setup_path then
    QfbookmarkPaths.setup_path(is_save_global_mark)
    is_setup_path = true
  end

  local path_git_cwd = QfbookmarkPaths.get_target_path_with_gitcwd(is_save_global_mark)
  if not QfbookmarkPathUtils.is_file(path_git_cwd) then
    QfbookmarkPathUtils.create_file(path_git_cwd)
  end

  QfbookmarkUtils.save_table_to_file(mark_lists, path_git_cwd)
end

---@param mark_lists QFbookBufferMarkEntry[]
function M.save_marks(mark_lists)
  __save_marks(mark_lists)
end

local autocmds_set = false

---@param mark_lists QFbookBufferMark
---@param force_set? boolean
function M.setup_mark_autocmds(mark_lists, force_set)
  force_set = force_set or false

  if autocmds_set and not force_set then
    return
  end

  autocmds_set = true

  vim.api.nvim_create_autocmd("BufReadPost", {
    group = QfbookmarkUtils.create_augroup_name "RefreshMark",
    pattern = "*",
    callback = function(ctx)
      refresh_mark(mark_lists, true, ctx.buf)
    end,
  })

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = QfbookmarkUtils.create_augroup_name "RefreshMark",
    pattern = "*",
    callback = function(ctx)
      refresh_mark(mark_lists, true, ctx.buf)
    end,
  })
end

---@param mark_lists QFbookBufferMark
---@param mark_mode QFBookMarkMode
---@param extmarkspec QFBookSpec
---@param id integer
---@param bufnr? integer
---@param lnum integer
---@param col integer
---@param text string
---@param note? string[]
---@param inserted_at? integer
---@return QFbookBufferMark | nil
local function register_mark(mark_lists, mark_mode, extmarkspec, id, bufnr, lnum, col, text, inserted_at, note)
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

  -- local text_concat = ""
  --
  -- --- Handle note if its type is table or string before saving
  -- if mark_mode == "NOTE" then
  --   if type(note) == "table" then
  --     text_concat = table.concat(note, " ")
  --   elseif type(note) == "string" then
  --     text_concat = note
  --   end
  --   if #text_concat == 0 then
  --     return
  --   end
  -- end

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

---@param mark_lists QFbookBufferMark
---@param mark_mode QFBookMarkMode
---@param extmarkspec QFBookSpec
---@param id integer
---@param bufnr? integer
---@param lnum integer
---@param col integer
---@param text string
---@param is_open_window boolean
---@return QFbookBufferMark | nil
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

---@param mark_lists QFbookBufferMark
---@param bufnr integer
function M.update_mark_sign(mark_lists, bufnr)
  if vim.tbl_isempty(mark_lists) then
    return
  end

  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  QfbookmarkMarkVisual.resolve_mark_sign(bufnr)

  local filename = vim.api.nvim_buf_get_name(bufnr)

  local existing_ids = {}
  local mark_list_active_ids = {}

  for mode, _ in pairs(mark_lists) do
    for m_id, _ in pairs(mark_lists[mode]) do
      if not existing_ids[m_id] then
        existing_ids[m_id] = true
        mark_list_active_ids[#mark_list_active_ids + 1] = {
          id = m_id,
          mode = mode,
        }
      end
    end
  end

  local sign_mark_placed = QfbookmarkMarkVisual.get_sign_unused_ids(bufnr, existing_ids)

  local id_lookup = {}
  for _, sign in pairs(sign_mark_placed) do
    if not id_lookup[sign.id] then
      id_lookup[sign.id] = true
    end
  end

  for _, mark in pairs(mark_list_active_ids) do
    if not id_lookup[mark.id] then
      for mark_id, mark_data in pairs(mark_lists[mark.mode]) do
        if mark.id ~= mark_id then
          goto continue
        end

        local mark_filename = mark_lists[mark.mode][tonumber(mark_id)].filename
        if mark_filename ~= filename then
          goto continue
        end

        local extmarkspec = Config.extmarks.keywords[mark.mode]

        if is_not_valid_line_and_col(bufnr, mark_data.line, mark_data.col) then
          M.delete_mark(mark_lists, mark.mode, mark_data.id, bufnr)
        else
          register_mark(
            mark_lists,
            mark.mode,
            extmarkspec,
            mark_data.id,
            bufnr,
            mark_data.line,
            mark_data.col,
            mark_data.text,
            mark_data.inserted_at,
            mark_data.note
          )
        end

        ::continue::
      end
    end
  end
end

--- Check whether mark data exists in the bookmark storage.
--- This only checks the internal `mark_lists` table and does not inspect
--- placed signs or extmarks in the buffer.
---@param mark_lists QFbookBufferMark
---@param mark_mode QFBookMarkMode
---@param id? integer
---@param bufnr? integer
---@return integer|nil, boolean
function M.has_mark_data(mark_lists, mark_mode, id, bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local line_opts = QfbookmarkUtils.get_line_pos_col_buffer()
  id = id or tonumber(line_opts.line .. bufnr)

  if not mark_lists[mark_mode] or not mark_lists[mark_mode][id] then
    return nil, false
  end

  return id, true
end

--- Remove a mark entry and its associated sign.
--- Returns `true` when the mark exists and is successfully removed from
--- the internal storage; otherwise returns `false`.
---@param mark_lists QFbookBufferMark
---@param mark_mode QFBookMarkMode
---@param id? integer
---@param bufnr? integer
---@return boolean
function M.delete_mark(mark_lists, mark_mode, id, bufnr)
  local _, ok = M.has_mark_data(mark_lists, mark_mode, id, bufnr)
  if not ok or not id then
    return false
  end

  mark_lists[mark_mode][id] = nil
  QfbookmarkMarkVisual.delete_sign(id, bufnr)
  QfbookmarkMarkVisual.delete_extmark(id, bufnr)
  return true
end

--- Add a new mark at the current cursor position.
--- Uses the current buffer, line, and column to create a mark and store
--- it through `place_next_mark()`.
---@param mark_lists QFbookBufferMark
---@param mark_mode QFBookMarkMode
---@param extmarkspec QFBookSpec
---@param is_open_window? boolean
---@return QFbookBufferMark|nil
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

return M
