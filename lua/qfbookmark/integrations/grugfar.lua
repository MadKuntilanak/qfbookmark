local QfbookmarkUtils = require "qfbookmark.utils"

local loaded = false
local Grugfar
local GrugfarOpts

local silent_notify = false

local function setup_grugfar()
  if loaded then
    return Grugfar, GrugfarOpts
  end

  local ok, _ = pcall(require, "grug-far")
  if not ok then
    if not silent_notify then
      QfbookmarkUtils.error "This integration requires `MagicDuck/grug-far.nvim` (https://github.com/MagicDuck/grug-far.nvim)"
      silent_notify = true
      return
    end
    return
  end

  Grugfar = require "grug-far"
  GrugfarOpts = require "grug-far.opts"
  loaded = true

  return Grugfar, GrugfarOpts
end

local M = {}

local function check_duplicate_elements(tbl, element)
  for _, x in pairs(tbl) do
    if x == element then
      return true
    end
  end
  return false
end

local is_silent_opts_grugfar_changed = false

---@param list_type QFBookListType
---@param is_grugfar_ft? boolean
---@param is_loc? boolean
function M.handle_toggle_qf(list_type, is_grugfar_ft, is_loc)
  Grugfar, GrugfarOpts = setup_grugfar()
  if not Grugfar or not GrugfarOpts then
    return
  end

  is_grugfar_ft = is_grugfar_ft or false
  is_loc = is_loc or false

  local is_location_target = list_type == "loclist"
  local data_list = QfbookmarkUtils.get_data_qf(is_location_target)
  local results = {}
  if is_location_target then
    results = data_list.location
  else
    results = data_list.quickfix
  end

  if vim.tbl_isempty(results.items) then
    QfbookmarkUtils.warn "Nothing todo. data is empty!"
    return
  end

  local paths = {}

  for _, x in pairs(results.items) do
    if #x.filename > 0 then
      if not check_duplicate_elements(paths, x.filename) then
        paths[#paths + 1] = x.filename
      end
    end
  end

  Grugfar.open {
    prefills = {
      search = "",
      replacement = "",
      filesFilter = "",
      flags = "--hidden",
      paths = table.concat(paths, "  "),
    },
  }

  local cfg_user_grugfar = GrugfarOpts.getGlobalOptions()
  local mode_open = "wincmd L"

  if vim.bo.filetype == "grug-far" then
    local window_creation_cmd = cfg_user_grugfar.windowCreationCommand
    if not window_creation_cmd then
      if not is_silent_opts_grugfar_changed then
        QfbookmarkUtils.warn "Option windowCreationCommand `grug-far` was changed."
        is_silent_opts_grugfar_changed = true
      end
    else
      if window_creation_cmd == "aboveleft vsplit" then
        mode_open = "wincmd H"
      end
    end
  end

  vim.cmd(mode_open)
  vim.schedule(function()
    vim.wo.winhighlight = ""
  end)
end

return M
