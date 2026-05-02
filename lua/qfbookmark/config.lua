local M = {}

---@type QFBookmarkConfig
M.defaults = {
  save_dir = vim.fn.stdpath "data" .. "/qfbookmark",
  picker = "default", -- fzf-lua
  extmarks = {
    enabled = true,
    priority = 20,
    excluded = {
      buftypes = {},
      filetypes = {},
    },
    builtin_marks = false,
    cyclic_navigation = true,
    refresh_interval = 250,
    throttle = 200,
    keywords = {
      MARK = { icon = "📌", hl_group = "QFBookMark", alt = " -> " },
      FIX = { icon = "🔧", hl_group = "QFBookFix", alt = " -> " },
      DEBUG = { icon = "🚧", hl_group = "QFBookDebug", alt = " -> " },
      NOTE = { icon = "📝", hl_group = "QFBookNote", alt = " -> " },
    },
  },
  persistence = {
    builtin_marks = false,
    force_write_shada = false,
  },
  window = {
    notify = { mark = true, plugin = true },
    theme = { enabled = true, maxheight = 10 },
    layout = {
      enabled = true,
      copen = "belowright copen",
      lopen = "belowright lopen",
    },
    actions = {
      auto_center = true,
      auto_unfold = true,
    },
    note = {
      open_cmd = "botright vsplit",
      size_split = 12,
      size_vsplit = 50,
      filetype = "org", -- Ex: "orgmode" "norg", "markdown", "text"
      file_ext = "org", -- Ex: "org" "norg" "md" "txt"
    },
    popup = {
      winhighlight = "Normal:NormalFloat,FloatBorder:FloatBorder",
      higroup_title = "Function",
      quickfix = true,
      icons = {
        box_message = " ", -- " ",
      },
    },
  },
  keymaps = {
    disable_all = false,

    actions = { -- General actions
      delete_mark = "dm",
      delete_mark_buffer = "dM",
      delete_item = "dd",
      delete_item_all = "<Leader>mC",
      rename_title = "<Leader>mR",

      save_or_load = "<Leader>qy",
      mark_win_open = "<Leader>qo",

      mark = "<Leader>qq",
      fix = "<Leader>qf",
      debug = "<Leader>qd",
      note = "<Leader>qN",

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
        next = "<Leader>qn",
        prev = "<Leader>qp",
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
      copyline = { enabled = true, toggle = "<Leader>nl" },
      cmdline_strings = {
        enabled = true,
        commands = {
          {
            key = "<Leader>qrl",
            cmd = "cdo %s/status//gi | update",
            desc = "Descriptions about cdo..",
            mode = "n", -- "i", "x", "s", "n", "o"
          },
        },
      },
    },
  },
}

---@param defaults QFBookmarkConfig
---@param user_opts QFBookmarkConfig
---@return QFBookmarkConfig
local function merge_settings(defaults, user_opts)
  local user_keymaps = user_opts.keymaps or {}
  local disable_all = user_keymaps.disable_all == true

  -- do a normal merge unless `disable_all` is set to true
  if not disable_all then
    return vim.tbl_deep_extend("force", defaults, user_opts)
  end

  local new_defaults = vim.deepcopy(defaults)

  for section, _ in pairs(new_defaults.keymaps) do
    if section ~= "disable_all" then
      -- clear all default keymaps for each section except "disable_all"
      new_defaults.keymaps[section] = {}
    end
  end

  local final = vim.deepcopy(user_opts)
  final = vim.tbl_deep_extend("force", new_defaults, final)
  final.keymaps.disable_all = true -- set it back to true
  return final
end

---@return QFBookmarkConfig
function M.update_settings(user_opts)
  user_opts = user_opts or {}
  M.defaults = merge_settings(M.defaults, user_opts)

  -- Makes the quickfix and local list prettier. Borrowed from nvim-bqf.
  -- function _G.qftf(info)
  --   local items
  --   local ret = {}
  --   if info.quickfix == 1 then
  --     items = fn.getqflist({ id = info.id, items = 0 }).items
  --   else
  --     items = fn.getloclist(info.winid, { id = info.id, items = 0 }).items
  --   end
  --   local limit = 60
  --   local fname_fmt1, fname_fmt2 = "%-" .. limit .. "s", "…%." .. (limit - 1) .. "s"
  --   local valid_fmt = "%s │%5d:%-3d│%s %s"
  --   for i = info.start_idx, info.end_idx do
  --     local e = items[i]
  --     local fname = ""
  --     local str
  --     if e.valid == 1 then
  --       if e.bufnr > 0 then
  --         fname = fn.bufname(e.bufnr)
  --         if fname == "" then
  --           fname = "[No Name]"
  --         else
  --           fname = fname:gsub("^" .. vim.env.HOME, "~")
  --         end
  --         if #fname <= limit then
  --           fname = fname_fmt1:format(fname)
  --         else
  --           fname = fname_fmt2:format(fname:sub(1 - limit))
  --         end
  --       end
  --       local lnum = e.lnum > 99999 and -1 or e.lnum
  --       local col = e.col > 999 and -1 or e.col
  --       local qtype = e.type == "" and "" or " " .. e.type:sub(1, 1):upper()
  --       str = valid_fmt:format(fname, lnum, col, qtype, e.text)
  --     else
  --       str = e.text
  --     end
  --     table.insert(ret, str)
  --   end
  --   return ret
  -- end

  -- local function addjustWindowHWQf(maxheight)
  --   maxheight = maxheight or 7
  --   local l = 1
  --   local n_lines = 0
  --   local w_width = fn.winwidth(vim.api.nvim_get_current_win())
  --
  --   for i = l, fn.line "$" do
  --     local l_len = fn.strlen(fn.getline(l)) + 0.0
  --     local line_width = l_len / w_width
  --     n_lines = n_lines + fn.float2nr(fn.ceil(line_width))
  --     i = i + 1
  --   end
  --   --
  --   local height = math.min(n_lines, maxheight)
  --   vim.cmd(fmt("%swincmd _", height + 1))
  -- end

  -- if settings.theme_list.set.enabled then
  --   vim.o.qftf = "{info -> v:lua.qftf(info)}" -- uncomment this line if needed..
  -- end

  -- if settings.theme_list.auto_height.enabled then
  --   local augroup = vim.api.nvim_create_augroup("QFSiletThemeQF", { clear = true })
  --   vim.api.nvim_create_autocmd("FileType", {
  --     pattern = { "qf" },
  --     group = augroup,
  --     callback = function()
  --       addjustWindowHWQf(settings.theme_list.maxheight)
  --     end,
  --   })
  -- end

  -- if settings.marks.enabled then
  --   require("qfsilet.marks").setup(settings.marks.refresh_interval)
  -- end
  --
  -- for i_ext, _ in pairs(Visual.extmarks) do
  --   for i_ext_set, _ in pairs(settings.extmarks) do
  --     if i_ext == i_ext_set then
  --       Visual.extmarks[i_ext] = settings.extmarks[i_ext_set]
  --     end
  --   end
  -- end

  -- setup_highlight_groups()

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
