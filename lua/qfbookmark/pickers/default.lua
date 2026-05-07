local M = {}

local QfbookmarkUtils = require "qfbookmark.utils"
local QfbookmarkPaths = require "qfbookmark.path"
local QfbookmarkPathUtils = require "qfbookmark.path.utils"

local save_icon = " "
local load_icon = " "
local set_icon = " "

---@param str string
---@param icon string
local function format_title(str, icon)
  return " " .. icon .. " " .. str .. " "
end

---@param sel_fname string
---@param base_path string
---@param is_loc? boolean
local function load_open(sel_fname, base_path, is_loc)
  is_loc = is_loc or false

  local fname = sel_fname
  local fname_path = base_path .. "/" .. fname .. ".json"

  local list_items = QfbookmarkPaths.read_from_file_json(fname_path)
  if not list_items then
    return
  end

  QfbookmarkUtils.save_to_qf(list_items, is_loc)

  if is_loc then
    vim.cmd "lopen"
  else
    vim.cmd "copen"
  end

  QfbookmarkUtils.info("Load successful! File -> " .. fname)
end

---@param state QFBookState
---@param selected string
local function load_to_qf(state, selected)
  local is_global = selected == "Global" and true or false
  local path = QfbookmarkPaths.get_target_path(is_global)

  if not QfbookmarkPaths.is_json_path_exists(path) then
    QfbookmarkUtils.warn([[No quickfix lists were found at `]] .. path .. [[`.\nPlease create one]])
    return
  end

  local title_prompt = format_title(state, load_icon)

  -- fix quote path ('""')
  local cmd = {
    "sh",
    "-c",
    "fd '' -d 1 -e json "
      .. "'"
      .. path
      .. "'"
      .. " --exec stat --format '%Z %n' {} | "
      .. "sort -nr | cut -d' ' -f2- | sed 's/.json$//' | sed 's#^\\./##'",
  }

  local proc = vim.system(cmd, { text = true }):wait()
  if proc.code ~= 0 or not proc.stdout or proc.stdout == "" then
    QfbookmarkUtils.warn "Command fd failed or fd not installed"
    return
  end
  local proc_stdouts = vim.split(proc.stdout, "\n", { trimempty = true })
  local __contents = vim.deepcopy(proc_stdouts)

  local contents = {}
  for _, p in pairs(__contents) do
    contents[#contents + 1] = QfbookmarkPathUtils.basename(p)
  end

  vim.ui.select(contents, { prompt = title_prompt }, function(choice)
    if not choice then
      return
    end

    local _selected = choice
    load_open(_selected, path)
  end)
end

---@param state QFBookState
---@param selected string
local function save_to_qf(state, selected)
  local is_global = selected == "Global" and true or false
  QfbookmarkPaths.setup_path(is_global)

  local is_loc = true
  if state == "Save Qflist" then
    is_loc = false
  end

  local data_lists = QfbookmarkUtils.get_populate_data_qf(is_loc)
  if data_lists then
    QfbookmarkPaths.save_data_lists(data_lists, is_loc)
  end
end

---@param config QFBookmarkConfig
---@param contents? string[]
---@param state QFBookState
function M.set_state(config, contents, state)
  contents = contents or {}
  state = state or ""

  local prompt_title
  if #state > 0 then
    local icon = (state == "Save Qflist" or state == "Save Loclist") and save_icon or load_icon
    prompt_title = format_title(state, icon)
  else
    prompt_title = format_title("Save Or Load", set_icon)
  end

  vim.ui.select(contents, { prompt = prompt_title }, function(choice)
    if not choice then
      return
    end

    local selected = choice
    local new_contents = { "Local", "Global" }

    local is_found = false
    for _, ctx in pairs(new_contents) do
      if selected == ctx then
        is_found = true
      end
    end

    if not is_found then
      M.set_state(config, new_contents, selected)
    end

    if state == "Save Qflist" or state == "Save Loclist" then
      save_to_qf(state, selected)
    end

    if state == "Load" then
      load_to_qf(state, choice)
    end
  end)
end

return M
