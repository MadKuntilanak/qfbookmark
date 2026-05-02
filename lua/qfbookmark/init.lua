local config = require "qfbookmark.config"

local plugin_load

---@param user_opts QFBookmarkConfig
local function setup(user_opts)
  if plugin_load == nil then
    local opts = config.update_settings(user_opts)
    config.init(opts)
    plugin_load = true
  end
end

return { setup = setup }
