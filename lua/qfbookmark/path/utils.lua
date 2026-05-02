local Plenary_path = require "plenary.path"
local QfbookmarkUtils = require "qfbookmark.utils"

local M = {}

---@param filename string
---@return boolean | string
function M.exists(filename)
  local stat
  if filename then
    stat = vim.loop.fs_stat(filename)
  end

  return stat and stat.type or false
end

---@param filename string
---@return boolean
function M.is_dir(filename)
  return M.exists(filename) == "directory"
end

---@return boolean
function M.is_file(filename)
  return M.exists(filename) == "file"
end

function M.create_file(path)
  local p = Plenary_path.new(path)
  if not p:exists() then
    p:touch()
  end
end

function M.create_dir(path)
  local p = Plenary_path.new(path)
  if not p:exists() then
    p:mkdir()
  end
end

---@return string
local function __get_cwd_root()
  local HAVE_GITSIGNS = pcall(require, "gitsigns")

  ---@diagnostic disable-next-line: undefined-field
  local status = vim.b.gitsigns_status_dict or nil

  local root_path = ""
  if not HAVE_GITSIGNS or status == nil or status["root"] == nil then
    root_path = vim.fn.getcwd()
  else
    root_path = status["root"]
  end

  if #root_path > 0 then
    root_path = vim.fs.basename(root_path)
  end

  return root_path
end

---@param path string
---@param is_global? boolean
---@return string
function M.get_base_path_root(path, is_global)
  is_global = is_global or false

  local full_path = path

  if not is_global then
    local root_path = __get_cwd_root()
    full_path = full_path .. "/" .. root_path
  end
  return full_path
end

---@return string | function| table
function M.get_hash_note(filePath)
  local SHA = require "qfbookmark.path.sha"
  return SHA.sha1(filePath)
end

---@return string
function M.json_encode(tbl)
  return vim.json.encode(tbl)
end

---@return any
function M.json_decode(tbl)
  return vim.json.decode(tbl)
end

---@param tbl string[]
---@return any
function M.fn_json_decode(tbl)
  return vim.fn.json_decode(tbl)
end

---@param list_items QFBookLists
---@param path_fname string
function M.write_to_file(list_items, path_fname)
  if list_items.items and list_items.items == 0 then
    error [[`tbl` must contains { items = {}, title = "" }]]
  end

  local tbl_json = M.json_encode(list_items)
  vim.fn.writefile({ tbl_json }, path_fname)
end

---@return string[]
function M.get_file_read(fname_path)
  return vim.fn.readfile(fname_path)
end

---@return boolean
function M.is_file_json_found_on_path(path)
  local scripts = vim.api.nvim_exec2(string.format([[!find %s -type f -name "*.json"]], path), { output = true })
  if scripts.output ~= nil then
    local res = vim.split(scripts.output, "\n")
    local found = false
    for index = 2, #res do
      local item = res[index]
      if #item > 0 then
        found = true
      end
    end

    return found
  end

  return false
end

---@param base_path string
---@param title string
---@param is_loc boolean
---@return string, string
local function format_filename_json(base_path, title, is_loc)
  local qf_title = QfbookmarkUtils.get_title_qf(is_loc)

  local fmt_str_title = function(prefix)
    prefix = #prefix > 0 and "_" .. prefix .. "-" or "-"
    return prefix
  end

  local prefix = ""

  -- TODO: ini kenapa ada title [FzfLua] bla bla bla
  -- apakah ada gw set dengan prefix title tersebut?
  -- coba diselediki

  if qf_title:match "%[FzfLua%]%sfiles:%s" then
    -- prefix = qf_title:gsub("%[FzfLua%]%sfiles:%s", "")
    prefix = fmt_str_title(prefix)
  end

  if qf_title:match "%[FzfLua%]%slive_grep_glob:%s" then
    -- prefix = qf_title:gsub("%[FzfLua%]%slive_grep_glob:%s", "")
    prefix = fmt_str_title(prefix)
  end

  if qf_title:match "%[FzfLua%]%sblines:%s" then
    -- prefix = qf_title:gsub("%[FzfLua%]%sblines:%s", "")
    prefix = fmt_str_title(prefix)
  end

  if qf_title:match "Fzf_diffview" then
    -- prefix = qf_title:gsub("Fzf_diffview", "")
    prefix = fmt_str_title(prefix)
  end

  -- TODO: untuk prefix Octo, sepertinya format title dari plugin Octo tidak ada hanya tanda kurung '()'
  -- ini membuat susah untuk di buat format
  -- if qf_title:match("%s%(%)") then
  -- 	local qf_list = vim.fn.getqflist({ winid = 0, items = 0 })
  -- 	print(vim.inspect(qf_list.items))
  -- 	-- prefix = qf_title:gsub("%[FzfLua%]%sfiles:%s", "")
  -- 	-- prefix = prefix .. "_"
  -- end

  local fname = title .. prefix .. ".json"
  local fname_path = base_path .. "/" .. fname
  return fname_path, fname
end

---@param input string
---@param target_path string
---@param is_loc? boolean
---@return {full_path: string, filename: string, is_loc: boolean} | nil
function M.reformat_filename_json(input, target_path, is_loc)
  is_loc = is_loc or false

  input = input:gsub("%s", "_")
  input = input:gsub("%.", "_")

  local fname_path, fname = format_filename_json(target_path, input, is_loc)
  return {
    full_path = fname_path,
    filename = fname,
    is_loc = is_loc,
  }
end

---@return string
local separator = function()
  return "/"
end

---@param path string
---@return string
local function remove_trailing(path)
  local p, _ = path:gsub(separator() .. "$", "")
  return p
end

function M.basename(path)
  path = remove_trailing(path)
  local i = path:match("^.*()" .. separator())
  if not i then
    return path
  end
  return path:sub(i + 1, #path)
end

---@param command string
---@return string|nil
local function cmd(command)
  local h = io.popen(command)
  if h == nil then
    return nil
  end
  local result = h:read("*a"):gsub("%s+", "")
  h:close()
  return result ~= "" and result or nil
end

---@return string|nil
function M.git_branch()
  return cmd "git branch --show-current"
end

return M
