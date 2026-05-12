local QfbookmarkPaths = require "qfbookmark.path"
local QfbookmarkUtils = require "qfbookmark.utils"

-- local _, ok = pcall(require, "fzf-lua")
-- if not ok then
--   error "This extension requires ibhagwan/fzf-lua (https://github.com/ibhagwan/fzf-lua)"
-- end

local loaded = false
local FzfLua

local silent_notify = false

local function setup_fzflua()
  if loaded then
    return FzfLua
  end

  local ok, _ = pcall(require, "fzf-lua")
  if not ok then
    if not silent_notify then
      QfbookmarkUtils.error "This extension requires ibhagwan/fzf-lua (https://github.com/ibhagwan/fzf-lua)"
      silent_notify = true
      return
    end
    return
  end

  FzfLua = require "fzf-lua"
  loaded = true

  return FzfLua
end

local save_icon = " "
local load_icon = " "
local set_icon = " "

local M = {}

local Mapping = {}

--- FZFLUA: Taken from fzf-lua
local nbsp = "\xe2\x80\x82" -- Non-breaking space unicode character "\u{2002}"
local function last_index_of(haystack, needle)
  local i = haystack:match(".*" .. needle .. "()")
  if i == nil then
    return nil
  else
    return i - 1
  end
end
---@return string, integer
local function strip_before_last_occurence_of(str, sep)
  local idx = last_index_of(str, sep) or 0
  return str:sub(idx + 1), idx
end
local function strip_ansi_coloring(str)
  if not str then
    return str
  end
  -- Remove escape sequences of the following formats:
  -- 1. ^[[34m
  -- 2. ^[[0;34m
  -- 3. ^[[m
  return str:gsub("%[[%d;]-m", "")
end
---@return string | nil
local function strip_string(selected)
  local pth = strip_ansi_coloring(selected)
  if pth == nil then
    return
  end
  local str, _ = strip_before_last_occurence_of(pth, nbsp)
  if str == "" then
    return
  end
  return str
end
--- END FZFLUA

---@param str string
---@param icon? string
---@return string
local function format_title(str, icon)
  icon = icon and icon .. " " or ""
  return icon .. str
end

---@param state QFBookState
---@param select_state QFBookCurrentState
local function save_to_qf(state, select_state)
  local is_global = select_state == "Global" and true or false
  QfbookmarkPaths.setup_path(is_global)

  local is_loc = true
  if state == "Save Qflist" then
    is_loc = false
  end

  local data_lists = QfbookmarkUtils.get_populate_data_qf(is_loc)
  if data_lists then
    QfbookmarkPaths.save_data_lists(data_lists, is_global, is_loc)
  end
end

local function __fzf_open_files(title_prompt, path_cwd, opts)
  opts = opts or {}
  return FzfLua.files(vim.tbl_deep_extend("force", {
    cwd = path_cwd,
    no_header = false,
    no_header_i = true, -- hide interactive header?
    fzf_opts = { ["--header"] = [[^x:delete  ^r:rename]] },
    cmd = "fd -d 1 -e json --exec stat --format '%Z %n' {} | sort -nr | cut -d' ' -f2- | sed 's/.json$//' | sed 's/\\.\\///'",
    winopts = { title = title_prompt, preview = { hidden = true } },
    actions = {
      ["default"] = Mapping.default_load_qf(path_cwd),
      ["alt-q"] = Mapping.load_open_in_qf(path_cwd),
      ["alt-v"] = Mapping.load_open_in_loc(path_cwd),
      ["ctrl-x"] = function()
        return Mapping.remove_itemqf(path_cwd)
      end,
      ["ctrl-r"] = function()
        return Mapping.rename_itemqf(path_cwd)
      end,
    },
  }, opts))
end

---@param state QFBookState
---@param select_state QFBookCurrentState
local function load_to_qf(state, select_state)
  local is_global = select_state == "Global" and true or false
  local path = QfbookmarkPaths.get_target_path(is_global)

  if not QfbookmarkPaths.is_json_path_exists(path) then
    QfbookmarkUtils.warn([[No quickfix lists were found at `]] .. path .. [[`.\nPlease create one]])
    return
  end

  local title_prompt = format_title(state, load_icon)
  __fzf_open_files(title_prompt, path)
end

local fzf_opts = {
  winopts = {
    width = 0.50,
    height = 0.50,
    row = 0.50,
    col = 0.50,
    backdrop = 100,
    preview = { hidden = true },
  },
}

---@param config QFBookmarkConfig
---@param contents string[]
---@param state QFBookState
local function handle_state(config, contents, state)
  fzf_opts.actions = function()
    return {
      ["default"] = Mapping.default_handle(config, state),
    }
  end

  if #state > 0 then
    local icon = (state == "Save Qflist" or state == "Save Loclist") and save_icon or load_icon
    fzf_opts.winopts.title = format_title(state, icon)
  else
    fzf_opts.winopts.title = format_title("Save Or Load", set_icon)
  end

  local generate_width = function()
    local x_width = 0
    for _, x in pairs(contents) do
      if x_width < #x then
        x_width = #x
      end
    end
    return x_width
  end

  fzf_opts.winopts.width = generate_width() + 40
  fzf_opts.winopts.height = #contents + 10

  FzfLua.fzf_exec(contents, fzf_opts)
end

---@param config QFBookmarkConfig
---@param contents? string[]
---@param state QFBookState
function M.set_state(config, contents, state)
  setup_fzflua()

  contents = contents or {}
  state = state or ""

  handle_state(config, contents, state)
end

---@param config QFBookmarkConfig
---@param state QFBookState
function Mapping.default_handle(config, state)
  return function(selected)
    if #selected == 0 then
      return
    end

    local sel = selected[1]
    local contents = { "Local", "Global" }

    local is_found = false
    for _, ctx in pairs(contents) do
      if sel == ctx then
        is_found = true
      end
    end

    if not is_found then
      M.set_state(config, contents, sel)
    end

    if state == "Save Qflist" or state == "Save Loclist" then
      save_to_qf(state, sel)
    end

    if state == "Load" then
      load_to_qf(state, sel)
    end
  end
end

---@param sel_fname string
---@param base_path string
---@param is_loc? boolean
local function load_open(sel_fname, base_path, is_loc)
  is_loc = is_loc or false

  local fname = strip_string(sel_fname)
  if not fname then
    return
  end

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

  QfbookmarkUtils.info("󰄬 Loaded: `" .. fname .. "`")
end

---@param base_path string
function Mapping.default_load_qf(base_path)
  return function(selected)
    if #selected == 0 then
      return
    end

    local sel_fname = selected[1]
    load_open(sel_fname, base_path)
  end
end

---@param base_path string
function Mapping.load_open_in_qf(base_path)
  return function(selected)
    if #selected == 0 then
      return
    end

    local sel_fname = selected[1]
    load_open(sel_fname, base_path)
  end
end

---@param base_path string
function Mapping.load_open_in_loc(base_path)
  return function(selected)
    if #selected == 0 then
      return
    end

    local sel_fname = selected[1]
    load_open(sel_fname, base_path, true)
  end
end

---@param base_path string
function Mapping.remove_itemqf(base_path)
  __fzf_open_files("Remove", base_path, {
    actions = {
      ["default"] = function(sel)
        local fname = strip_string(sel[1])
        if not fname then
          QfbookmarkUtils.warn("Something went wrong when strip string: `" .. tostring(fname) .. "`")
          return
        end

        local file_path = base_path .. "/" .. fname .. ".json"

        if vim.fn.filereadable(file_path) ~= 1 then
          QfbookmarkUtils.error("File not found: " .. file_path)
          return
        end

        local ok, err = os.remove(file_path)
        if not ok then
          QfbookmarkUtils.error("Failed to delete file: " .. err)
          return
        end
        QfbookmarkUtils.info("File deleted: `" .. file_path .. "`")
      end,
    },
  })
end

function Mapping.rename_itemqf(base_path)
  __fzf_open_files("Rename", base_path, {
    actions = {
      ["default"] = function(sel)
        local fname = strip_string(sel[1])
        if not fname then
          QfbookmarkUtils.warn("Something went wrong when strip string: `" .. tostring(fname) .. "`")
          return
        end

        local old_path = base_path .. "/" .. fname .. ".json"

        if vim.fn.filereadable(old_path) ~= 1 then
          QfbookmarkUtils.error("File not found: " .. old_path)
          return
        end

        -- Create a new input prompt
        local new_name = vim.fn.input("Rename to: ", fname)
        if not new_name or new_name == "" then
          QfbookmarkUtils.warn "Rename cancelled"
          return
        end

        local new_path = base_path .. "/" .. new_name .. ".json"

        if vim.fn.filereadable(new_path) == 1 then
          QfbookmarkUtils.error("Target file already exists: " .. new_path)
          return
        end

        local ok, err = os.rename(old_path, new_path)
        if not ok then
          QfbookmarkUtils.error("Failed to rename file: " .. err)
          return
        end

        QfbookmarkUtils.info("Renamed: `" .. old_path .. "` -> `" .. new_path .. "`")
      end,
    },
  })
end

return M
