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
      theme = {
        enabled = true,
        limit = 50,
        highlight = true,
        maxheight = 7,
      },
      actions = {
        copen = "belowright copen",
        lopen = "belowright lopen",
        auto_center = true,
        auto_unfold = true,
        default = { auto_close = true },
        split = { auto_close = false },
        vsplit = { auto_close = false },
        tab = { auto_close = true },
      },
    },
    buffers = {
      enabled = true,
    },
    note = {
      enabled = true,
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
      enabled = true,
      anchor = "SE", -- NW/SW --- SE/NE
    },
  },
  keymaps = {
    disable_all = false,

    actions = { -- General actions
      up = { "<C-p>", "<C-k>", "k" },
      down = { "<C-n>", "<C-j>", "j" },

      default = { "o", "<CR>" },
      split = "<C-s>",
      vsplit = "<C-v>",
      tab = "<C-t>",

      scroll_preview_up = "<C-u>",
      scroll_preview_down = "<C-d>",
      scroll_preview_up_fast = "<C-b>",
      scroll_preview_down_fast = "<C-f>",

      toggle_select = "<Tab>",
      diselect_all = "D",

      next_item = "<C-n>",
      prev_item = "<C-p>",

      quit = { "q", "<Esc>", "<C-c>", "<C-q>" },

      del_item = "dd",
      del_item_all = "dM",
    },

    mark = {
      add_mark = "<Leader>qq",
      add_fix = "<Leader>qf",
      add_debug = "<Leader>qd",
      add_mark_annotation = "<Leader>qn",

      open_popup = "gl",

      save_annotation = "<C-s>",

      del_mark = "dm",
      del_mark_buffer = "dM",

      next_mark = "gn",
      prev_mark = "gp",

      move_item_down = "<a-n>",
      move_item_up = "<a-p>",

      zoom = "<C-z>",

      load_all = "<C-a>",

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
      integrations = {
        custom = { enabled = false, commands = {} },
      },
    },
    quickfix = {
      next_hist = "gl",
      prev_hist = "gh",

      rename_title = "<Localleader>qR",

      add_item_to_qf = "tt",
      add_item_to_loc = "ty",

      open_toggle_qf = "<Leader>qj",
      open_toggle_loc = "<Leader>ql",

      save_or_load = "<Leader>qy",

      layout_up = "<c-k>",
      layout_down = "<c-j>",

      integrations = {
        trouble = { enabled = true, toggle_qflist = "Q", toggle_loclist = "L" },
        grugfar = { enabled = true, toggle = "<Localleader>gg" },
        copyline = { enabled = true, toggle = "<Leader>qc" },
        custom = { enabled = false, commands = {} },
      },
    },

    buffers = {
      toggle_open = "gb",
    },

    note = {
      open_toggle_global = "<Leader>fn",
      open_toggle_local = "<Leader>fN",
      layout_rotate = "<a-=>",
    },
  },
}

-- +-----------------------------------------------------------------------------+
-- |                    QFTF: Quickfix Title Format Function                     |
-- +-----------------------------------------------------------------------------+
---@param opts QFBookmarkWindowCfg
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

    local function addjustWindowHWQf(maxheight)
      maxheight = maxheight or 7
      local l = 1
      local n_lines = 0
      local w_width = vim.fn.winwidth(vim.api.nvim_get_current_win())

      for i = l, vim.fn.line "$" do
        local l_len = vim.fn.strlen(vim.fn.getline(l)) + 0.0
        local line_width = l_len / w_width
        n_lines = n_lines + vim.fn.float2nr(vim.fn.ceil(line_width))
        i = i + 1
      end

      local height = math.min(n_lines + 3, maxheight)
      vim.cmd(string.format("%swincmd _", height + 1))
    end

    if M.defaults.window.quickfix.theme.maxheight then
      local augroup = vim.api.nvim_create_augroup("QFbookmarkQuickfixHeight", { clear = true })
      vim.api.nvim_create_autocmd("FileType", {
        pattern = { "qf" },
        group = augroup,
        callback = function()
          addjustWindowHWQf(M.defaults.window.quickfix.theme.maxheight)
        end,
      })
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

  require("qfbookmark.keymaps").setup()
  require("qfbookmark.qf").setup_autocmds()
end

return M
