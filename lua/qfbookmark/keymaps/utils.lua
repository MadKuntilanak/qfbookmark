local QfbookmarkUtils = require "qfbookmark.utils"

local M = {}

---@param entry table
---@return boolean
local function should_set_keymap(entry)
  if entry.keys == nil then
    return false
  end

  if type(entry.keys) == "string" and entry.keys == "" then
    return false
  end

  if type(entry.keys) == "table" and vim.tbl_isempty(entry.keys) then
    return false
  end

  return true
end

---@param keymaps_opts QFBookKeys[]
---@param is_bufnr boolean
function M.set_keymaps(keymaps_opts, is_bufnr)
  is_bufnr = is_bufnr or false

  for _, cmd in pairs(keymaps_opts) do
    if not should_set_keymap(cmd) then
      goto continue
    end

    local key_func = cmd.from_user and cmd.func or {}
    if type(key_func) == "table" then
      local qf = require "qfbookmark.qf"
      key_func = qf[cmd.func]
    end

    local keymap_opts = { desc = cmd.desc }
    local key = cmd.keys

    if is_bufnr then
      if not keymap_opts.buffer then
        keymap_opts.buffer = vim.api.nvim_get_current_buf()
      end
    end
    if type(key) == "table" then
      for _, k in pairs(key) do
        vim.keymap.set(cmd.mode, k, key_func, keymap_opts)
      end
    end
    if type(key) == "string" then
      vim.keymap.set(cmd.mode, key, key_func, keymap_opts)
    end

    ::continue::
  end
end

---@param keymap_group {keymaps: QFBookKeys[], is_set?: boolean}
---@return QFBookKeys[]
function M.append_active_keymaps(keymap_group, dest)
  local is_set = keymap_group.is_set or false
  if is_set then
    for _, keys in pairs(keymap_group.keymaps) do
      dest[#dest + 1] = keys
    end
  end
  return dest
end

---@param name_au string
---@param pattern string | table<string>
---@param keymaps_opts QFBookKeys[]
function M.set_keymaps_ft(name_au, pattern, keymaps_opts)
  local augroup_name = "Mapping" .. name_au
  local augroup = QfbookmarkUtils.create_augroup_name(augroup_name)
  vim.api.nvim_create_autocmd("FileType", {
    pattern = pattern,
    group = augroup,
    callback = function()
      M.set_keymaps(keymaps_opts, true)
    end,
  })
end

local select_providers = {
  ["quickfix"] = function(val)
    local qf_result, selected

    if QfbookmarkUtils.is_loclist() then
      local data = QfbookmarkUtils.get_data_qf(true)
      qf_result = data.location
    else
      local data = QfbookmarkUtils.get_data_qf()
      qf_result = data.quickfix
    end

    if not vim.tbl_isempty(qf_result.items) then
      local qflist_stack_idx = QfbookmarkUtils.get_current_qf_idx()
      ---@diagnostic disable-next-line: inject-field
      qf_result.stack_idx = qflist_stack_idx
    end

    local qf = require "qfbookmark.qf"
    selected = qf.get_qf_selected()

    local results = {
      selected = selected or {},
      data = qf_result or {},
    }

    val.cmd(results)
  end,
  ["mark"] = function(val)
    local marks_selected = require "qfbookmark.ui.keymaps"
    local results = marks_selected.get_selected_marks()
    val.cmd(results)
  end,
  ["buffers"] = function(val)
    local buffer_selected = require "qfbookmark.ui.keymaps"
    local results = buffer_selected.get_selected_buffers()
    val.cmd(results)
  end,
}

---@param tbl_cmdline_strings QFBookKeymapCustomIntegration
---@param providers QFBookListProviders
---@param buf? integer
---@return QFBookKeys[]
function M.set_user_mappings(tbl_cmdline_strings, providers, buf)
  if not providers or providers == nil then
    return {}
  end

  local cmdline_strs = tbl_cmdline_strings.commands
  if vim.tbl_isempty(cmdline_strs) then
    return {}
  end

  ---@type QFBookKeys[]
  local __keys = {}

  for idx, val in pairs(cmdline_strs) do
    if not val.key or #val.key == 0 then
      goto continue
    end

    if not val.desc or #val.desc == 0 then
      val.desc = "Qfmark: user command " .. tostring(idx)
    end

    if not val.mode or #val.mode == 0 then
      val.mode = "n"
    end

    local keymap_func

    if type(val.cmd) == "function" then
      local fun = select_providers[providers]
      keymap_func = function()
        fun(val)
      end
    elseif type(val.cmd) == "string" then
      keymap_func = ":" .. val.cmd
    end

    if buf then
      if not val.buffer then
        if vim.api.nvim_buf_is_valid(buf) then
          val.buffer = buf
        end
      end
    end

    __keys[#__keys + 1] = {
      keys = val.key,
      func = keymap_func,
      mode = val.mode,
      desc = val.desc,
      buffer = val.buffer or nil,
      from_user = true,
    }

    ::continue::
  end

  return __keys
end

return M
