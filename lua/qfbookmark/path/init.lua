local M = {}

local Config = require("qfbookmark.config").defaults
local QfbookmarkUtils = require "qfbookmark.utils"
local QfbookmarkPathUtils = require "qfbookmark.path.utils"

M.path_opts = {
  -- this a dir path
  __global = Config.save_dir .. "/__global",
  __local = nil,

  -- this a name/filename path
  current_target_file = nil,
  current_branch = nil,
  current_root = nil,
}

-- +-----------------------------------------------------------------------------+
-- |                                   HELPER                                    |
-- +-----------------------------------------------------------------------------+

--- Initialize the active storage directory.
--- When `is_global` is false, a project-specific directory is resolved
--- and stored in `path_opts.__local`. Otherwise, the global directory
--- is used.
--- The global storage directory is created automatically if it does not
--- already exist
---@param is_global boolean
local function init_path(is_global)
  if not is_global then
    local save_qf, root = M.get_root_project()

    M.path_opts.__local = save_qf
    M.path_opts.current_root = root
  end

  -- Create the __global directory if it does not exist.
  if not QfbookmarkPathUtils.is_dir(M.path_opts.__global) then
    QfbookmarkPathUtils.create_dir(M.path_opts.__global)
  end
end

---@param root? string
---@return string | function | table | nil
local function get_hash_note(root)
  root = root or vim.uv.cwd()

  if root then
    return QfbookmarkPathUtils.get_hash_note(vim.loop.fs_realpath(root))
  end

  return nil
end

-- +-----------------------------------------------------------------------------+
-- |                                     API                                     |
-- +-----------------------------------------------------------------------------+

--- Returns the storage root path for the current project.
--- If the current working directory is inside a Git repository,
--- a project-specific path is generated using the repository root
--- and a hash derived from it. Otherwise, the global storage path
--- is returned
---@return string
---@return string
function M.get_root_project()
  local save_qfpath, root = QfbookmarkPathUtils.get_base_path_root(Config.save_dir)

  local sha_path = get_hash_note(root)
  if sha_path then
    return save_qfpath .. "-" .. sha_path, root
  end

  return save_qfpath, root
end

--- Get the target bookmark file path.
--- The file name is derived from the current Git branch and stored
--- under the active storage directory. If no Git branch is available,
--- "no-branch" is used as a fallback.
--- The computed path is cached and reused on subsequent calls. Set
--- `is_reload` to true to refresh the cache and recompute the path,
--- which is useful when the current Git branch has changed
---@param is_global boolean
---@param is_reload? boolean
---@return string path
function M.get_target_file_path(is_global, is_reload)
  is_reload = is_reload or false

  if not M.path_opts.__local then
    init_path(is_global)
  end

  if is_reload then
    M.path_opts.current_branch = nil
    M.path_opts.current_target_file = nil
  end

  if not M.path_opts.current_target_file then
    if not QfbookmarkPathUtils.is_dir(M.path_opts.__local) then
      QfbookmarkPathUtils.create_dir(M.path_opts.__local)
    end

    if not M.path_opts.current_branch then
      M.path_opts.current_branch = QfbookmarkPathUtils.get_git_branch(M.path_opts.current_root)
    end

    local safe_branch = (M.path_opts.current_branch or "no-branch"):gsub("[/\\:]", "-")

    M.path_opts.current_target_file = M.path_opts.__local .. "/qfmark_" .. safe_branch .. ".lua"
  end

  if is_global then
    return M.path_opts.__global
  end
  return M.path_opts.current_target_file
end

--- Get the target storage directory.
--- Initializes the internal path state on first use. Returns either the
--- global storage directory or the project-specific directory based on
--- the value of `is_global`
---@param is_global boolean
---@return string
function M.get_target_dir_path(is_global)
  if not M.path_opts.__local then
    init_path(is_global)
  end

  if is_global then
    return M.path_opts.__global
  end

  return M.path_opts.__local
end

---@param current_root string
---@param current_branch string
---@param is_global? boolean
---@param is_force? boolean
---@return string
function M.resolve_marks_path(current_root, current_branch, is_global, is_force)
  is_global = is_global or false
  is_force = is_force or false

  M.path_opts.current_root = current_root
  M.path_opts.current_branch = current_branch

  return M.get_target_file_path(is_global, is_force)
end

function M.resolve_active_marks_file()
  local save_qfpath, root = QfbookmarkPathUtils.get_base_path_root(Config.save_dir)
  local branch = QfbookmarkPathUtils.get_git_branch(root)

  return save_qfpath, root, branch
end

--- Load marks from a saved file.
--- Returns the deserialized mark list if the file exists.
--- Otherwise, an empty table is returned.
---@param path_master string
---@return QFbookBufferMarkEntry[]
function M.load_master(path_master)
  if QfbookmarkPathUtils.is_file(path_master) then
    local mark_lists = dofile(path_master)
    return mark_lists
  end

  return {}
end

---@param is_global boolean
---@param force_reload boolean
---@return QFbookBufferMarkEntry[]
local function load_marks_data(is_global, force_reload)
  local fn_mark_lua = M.get_target_file_path(is_global, force_reload)

  if not QfbookmarkPathUtils.is_file(fn_mark_lua) then
    return {}
  end

  return M.load_master(fn_mark_lua)
end

---@param force_reload boolean
---@return QFbookBufferMarkEntry[]
function M.get_data_marks_from_local_project(force_reload)
  return load_marks_data(false, force_reload)
end

---@param force_reload boolean
---@return QFbookBufferMarkEntry[]
function M.get_data_mark_from_global_project(force_reload)
  return load_marks_data(true, force_reload)
end

---@param is_global boolean
function M.setup_path(is_global)
  local path = M.get_target_file_path(is_global)
  if not QfbookmarkPathUtils.is_file(path) then
    QfbookmarkPathUtils.create_file(path)
  end
end

-- +-----------------------------------------------------------------------------+
-- |                                    MISC                                     |
-- +-----------------------------------------------------------------------------+

M.qf = {}

---@param list_items QFBookmarkLists
---@param is_global boolean
---@param is_loc boolean
function M.qf.save_data_lists(list_items, is_global, is_loc)
  local target_path = M.path_opts.__local
  if not target_path then
    return
  end

  local QfbookmarkUI = require "qfbookmark.ui"
  local title_popup = "📁 Save to File " .. (is_global and "Global" or "Local")

  QfbookmarkUI.saveqf_popup(title_popup, target_path, "save", is_loc, function(input)
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

M.json = {}

---@param path string
function M.json.is_dir_json_exists(path)
  if not QfbookmarkPathUtils.is_dir(path) then
    return false
  end
  return QfbookmarkPathUtils.is_file_json_found_on_path(path)
end

---@param path string
---@return QFBookmarkLists | nil
function M.json.read_from_file_json(path)
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
