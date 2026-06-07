local qf = require "qfbookmark.qf"
local Config = require("qfbookmark.config").defaults
local QfbookmarkUtils = require "qfbookmark.utils"

local M = {}

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
---@param is_marks boolean
---@param is_todo_note boolean
function M.set_keymaps(keymaps_opts, is_bufnr, is_marks, is_todo_note)
  is_bufnr = is_bufnr or false
  is_marks = is_marks or false
  is_todo_note = is_todo_note or false

  for _, cmd in pairs(keymaps_opts) do
    if not should_set_keymap(cmd) then
      goto continue
    end

    local key_func = cmd.from_user and cmd.func or qf[cmd.func]

    local keymap_opts = { desc = cmd.desc }
    local keys = cmd.keys

    if is_bufnr then
      keymap_opts.buffer = vim.api.nvim_get_current_buf()
    end
    if type(keys) == "table" then
      for _, k in pairs(keys) do
        vim.keymap.set(cmd.mode, k, key_func, keymap_opts)
      end
    end
    if type(keys) == "string" then
      vim.keymap.set(cmd.mode, keys, key_func, keymap_opts)
    end

    ::continue::
  end
end

---@param name_au string
---@param pattern string | table<string>
---@param keymaps_opts QFBookKeys[]
function M.set_keymaps_ft(name_au, pattern, keymaps_opts)
  local augroup = QfbookmarkUtils.create_augroup_name(name_au)
  vim.api.nvim_create_autocmd("FileType", {
    pattern = pattern,
    group = augroup,
    callback = function()
      M.set_keymaps(keymaps_opts, true, false, false)
    end,
  })
end

---@param keymap_group {keymaps: QFBookKeys[], is_set?: boolean}
---@param dest QFBookKeys[]
local function append_active_keymaps(keymap_group, dest)
  local is_set = keymap_group.is_set or false
  if is_set then
    for _, keys in pairs(keymap_group.keymaps) do
      dest[#dest + 1] = keys
    end
  end
  return dest
end

---@param tbl_cmdline_strings QFBookKeymapCMDLineStrings
---@return QFBookKeys[], QFBookKeys[]
local function set_user_mappings(tbl_cmdline_strings)
  local cmdline_strs = tbl_cmdline_strings.commands
  if vim.tbl_isempty(cmdline_strs) then
    return {}, {}
  end

  ---@type QFBookKeys[]
  local keys = {}

  ---@type QFBookKeys[]
  local keys_ft = {}

  for _, val in pairs(cmdline_strs) do
    if not val.mode or val.mode == "" then
      val.mode = "n"
    end

    local keymap_func

    if type(val.cmd) == "function" then
      keymap_func = function()
        local results
        if QfbookmarkUtils.is_loclist() then
          local data = QfbookmarkUtils.get_data_qf(true)
          results = data.location
        else
          local data = QfbookmarkUtils.get_data_qf()
          results = data.quickfix
        end

        if not vim.tbl_isempty(results.items) then
          local qflist_stack_idx = QfbookmarkUtils.get_current_qf_idx()
          ---@diagnostic disable-next-line: inject-field
          results.stack_idx = qflist_stack_idx
        end

        val.cmd(results)
      end
    elseif type(val.cmd) == "string" then
      keymap_func = ":" .. val.cmd
      -- vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(cmd, true, false, true), "n", false)
      -- end
    end

    val.desc = val.desc .. " [QFbookmark]"

    if val.buffer then
      keys_ft[#keys_ft + 1] = {
        keys = val.key,
        func = keymap_func,
        mode = val.mode,
        desc = val.desc,
        from_user = true,
      }
    else
      keys[#keys + 1] = {
        keys = val.key,
        func = keymap_func,
        mode = val.mode,
        desc = val.desc,
        from_user = true,
      }
    end
  end

  return keys, keys_ft
end

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

function M.setup()
  ---@type QFBookKeys[]
  local keys = {
    -- TOGGLE
    {
      desc = "Qf: toggle open loclist [QFbookmark]",
      func = "toggle_open_loclist",
      keys = get_keymap(Config.keymaps, "loclist", "toggle_open"),
      mode = { "n", "x" },
    },
    {
      desc = "Qf: toggle open quickfix [QFbookmark]",
      func = "toggle_open_qflist",
      keys = get_keymap(Config.keymaps, "quickfix", "toggle_open"),
      mode = { "n", "x" },
    },
    -- ADD item
    {
      desc = "Qf: add item to loclist [QFbookmark]",
      func = "add_item_loclist",
      keys = get_keymap(Config.keymaps, "loclist", "add_item"),
      mode = "n",
    },
    {
      desc = "Qf: add item to quickfix [QFbookmark]",
      func = "add_item_qflist",
      keys = get_keymap(Config.keymaps, "quickfix", "add_item"),
      mode = "n",
    },
    -- OPEN SAVE AND LOAD
    {
      desc = "Qf: load or save qf to file [QFbookmark]",
      func = "save_or_load",
      keys = get_keymap(Config.keymaps, "actions", "save_or_load"),
      mode = "n",
    },
    -- OPEN MARK WINDOW
    {
      desc = "Qf: open mark harpoon [QFbookmark]",
      func = "open_mark_harpoon_window",
      keys = get_keymap(Config.keymaps, "actions", "mark_win_open"),
      mode = "n",
    },
    -- MARK
    {
      desc = "Qf: add MARK sign [QFbookmark]",
      func = "add_mark_sign",
      keys = get_keymap(Config.keymaps, "actions", "mark"),
      mode = "n",
    },
    -- FIX
    {
      desc = "Qf: add FIX sign [QFbookmark]",
      func = "add_fix_sign",
      keys = get_keymap(Config.keymaps, "actions", "fix"),
      mode = "n",
    },
    -- DEBUG
    {
      desc = "Qf: add DEBUG sign [QFbookmark]",
      func = "add_debug_sign",
      keys = get_keymap(Config.keymaps, "actions", "debug"),
      mode = "n",
    },
    -- NOTE
    {
      desc = "Qf: add NOTE sign [QFbookmark]",
      func = "add_note_sign",
      keys = get_keymap(Config.keymaps, "actions", "note"),
      mode = "n",
    },
    -- DELETE
    {
      desc = "Qf: delete mark sign [QFbookmark]",
      func = "delete_mark",
      keys = get_keymap(Config.keymaps, "actions", "delete_mark"),
      mode = "n",
    },
    {
      desc = "Qf: delete all mark buffer sign [QFbookmark]",
      func = "delete_mark_buffer",
      keys = get_keymap(Config.keymaps, "actions", "delete_mark_buffer"),
      mode = "n",
    },

    -- NOTE LOCAL OR GLOBAL
    {
      desc = "Qf: toggle open note global project [QFbookmark]",
      func = "toggle_open_note_global",
      keys = get_keymap(Config.keymaps, "note", "toggle_global_note"),
      mode = "n",
    },
    {
      desc = "Qf: toggle open note local project [QFbookmark]",
      func = "toggle_open_note_local",
      keys = get_keymap(Config.keymaps, "note", "toggle_local_note"),
      mode = "n",
    },
    {
      desc = "Qf: toggle rotate window note [QFbookmark]",
      func = "toggle_rotate_note_window",
      keys = get_keymap(Config.keymaps, "navigation", "window", "rotate_layout_note"),
      mode = "n",
    },

    -- BUFFERS
    {
      desc = "Qf: open buffer [QFbookmark]",
      func = "open_buffers",
      keys = get_keymap(Config.keymaps, "actions", "buffers"),
      mode = { "n" },
    },

    -- NAVI MARK
    {
      desc = "Qf: next mark [QFbookmark]",
      func = "next_mark",
      keys = get_keymap(Config.keymaps, "navigation", "mark", "next"),
      mode = { "n" },
    },
    {
      desc = "Qf: prev mark [QFbookmark]",
      func = "prev_mark",
      keys = get_keymap(Config.keymaps, "navigation", "mark", "prev"),
      mode = { "n" },
    },

    -- ╭────────────────╮
    -- │ debug commands │
    -- ╰────────────────╯
    {
      desc = "Qf: -- debug -- [QFbookmark]",
      func = "debug_qf",
      keys = "<Leader>q?",
      mode = "n",
    },
  }

  ---@type QFBookKeys[]
  local keys_ft = {
    -- OPEN
    {
      desc = "Qf: open item [QFbookmark]",
      func = "open_item_qf",
      keys = get_keymap(Config.keymaps, "open_item", "default", "keys"),
      mode = "n",
    },
    {
      desc = "Qf: open item in split [QFbookmark]",
      func = "open_item_in_split",
      keys = get_keymap(Config.keymaps, "open_item", "split", "keys"),
      mode = { "n", "x" },
    },
    {
      desc = "Qf: open item in vsplit [QFbookmark]",
      func = "open_item_in_vsplit",
      keys = get_keymap(Config.keymaps, "open_item", "vsplit", "keys"),
      mode = { "n", "x" },
    },
    {
      desc = "Qf: open item in tab [QFbookmark]",
      func = "open_item_in_tab",
      keys = get_keymap(Config.keymaps, "open_item", "tab", "keys"),
      mode = { "n", "x" },
    },
    -- RENAME
    {
      desc = "Qf: rename title quickfix [QFbookmark]",
      func = "rename_title_qf",
      keys = get_keymap(Config.keymaps, "actions", "rename_title"),
      mode = "n",
    },
    -- NAV
    {
      desc = "Qf: next item [QFbookmark]",
      func = "next_item",
      keys = get_keymap(Config.keymaps, "navigation", "quicklist", "next"),
      mode = { "n" },
    },
    {
      desc = "Qf: prev item [QFbookmark]",
      func = "prev_item",
      keys = get_keymap(Config.keymaps, "navigation", "quicklist", "prev"),
      mode = { "n" },
    },
    -- DELETE
    {
      desc = "Qf: delete item [QFbookmark]",
      func = "delete_item",
      keys = get_keymap(Config.keymaps, "actions", "delete_item"),
      mode = { "n" },
    },
    {
      desc = "Qf: delete all items [QFbookmark]",
      func = "delete_all_items",
      keys = get_keymap(Config.keymaps, "actions", "delete_item_all"),
      mode = "n",
    },
    -- HISTORY
    {
      desc = "Qf: next history qf [QFbookmark]",
      func = "next_hist_qf",
      keys = get_keymap(Config.keymaps, "navigation", "quicklist", "next_hist"),
      mode = { "n", "x" },
    },
    {
      desc = "Qf: prev history qf [QFbookmark]",
      func = "prev_hist_qf",
      keys = get_keymap(Config.keymaps, "navigation", "quicklist", "prev_hist"),
      mode = { "n", "x" },
    },
  }

  local keys_ft_trouble = {
    {
      desc = "Qf: convert toggle quickfix [QFbookmark]",
      func = "integrations_trouble_qflist",
      keys = get_keymap(Config.keymaps, "integrations", "trouble", "toggle_qflist"),
      mode = "n",
    },
    {
      desc = "Qf: convert toggle loclist [QFbookmark]",
      func = "integrations_trouble_loclist",
      keys = get_keymap(Config.keymaps, "integrations", "trouble", "toggle_loclist"),
      mode = "n",
    },
  }

  if Config.keymaps.integrations.copyline and Config.keymaps.integrations.copyline.enabled then
    keys[#keys + 1] = {
      desc = "Qf: open copyline [QFbookmark]",
      func = "integrations_copyline",
      keys = get_keymap(Config.keymaps, "integrations", "copyline", "toggle"),
      mode = "n",
    }
  end

  if Config.window.layout and Config.window.layout.enabled then
    append_active_keymaps({
      is_set = Config.window.layout.enabled,
      keymaps = {
        {
          desc = "Qf: move window to up [QFbookmark]",
          func = "move_layout_qf_up",
          keys = get_keymap(Config.keymaps, "navigation", "window", "move_up"),
          mode = { "n", "x" },
        },
        {
          desc = "Qf: move window to bottom [QFbookmark]",
          func = "move_layout_qf_down",
          keys = get_keymap(Config.keymaps, "navigation", "window", "move_down"),
          mode = { "n", "x" },
        },
      },
    }, keys_ft)
  end

  if Config.keymaps.integrations.grugfar and Config.keymaps.integrations.grugfar.enabled then
    append_active_keymaps({
      is_set = Config.keymaps.integrations.grugfar.enabled,
      keymaps = {
        {
          desc = "Qf: search in grugfar [QFbookmark integration]",
          func = "integrations_grugfar",
          keys = get_keymap(Config.keymaps, "integrations", "grugfar", "toggle"),
          mode = "n",
        },
      },
    }, keys_ft)
  end

  if Config.keymaps.integrations.trouble and Config.keymaps.integrations.trouble.enabled then
    append_active_keymaps({
      is_set = Config.keymaps.integrations.trouble.enabled,
      keymaps = {
        {
          desc = "Qf: open trouble quickfix [QFbookmark integration]",
          func = "integrations_trouble_qflist",
          keys = get_keymap(Config.keymaps, "integrations", "trouble", "toggle_qflist"),
          mode = "n",
        },
        {
          desc = "Qf: open trouble loclist [QFbookmark integration]",
          func = "integrations_trouble_loclist",
          keys = get_keymap(Config.keymaps, "integrations", "trouble", "toggle_loclist"),
          mode = "n",
        },
      },
    }, keys_ft)

    M.set_keymaps_ft("Trouble", { "trouble" }, keys_ft_trouble)
  end

  if Config.keymaps.integrations.cmdline_strings and Config.keymaps.integrations.cmdline_strings.enabled then
    local mapping_cmdline = Config.keymaps.integrations.cmdline_strings
    local user_key, user_keyft = set_user_mappings(mapping_cmdline)

    local function merge_with_concatenate(t1, t2)
      for _, v in ipairs(t2) do
        table.insert(t1, v)
      end
      return t1
    end

    keys = merge_with_concatenate(user_key, keys)
    keys_ft = merge_with_concatenate(keys_ft, user_keyft)
  end

  -- Mark_Harpoon
  if Config.keymaps.actions and Config.keymaps.actions.harpoon then
    for i, _ in pairs(Config.keymaps.actions.harpoon) do
      local idx = tonumber(vim.split(i, "_")[2])
      if idx then
        keys[#keys + 1] = {
          desc = "Qf: open Mark_" .. idx .. " [QFbookmark]",
          func = function()
            qf.goto_mark_index(idx)
          end,
          keys = Config.keymaps.actions.harpoon[i],
          mode = "n",
          from_user = true,
        }
      end
    end
  end

  M.set_keymaps_ft("Mappings", { "qf" }, keys_ft)
  M.set_keymaps(keys, false, false, true)
  qf.setup_autocmds()
end

return M
