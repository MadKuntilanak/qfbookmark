local M = {}

local Config = require("qfbookmark.config").defaults
local QfbookmarkUtils = require "qfbookmark.utils"
local QfbookmarkPathUtils = require "qfbookmark.path.utils"

M.path_opts = {
  __global = Config.save_dir .. "/__global",
  __local = Config.save_dir .. "/__local",

  current_target = "",
}

---@return string | function | table | nil
local function get_hash_note()
  local root = vim.uv.cwd()
  if root then
    return QfbookmarkPathUtils.get_hash_note(vim.loop.fs_realpath(root))
  end
  return nil
end

---@return string
function M.get_basename_cwd_project()
  local sha_path = get_hash_note()
  if sha_path then
    return QfbookmarkPathUtils.get_base_path_root(Config.save_dir) .. "-" .. sha_path
  end
  return M.path_opts.__global
end

---@param is_global boolean
---@return string
function M.get_target_path(is_global)
  local path

  path = M.path_opts.__global
  if not is_global then
    M.path_opts.__local = M.get_basename_cwd_project()
    path = M.path_opts.__local
  end

  M.path_opts.current_target = path
  return M.path_opts.current_target
end

---@param is_global? boolean
---@return string
function M.get_target_path_with_gitcwd(is_global)
  is_global = is_global or false

  local cwd_local_project = M.get_target_path(is_global)
  local git_branch = QfbookmarkPathUtils.git_branch()
  if not git_branch then
    return cwd_local_project
  end
  git_branch = "_" .. git_branch .. ""
  return cwd_local_project .. "/mark" .. git_branch .. ".lua"
end

---@param is_global? boolean
---@return QFbookBufferMarkEntry[]
local function get_marks_cwd(is_global)
  is_global = is_global or false

  local mark_lists = {}

  local cwd_local_project = M.get_target_path(is_global)
  if QfbookmarkPathUtils.is_dir(cwd_local_project) then
    local fn_mark_lua = M.get_target_path_with_gitcwd(is_global)
    if QfbookmarkPathUtils.is_file(fn_mark_lua) then
      mark_lists = dofile(fn_mark_lua)
    end
  end

  return mark_lists
end

---@return QFbookBufferMarkEntry[]
function M.get_data_mark_local_project()
  return get_marks_cwd()
end

---@return QFbookBufferMarkEntry[]
function M.get_data_mark_global_project()
  return get_marks_cwd(true)
end

---@param is_global boolean
function M.setup_path(is_global)
  local path = M.get_target_path(is_global)
  if not QfbookmarkPathUtils.is_dir(path) then
    QfbookmarkPathUtils.create_dir(path)
  end
end

---@param list_items QFBookLists
---@param is_loc boolean
function M.save_data_lists(list_items, is_loc)
  is_loc = is_loc or false

  local target_path = M.path_opts.current_target

  local QfbookmarkUI = require "qfbookmark.ui"
  QfbookmarkUI._input_popup("Save To File", target_path, "save", function(input)
    if #input == 0 or input == "" then
      return
    end

    local reform_opts = QfbookmarkPathUtils.reformat_filename_json(input, target_path, is_loc)
    if not reform_opts then
      return
    end

    QfbookmarkPathUtils.write_to_file(list_items, reform_opts.full_path)
    QfbookmarkUtils.info(string.format("Save successful!\nFilename: %s", reform_opts.filename))
  end)
end

---@param path string
function M.is_json_path_exists(path)
  if not QfbookmarkPathUtils.is_dir(path) then
    return false
  end
  return QfbookmarkPathUtils.is_file_json_found_on_path(path)
end

---@param path string
---@return QFBookLists | nil
function M.read_from_file_json(path)
  if not QfbookmarkPathUtils.is_file(path) then
    QfbookmarkUtils.error("Can’t find this file:`" .. path .. "`")
    return
  end

  local raw_data_json = QfbookmarkPathUtils.get_file_read(path)
  local tbl_outputs = QfbookmarkPathUtils.fn_json_decode(raw_data_json)

  if not tbl_outputs or vim.tbl_isempty(tbl_outputs) then
    return
  end

  return tbl_outputs
end

return M
