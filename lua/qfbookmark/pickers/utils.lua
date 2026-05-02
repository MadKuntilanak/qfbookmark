local M = {}

---@return boolean
function M.is_blank(s)
  return (
    s == nil
    or s == vim.NIL
    or (type(s) == "string" and string.match(s, "%S") == nil)
    or (type(s) == "table" and next(s) == nil)
  )
end

return M
