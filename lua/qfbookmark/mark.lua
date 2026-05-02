local Config = require("qfbookmark.config").defaults
local QfbookmarkUtils = require "qfbookmark.utils"
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
---@param line integer
---@return boolean
local function is_not_valid_line(bufnr, line)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  return line >= 0 and line < line_count
end

---@param bufnr integer
---@param line integer
---@param col integer
---@return boolean
local function is_not_valid_line_and_col(bufnr, line, col)
  if is_not_valid_line(bufnr, line) then
    return false
  end

  local text = vim.api.nvim_buf_get_lines(bufnr, line, line + 1, false)[1] or ""
  local line_len = #text
  return col >= 0 and col <= line_len
end

--- Clean orphan marks (whose line no longer exists)
-- local function clean_orphan_marks(mark_lists)
--   for mode, marks in pairs(mark_lists) do
--     for id, mark in pairs(marks) do
--       if not is_valid_line(mark.bufnr, mark.line) then
--         M.buffers[mode][id] = nil
--       end
--     end
--   end
-- end

---@param bufnr integer
---@return table <integer>
local function get_all_signs_buffer(bufnr)
  local placed = vim.fn.sign_getplaced(bufnr, { group = "*" }) -- Ambil semua sign yang terpasang
  local all_signs = placed[1] and placed[1].signs or {}
  return all_signs
end

---@param bufnr integer
---@param existing_ids table
---@return table <integer>
local function get_unused_sign_ids(bufnr, existing_ids)
  local all_signs = get_all_signs_buffer(bufnr)
  local unused_ids = {}

  for _, sign in ipairs(all_signs) do
    if existing_ids[sign.id] then
      -- table.insert(unused_ids, sign.id)
      table.insert(unused_ids, sign)
      existing_ids[sign.id] = true -- Tandai ID sudah digunakan
    end
  end

  return unused_ids
end

---@param bufnr integer
---@param line integer
---@return table
local function get_signs_at_line(bufnr, line)
  local all_signs = get_all_signs_buffer(bufnr)

  for _, x in pairs(all_signs) do
    if x.lnum == line then
      return x
    end
  end

  return {}
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

  local sign
  if no_id then
    local line_opts = QfbookmarkUtils.get_line_pos_col_buffer()
    sign = get_signs_at_line(bufnr, line_opts.line)
    if sign.group ~= Config.sign_group then
      return
    end
  end

  for mark_mode, _ in pairs(mark_lists) do
    local mode_marks = mark_lists[mark_mode]
    for _, x in pairs(mode_marks) do
      local opts
      local extmarkspec = Config.extmarks.keywords[mark_mode]
      if no_id and sign then
        if tonumber(x.line) == tonumber(sign.lnum) and sign.group == Config.sign_group then
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

----@param buf integer
-- local function update_render_extermark(buf)
--   if Config.ns > 0 then
--     -- Clear dahulu extemarks, sebelum di render di quickfix window
--     -- untuk mencegah duplikasi ketika `delete item` atau `update item`
--     vim.api.nvim_buf_clear_namespace(buf, Config.ns, 0, -1)
--   end
-- end

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

  local path_local_cwd = QfbookmarkPaths.get_target_path_with_gitcwd(is_save_global_mark)
  if not QfbookmarkPathUtils.is_file(path_local_cwd) then
    QfbookmarkPathUtils.create_file(path_local_cwd)
  end

  QfbookmarkUtils.save_table_to_file(mark_lists, path_local_cwd)
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
---@param line integer
---@param col integer
---@param text string
---@return QFbookBufferMark | nil
local function register_mark(mark_lists, mark_mode, extmarkspec, id, bufnr, line, col, text)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local filename = vim.api.nvim_buf_get_name(bufnr)

  -- Validate line before registering
  if is_not_valid_line_and_col(bufnr, line, col) then
    return nil
  end

  if not mark_lists[mark_mode] then
    mark_lists[mark_mode] = {}
  end

  local cwd = vim.uv.cwd()
  local filename_trim = filename:gsub(cwd .. "/", "")
  local harpoon = string.format("%s:%s:%s:%s", filename_trim, line, col, mark_mode)

  if not mark_lists[mark_mode][id] then
    mark_lists[mark_mode][id] = {
      bufnr = bufnr,
      filename = filename,
      line = line,
      col = col,
      text = QfbookmarkUtils.strip_whitespace(text),
      harpoon = harpoon,
      mark_mode = mark_mode,
      id = id,
    }
  end

  if Config.extmarks.enabled then
    QfbookmarkMarkVisual.insert_signs(id, mark_mode, bufnr, line, extmarkspec)
  end

  return mark_lists
end

---@param mark_lists QFbookBufferMark
---@param mark_mode QFBookMarkMode
---@param extmarkspec QFBookSpec
---@param id integer
---@param bufnr? integer
---@param line integer
---@param col integer
---@param text string
---@return QFbookBufferMark | nil
function M.place_next_mark(mark_lists, mark_mode, extmarkspec, id, bufnr, line, col, text)
  -- local last_mark = M.is_current_line_got_mark(id)
  -- if last_mark and last_mark.id then
  --   M.delete_mark(last_mark.mark_mode, last_mark.extmarkspec, last_mark.id, bufnr)
  -- end
  -- vim.schedule(function()
  return register_mark(mark_lists, mark_mode, extmarkspec, id, bufnr, line, col, text)
  -- end)
end

---@param mark_lists QFbookBufferMark
---@param bufnr integer
function M.update_mark_sign(mark_lists, bufnr)
  if vim.tbl_isempty(mark_lists) then
    return
  end

  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  pcall(vim.api.nvim_buf_clear_namespace, bufnr, Config.ns, 0, -1)

  local filename = vim.api.nvim_buf_get_name(bufnr)

  -- clear all signs
  local ok_signs, signinfo = pcall(vim.fn.sign_getplaced, bufnr, { group = Config.sign_group })
  if ok_signs and signinfo and signinfo[1] and signinfo[1].signs then
    for _, sign in pairs(signinfo[1].signs) do
      pcall(vim.fn.sign_unplace, Config.sign_group, { buffer = bufnr, id = sign.id })
    end
  end

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

  local sign_mark_placed = get_unused_sign_ids(bufnr, existing_ids)

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
            mark_data.text
          )
        end

        ::continue::
      end
    end
  end
end

---@param mark_lists QFbookBufferMark
---@param mark_mode QFBookMarkMode
---@param id? integer
---@param bufnr? integer
---@return boolean
function M.delete_mark(mark_lists, mark_mode, id, bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  if not id then
    local line_opts = QfbookmarkUtils.get_line_pos_col_buffer()
    id = tonumber(line_opts.line .. bufnr)
  end

  if id then
    if not mark_lists[mark_mode] or not mark_lists[mark_mode][id] then
      return false
    end

    mark_lists[mark_mode][id] = nil
    QfbookmarkMarkVisual.remove_sign(id, bufnr)
    return true
  end

  return false
end

---@param mark_lists QFbookBufferMark
---@param mark_mode QFBookMarkMode
---@param extmarkspec QFBookSpec
---@param toggle_delete boolean?
---@return QFbookBufferMark|nil
function M.add_mark(mark_lists, mark_mode, extmarkspec, toggle_delete)
  toggle_delete = toggle_delete or false

  if not Config.extmarks.enabled then
    return nil
  end

  local line_opts = QfbookmarkUtils.get_line_pos_col_buffer()

  local bufnr = vim.api.nvim_get_current_buf()
  local id = tonumber(line_opts.line .. bufnr)
  if not id then
    QfbookmarkUtils.warn "Unexpected error while getting line number"
    return nil
  end

  if toggle_delete then
    M.delete_mark(mark_lists, mark_mode, id, bufnr)
    return nil
  end

  return M.place_next_mark(mark_lists, mark_mode, extmarkspec, id, bufnr, line_opts.line, line_opts.col, line_opts.text)
end

return M
