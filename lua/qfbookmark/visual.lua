local M = { sign_cache = {} }
local Config = require("qfbookmark.config").defaults

---@param id number
---@param bufnr number
---@param line number
---@param mark_mode QFBookMarkMode
---@param extmarkspec QFBookSpec
function M.insert_signs(id, mark_mode, bufnr, line, extmarkspec)
  local sign_name = "Qfbookmark" .. mark_mode

  if not M.sign_cache[sign_name] then
    M.sign_cache[sign_name] = true
    if Config.extmarks.enabled then
      vim.fn.sign_define(sign_name, { text = extmarkspec.icon, texthl = extmarkspec.hl_group })
    end
  end

  local priority = 1
  if Config.extmarks.priority then
    priority = Config.extmarks.priority
  end

  vim.fn.sign_place(id, Config.sign_group, sign_name, bufnr, { lnum = line, priority = priority })
end

---@param id number
---@param bufnr? number
function M.remove_sign(id, bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  vim.fn.sign_unplace(Config.sign_group, { buffer = bufnr, id = id })
end

return M
