local M = {}

local qf = require "qfbookmark.qf"
local Config = require("qfbookmark.config").defaults
local QfbookmarkKeymapUtils = require "qfbookmark.keymaps.utils"

---@type QFBookKeys[]
local keys = {}

---@type QFBookKeys[]
local keys_ft = {}

---@return nil|string|string[]
local function get_keymap(tbl, ...)
  local node = tbl
  for _, key in ipairs { ... } do
    if type(node) ~= "table" or node[key] == nil then
      return nil
    end
    node = node[key]
  end

  if type(node) == "table" and vim.tbl_isempty(node) then
    return nil
  end

  if type(node) == "string" and #node == 0 then
    return nil
  end

  return node
end

local function mark_keymaps()
  if not Config.window.mark.enabled then
    return
  end

  QfbookmarkKeymapUtils.append_active_keymaps({
    is_set = true,
    keymaps = {
      -- DELETE MARK
      {
        desc = "Qfmark: delete mark sign",
        func = "delete_mark",
        keys = get_keymap(Config.keymaps, "mark", "del_mark"),
        mode = "n",
      },
      {
        desc = "Qfmark: delete all mark buffer sign",
        func = "delete_mark_buffer",
        keys = get_keymap(Config.keymaps, "mark", "del_mark_buffer"),
        mode = "n",
      },

      -- OPEN MARK WINDOW
      {
        desc = "Qfmark: open mark window",
        func = "open_mark_harpoon_window",
        keys = get_keymap(Config.keymaps, "mark", "toggle_open"),
        mode = "n",
      },

      -- MARK
      {
        desc = "Qfmark: add MARK sign",
        func = "add_mark_sign",
        keys = get_keymap(Config.keymaps, "mark", "add_mark"),
        mode = "n",
      },
      -- FIX
      {
        desc = "Qfmark: add FIX sign",
        func = "add_fix_sign",
        keys = get_keymap(Config.keymaps, "mark", "add_fix"),
        mode = "n",
      },
      -- DEBUG
      {
        desc = "Qfmark: add DEBUG sign",
        func = "add_debug_sign",
        keys = get_keymap(Config.keymaps, "mark", "add_debug"),
        mode = "n",
      },
      -- NOTE
      {
        desc = "Qfmark: add NOTE sign",
        func = "add_note_sign",
        keys = get_keymap(Config.keymaps, "mark", "add_mark_annotation"),
        mode = "n",
      },

      -- NAV MARK
      {
        desc = "Qfmark: next mark",
        func = "next_mark",
        keys = get_keymap(Config.keymaps, "mark", "next_mark"),
        mode = { "n" },
      },
      {
        desc = "Qfmark: prev mark",
        func = "prev_mark",
        keys = get_keymap(Config.keymaps, "mark", "prev_mark"),
        mode = { "n" },
      },

      -- NOTE: Remove this keybinding before release
      -- { -- Debug only
      --   desc = "Qfmark: debug",
      --   func = "debug_qf",
      --   keys = get_keymap(Config.keymaps, "mark", "debug"),
      --   mode = { "n" },
      -- },
    },
  }, keys)

  for i, _ in pairs(Config.keymaps.mark.harpoon) do
    local idx = tonumber(vim.split(i, "_")[2])
    if idx then
      keys[#keys + 1] = {
        desc = "Qfmark: open Mark_" .. idx .. "",
        func = function()
          qf.goto_mark_index(idx)
        end,
        keys = Config.keymaps.mark.harpoon[i],
        mode = "n",
        from_user = true,
      }
    end
  end
end

local function qf_keymaps()
  if not Config.window.quickfix.enabled then
    return
  end

  QfbookmarkKeymapUtils.append_active_keymaps({
    is_set = true,
    keymaps = {
      -- OPEN WINDOW
      {
        desc = "Qfmark: toggle loclist",
        func = "toggle_open_loclist",
        keys = get_keymap(Config.keymaps, "quickfix", "open_toggle_loc"),
        mode = { "n", "x" },
      },
      {
        desc = "Qfmark: toggle quickfix",
        func = "toggle_open_qflist",
        keys = get_keymap(Config.keymaps, "quickfix", "open_toggle_qf"),
        mode = { "n", "x" },
      },

      -- ADD ITEM
      {
        desc = "Qfmark: add item to loclist",
        func = "add_item_loclist",
        keys = get_keymap(Config.keymaps, "quickfix", "add_item_to_loc"),
        mode = "n",
      },
      {
        desc = "Qfmark: add item to quickfix",
        func = "add_item_qflist",
        keys = get_keymap(Config.keymaps, "quickfix", "add_item_to_qf"),
        mode = "n",
      },

      -- OPEN SAVE AND LOAD
      {
        desc = "Qfmark: load or save qf to file",
        func = "save_or_load",
        keys = get_keymap(Config.keymaps, "quickfix", "save_or_load"),
        mode = "n",
      },
    },
  }, keys)

  QfbookmarkKeymapUtils.append_active_keymaps({
    is_set = true,
    keymaps = {
      {
        desc = "Qfmark: open item",
        func = "open_item_default",
        keys = get_keymap(Config.keymaps, "actions", "default"),
        mode = "n",
      },
      {
        desc = "Qfmark: open item in split",
        func = "open_item_in_split",
        keys = get_keymap(Config.keymaps, "actions", "split"),
        mode = { "n", "x" },
      },
      {
        desc = "Qfmark: open item in vsplit",
        func = "open_item_in_vsplit",
        keys = get_keymap(Config.keymaps, "actions", "vsplit"),
        mode = { "n", "x" },
      },
      {
        desc = "Qfmark: open item in tab",
        func = "open_item_in_tab",
        keys = get_keymap(Config.keymaps, "actions", "tab"),
        mode = { "n", "x" },
      },

      -- RENAME
      {
        desc = "Qfmark: rename title quickfix",
        func = "rename_title_qf",
        keys = get_keymap(Config.keymaps, "quickfix", "rename_title"),
        mode = "n",
      },

      -- NAV
      {
        desc = "Qfmark: next item",
        func = "next_item",
        keys = get_keymap(Config.keymaps, "actions", "next_item"),
        mode = { "n" },
      },
      {
        desc = "Qfmark: prev item",
        func = "prev_item",
        keys = get_keymap(Config.keymaps, "actions", "prev_item"),
        mode = { "n" },
      },
      -- DELETE
      {
        desc = "Qfmark: delete item",
        func = "delete_item",
        keys = get_keymap(Config.keymaps, "actions", "del_item"),
        mode = { "n", "x" },
      },
      {
        desc = "Qfmark: delete all items",
        func = "delete_all_items",
        keys = get_keymap(Config.keymaps, "actions", "del_item_all"),
        mode = "n",
      },

      -- HISTORY
      {
        desc = "Qfmark: next history qf",
        func = "next_hist_qf",
        keys = get_keymap(Config.keymaps, "quickfix", "next_hist"),
        mode = { "n", "x" },
      },
      {
        desc = "Qfmark: prev history qf",
        func = "prev_hist_qf",
        keys = get_keymap(Config.keymaps, "quickfix", "prev_hist"),
        mode = { "n", "x" },
      },

      -- LAYOUT
      {
        desc = "Qfmark: move window to up",
        func = "move_layout_qf_up",
        keys = get_keymap(Config.keymaps, "quickfix", "layout_up"),
        mode = { "n", "x" },
      },
      {
        desc = "Qfmark: move window to bottom",
        func = "move_layout_qf_down",
        keys = get_keymap(Config.keymaps, "quickfix", "layout_down"),
        mode = { "n", "x" },
      },

      -- Select item
      {
        desc = "Qfmark: toggle select",
        func = "qf_toggle_selection",
        keys = get_keymap(Config.keymaps, "actions", "toggle_select"),
        mode = "n",
      },

      {
        desc = "Qfmark: diselect all",
        func = "diselect_all",
        keys = get_keymap(Config.keymaps, "actions", "diselect_all"),
        mode = "n",
      },
    },
  }, keys_ft)

  -- if Config.window.quickfix.allow_number then
  --   local QfbookmarkUtils = require "qfbookmark.utils"
  --   local qf_result
  --
  --   if QfbookmarkUtils.is_loclist() then
  --     local data = QfbookmarkUtils.get_data_qf(true)
  --     qf_result = data.location
  --   else
  --     local data = QfbookmarkUtils.get_data_qf()
  --     qf_result = data.quickfix
  --   end
  --
  --   for i = 1, #qf_result do
  --     QfbookmarkKeymapUtils.append_active_keymaps({
  --       is_set = Config.window.quickfix.allow_number,
  --       keymaps = {
  --         {
  --           desc = "Qfmark: jump to {" .. i .. "}",
  --           func = function()
  --             local curline = qf_result[i]
  --             RUtils.info(curline)
  --             -- Mapping.setup_open_key("default", curline.start_line)
  --           end,
  --           keys = tostring(i),
  --           mode = "n",
  --           from_user = true,
  --         },
  --       },
  --     }, keys_ft)
  --   end
  -- end

  QfbookmarkKeymapUtils.append_active_keymaps({
    is_set = Config.keymaps.quickfix.integrations.trouble.enabled,
    keymaps = {
      {
        desc = "Qfmark: open in trouble (integration)",
        func = "integrations_trouble_qflist",
        keys = get_keymap(Config.keymaps, "quickfix", "integrations", "trouble", "toggle_qflist"),
        mode = "n",
      },
    },
  }, keys_ft)

  QfbookmarkKeymapUtils.append_active_keymaps({
    is_set = Config.keymaps.quickfix.integrations.grugfar.enabled,
    keymaps = {
      {
        desc = "Qfmark: search with grugfar (integration)",
        func = "integrations_grugfar",
        keys = get_keymap(Config.keymaps, "quickfix", "integrations", "grugfar", "toggle"),
        mode = "n",
      },
    },
  }, keys_ft)

  if Config.keymaps.quickfix.integrations.custom.enabled then
    local mapping_qf = Config.keymaps.quickfix.integrations.custom
    if not mapping_qf then
      return
    end

    local user_keys = QfbookmarkKeymapUtils.set_user_mappings(mapping_qf, "quickfix")

    QfbookmarkKeymapUtils.append_active_keymaps({
      is_set = Config.keymaps.quickfix.integrations.custom.enabled,
      keymaps = user_keys,
    }, keys_ft)
  end

  QfbookmarkKeymapUtils.set_keymaps_ft("Quickfix", { "qf" }, keys_ft)
end

local function note_keymaps()
  if not Config.window.note.enabled then
    return
  end

  QfbookmarkKeymapUtils.append_active_keymaps({
    is_set = Config.window.note.enabled,
    keymaps = {
      -- NOTE LOCAL OR GLOBAL
      {
        desc = "Qfmark: toggle global note project",
        func = "toggle_open_note_global",
        keys = get_keymap(Config.keymaps, "note", "toggle_open_global"),
        mode = "n",
      },
      {
        desc = "Qfmark: toggle local note project",
        func = "toggle_open_note_local",
        keys = get_keymap(Config.keymaps, "note", "toggle_open_local"),
        mode = "n",
      },

      -- {
      --   desc = "Qfmark: add to note global",
      --   func = "add_note_to_global",
      --   keys = get_keymap(Config.keymaps, "note", "toggle_open_global"),
      --   mode = "v",
      -- },
      -- {
      --   desc = "Qfmark: add to note local",
      --   func = "add_note_to_local",
      --   keys = get_keymap(Config.keymaps, "note", "toggle_open_local"),
      --   mode = "v",
      -- },

      {
        desc = "Qfmark: rotate note window",
        func = "toggle_rotate_note_window",
        keys = get_keymap(Config.keymaps, "note", "layout_rotate"),
        mode = "n",
      },
    },
  }, keys)

  if Config.keymaps.note.integrations.custom.enabled then
    local mapping_note = Config.keymaps.note.integrations.custom
    if not mapping_note then
      return
    end

    local user_keys = QfbookmarkKeymapUtils.set_user_mappings(mapping_note, "note")

    QfbookmarkKeymapUtils.append_active_keymaps({
      is_set = Config.keymaps.note.integrations.custom.enabled,
      keymaps = user_keys,
    }, keys)
  end
end

local function buffers_keymaps()
  if not Config.window.buffers.enabled then
    return
  end

  QfbookmarkKeymapUtils.append_active_keymaps({
    is_set = true,
    keymaps = {
      -- OPEN
      {
        desc = "Qfmark: open buffer",
        func = "open_buffers",
        keys = get_keymap(Config.keymaps, "buffers", "toggle_open"),
        mode = { "n" },
      },
    },
  }, keys)
end

local function trouble_keymaps()
  if not Config.keymaps.quickfix.integrations.trouble.enabled then
    return
  end

  ---@type QFBookKeys[]
  local keys_ft_trouble = {}

  QfbookmarkKeymapUtils.append_active_keymaps({
    is_set = Config.keymaps.quickfix.integrations.trouble.enabled,
    keymaps = {
      {
        desc = "Qfmark: convert trouble into quickfix (integration)",
        func = "integrations_trouble_qflist",
        keys = get_keymap(Config.keymaps, "quickfix", "integrations", "trouble", "toggle_qflist"),
        mode = "n",
      },
      {
        desc = "Qfmark: convert trouble into loclist (integration)",
        func = "integrations_trouble_loclist",
        keys = get_keymap(Config.keymaps, "quickfix", "integrations", "trouble", "toggle_loclist"),
        mode = "n",
      },
    },
  }, keys_ft_trouble)

  QfbookmarkKeymapUtils.set_keymaps_ft("Trouble", { "trouble" }, keys_ft_trouble)
end

local function copyline_keymaps()
  if not Config.keymaps.quickfix.integrations.copyline.enabled then
    return
  end

  QfbookmarkKeymapUtils.append_active_keymaps({
    is_set = Config.keymaps.quickfix.integrations.copyline.enabled,
    keymaps = {
      {
        desc = "Qfmark: open copyline",
        func = "integrations_copyline",
        keys = get_keymap(Config.keymaps, "quickfix", "integrations", "copyline", "toggle"),
        mode = "n",
      },
    },
  }, keys)
end

function M.setup()
  mark_keymaps()
  qf_keymaps()
  note_keymaps()
  buffers_keymaps()

  copyline_keymaps()
  trouble_keymaps()

  QfbookmarkKeymapUtils.set_keymaps(keys, false)
end

return M
