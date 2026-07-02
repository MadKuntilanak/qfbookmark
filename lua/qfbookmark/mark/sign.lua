local QfbookmarkUtils = require "qfbookmark.utils"

local M = {
  sign_cache = {},
}

---@param icon string
---@param hl_group string
function M.register_sign(sign_name, icon, hl_group)
  if not M.sign_cache[sign_name] then
    M.sign_cache[sign_name] = true
    vim.fn.sign_define(sign_name, { text = icon, texthl = hl_group })
  end
end

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
function M.get_sign_unused_ids(bufnr, existing_ids)
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
---@param lnum integer
---@return table
function M.get_sign_at_line(bufnr, lnum)
  local all_signs = get_all_signs_buffer(bufnr)

  for _, x in pairs(all_signs) do
    if x.lnum == lnum then
      return x
    end
  end

  return {}
end

---@param id number
---@param bufnr? number
function M.delete_sign(id, bufnr)
  local Config = require("qfbookmark.config").defaults
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if QfbookmarkUtils.is_valid(bufnr) then
    vim.fn.sign_unplace(Config.sign_group, { buffer = bufnr, id = id })
  end
end

---@param bufnr integer
---@param id integer
---@param sign_name string
---@param sign_group string
---@param opts? vim.fn.sign_place.dict
---@return integer|nil
function M.set_signplace(bufnr, id, sign_group, sign_name, opts)
  if not QfbookmarkUtils.is_valid(bufnr) then
    return nil
  end

  local ok, sign_id = pcall(vim.fn.sign_place, id, sign_group, sign_name, bufnr, opts)
  if not ok then
    return nil
  end
  return sign_id
end

---@param id number
---@param bufnr number
---@param lnum number
---@param category QFBookMarkMode
---@return integer|nil
function M.insert_sign(id, category, bufnr, lnum)
  local Config = require("qfbookmark.config").defaults
  local sign_name = "Qfbookmark" .. category

  local QfbookmarkMarkUtils = require "qfbookmark.mark.utils"
  local keyword_def = QfbookmarkMarkUtils.get_keyword_def(category)
  M.register_sign(sign_name, keyword_def.icon, keyword_def.hl_group)

  local priority = Config.extmarks.priority and Config.extmarks.priority or 1
  return M.set_signplace(bufnr, id, Config.sign_group, sign_name, { lnum = lnum, priority = priority })
end

return M
