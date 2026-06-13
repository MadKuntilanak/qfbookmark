local M = {}

---@type QFBookmarkConfig
M.defaults = {
  save_dir = vim.fn.stdpath "data" .. "/qfbookmark",
  picker = "default", -- fzf-lua
  extmarks = {
    priority = 20,
    excluded = {
      buftypes = {},
      filetypes = {},
    },
    throttle = 200,
    keywords = {
      MARK = { icon = "📌", hl_group = "QFBookMark", alt = " -> " },
      FIX = { icon = "🔧", hl_group = "QFBookFix", alt = " -> " },
      DEBUG = { icon = "🚧", hl_group = "QFBookDebug", alt = " -> " },
      NOTE = { icon = "📝", hl_group = "QFBookNote", alt = " -> " },
    },
  },
  window = {
    notify = { mark = true, plugin = true },
    quickfix = {
      enabled = true,
      copen = "belowright copen",
      lopen = "belowright lopen",
      theme = { enabled = true, limit = 50, highlight = true },
      actions = {
        auto_center = true,
        auto_unfold = true,
      },
    },
    note = {
      open_cmd = {
        mode = "float",
        anchor = "SE",
      },
      size = "40%",
      filetype = "org",
      current_project = {
        enabled = true,
        filename = "TODO.org",
      },
    },
    mark = {
      anchor = "SE",
      keymap = {
        up = "",
        down = "",
        move_item_down = "<a-n>",
        move_item_up = "<a-p>",

        select = "<Tab>",
        zoom = "<C-z>",

        load_all = "<F4>",

        scroll_preview_up = "<C-u>",
        scroll_preview_down = "<C-d>",
        scroll_preview_up_fast = "<C-b>",
        scroll_preview_down_fast = "<C-f>",
      },

      on_send = nil,
    },
  },
  keymaps = {
    disable_all = false,

    actions = { -- General actions
      delete_mark = "dm",
      delete_mark_buffer = "dM",
      delete_item = "dd",
      delete_item_all = "<Localleader>qC",
      rename_title = "<Localleader>qR",

      save_or_load = "<Leader>qy",
      mark_win_open = "gp",
      buffers = "gn",

      mark = "<Leader>qq",
      fix = "<Leader>qf",
      debug = "<Leader>qd",
      note = "<Leader>qn",

      harpoon = {
        mark_1 = "<a-1>",
        mark_2 = "<a-2>",
        mark_3 = "<a-3>",
        mark_4 = "<a-4>",
        mark_5 = "<a-5>",
        mark_6 = "<a-6>",
        mark_7 = "<a-7>",
        mark_8 = "<a-8>",
        mark_9 = "<a-9>",
      },
    },

    open_item = {
      default = { keys = { "o", "<CR>" }, auto_close = true },
      split = { keys = { "ss", "<C-s>" }, auto_close = false },
      vsplit = { keys = { "sv", "<C-v>" }, auto_close = false },
      tab = { keys = { "st", "tn" }, auto_close = true },
    },

    navigation = {
      quicklist = {
        next = "<a-n>",
        prev = "<a-p>",
        next_hist = "gl",
        prev_hist = "gh",
      },
      window = {
        move_up = "<c-k>",
        move_down = "<c-j>",
        rotate_layout_note = "<a-=>",
      },
      mark = {
        next = "gj",
        prev = "gk",
      },
    },

    quickfix = {
      toggle_open = "<Leader>qj",
      add_item = "tt",
    },
    loclist = {
      toggle_open = "<Leader>ql",
      add_item = "ty",
    },

    note = {
      toggle_local_note = "<Leader>fn",
      toggle_global_note = "<Leader>fN",
    },
    integrations = {
      trouble = { enabled = true, toggle_qflist = "Q", toggle_loclist = "L" },
      grugfar = { enabled = true, toggle = "<Localleader>gg" },
      copyline = { enabled = true, toggle = "<Leader>qc" },
      cmdline_strings = { enabled = false, commands = {} },
    },
  },
}

-- +-----------------------------------------------------------------------------+
-- |                    QFTF: Quickfix Title Format Function                     |
-- +-----------------------------------------------------------------------------+
---@param opts WindowConfig
local function make_qftf(opts)
  local _qftf_limit = opts.quickfix.theme.limit
  local _fname_fmt1 = "%-" .. _qftf_limit .. "s"
  local _fname_fmt2 = "…%." .. (_qftf_limit - 1) .. "s"
  local _valid_fmt = "%s │%5d:%-3d│%s %s"

  function _G.qftf(info)
    local items
    if info.quickfix == 1 then
      items = vim.fn.getqflist({ id = info.id, items = 0 }).items
    else
      items = vim.fn.getloclist(info.winid, { id = info.id, items = 0 }).items
    end

    local ret = {}
    for i = info.start_idx, info.end_idx do
      local e = items[i]
      local str = ""
      if e.valid == 1 then
        local fname = ""
        if e.bufnr > 0 then
          fname = vim.fn.bufname(e.bufnr)
          local is_git = fname:match "%.git//(%x%x%x%x%x%x%x)" or fname:match "%.git/([a-f0-9]+)"
          if fname == "" then
            fname = "[No Name]"
          elseif is_git then
            fname = is_git
          else
            fname = vim.fn.fnamemodify(fname, ":~:.")
          end
          if #fname <= _qftf_limit then
            fname = _fname_fmt1:format(fname)
          else
            fname = _fname_fmt2:format(fname:sub(1 - _qftf_limit))
          end
        end
        local lnum = e.lnum > 99999 and -1 or e.lnum
        local col = e.col > 999 and -1 or e.col
        local qtype = e.type == "" and "" or " " .. e.type:sub(1, 1):upper()
        str = _valid_fmt:format(fname, lnum, col, qtype, e.text)
      end
      table.insert(ret, str)
    end
    return ret
  end

  vim.o.qftf = "{info -> v:lua.qftf(info)}"
end

---@param defaults QFBookmarkConfig
---@param user_opts QFBookmarkConfig
---@return QFBookmarkConfig
local function merge_settings(defaults, user_opts)
  local user_keymaps = user_opts.keymaps or {}
  local disable_all = user_keymaps.disable_all == true
  if not disable_all then
    return vim.tbl_deep_extend("force", defaults, user_opts)
  end
  local new_defaults = vim.deepcopy(defaults)
  for section, _ in pairs(new_defaults.keymaps) do
    if section ~= "disable_all" then
      new_defaults.keymaps[section] = {}
    end
  end
  local final = vim.deepcopy(user_opts)
  final = vim.tbl_deep_extend("force", new_defaults, final)
  final.keymaps.disable_all = true
  return final
end

---@return QFBookmarkConfig
function M.update_settings(user_opts)
  user_opts = user_opts or {}
  M.defaults = merge_settings(M.defaults, user_opts)

  if M.defaults.window.quickfix.theme.enabled then
    make_qftf(M.defaults.window)

    -- Setup highlights and autocmds for qf buffer coloring
    if M.defaults.window.quickfix.theme.highlight then
      require("qfbookmark.qftf_highlight").setup()
    end
  end

  return M.defaults
end

---@param opts QFBookmarkConfig
function M.init(opts)
  local PathUtil = require "qfbookmark.path.utils"
  if not PathUtil.is_dir(opts.save_dir) then
    PathUtil.create_dir(opts.save_dir)
  end

  require("qfbookmark.mappings").setup()
end

return M
