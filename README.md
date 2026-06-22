# QFbookmark (WIP 🚀)

<p align="center">
  <img src="./assets/tqfbookmark.svg" alt="qfbookmark" />
</p>

[**QFBookmark**](https://github.com/MadKuntilanak/qfbookmark) is a bookmarking plugin for Neovim that combines marks, buffers, quickfix lists, and notes into a single workflow.


## Features

- Mark lines with modes: `MARK`, `FIX`, `DEBUG`, `NOTE` (Mark Annotation)
- Harpoon-style popup with preview, symbol context (function/class/struct/impl), and per-entry highlights
- Treesitter-powered symbol resolution, shows enclosing function, class, struct, impl, or table context
* Persistent marks saved to disk per project, automatically separated and restored for each Git branch or tag, with support for merging marks across branches and tags
* Quickfix and location list integration with custom formatting, supporting both project-local and global save/load workflows
- Notes per project or globally (using external filetype definitions like org, norg, md, txt, etc.)
* Built-in quickfix integrations with trouble.nvim, grug-far.nvim, and fzf-lua (enabled by default, optional to disable)
- Fast navigation across all popup menus with jump shortcuts, plus optional number-based selection (similar to Harpoon) when `allow_number = true`
- Seamless item sharing across providers (**Mark**, **Quickfix**, **Buffers**, **Note**): add entries from marks, buffers, or other lists into quickfix and other supported targets directly from popup menus, with configurable custom integrations via `integrations.custom` commands

## Showcase

![qfbookmark](./assets/qfbookmark.png)

## Requirements

- Neovim >= 0.12
- [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) (optional, for symbol context)
- [trouble](https://github.com/folke/trouble.nvim) (optional)
- [fzf-lua](https://github.com/ibhagwan/fzf-lua) (optional)
- [grug-far](https://github.com/MagicDuck/grug-far.nvim) (optional)

## Installation

**lazy.nvim**

```lua
{
  "MadKuntilanak/qfbookmark",
  event = "VeryLazy",
  opts = {},
}
```

**packer.nvim**

```lua
use {
  "MadKuntilanak/qfbookmark",
  config = function()
    require("qfbookmark").setup()
  end,
}
```

## Setup

```lua
require("qfbookmark").setup {
  -- all options shown with their defaults
}
```


---

## Configuration

<details>
<summary>Default configuration, click to expand</summary>

```lua
require("qfbookmark").setup {
  save_dir = vim.fn.stdpath "data" .. "/qfbookmark",

  -- Picker backend. "default" uses the built-in popup.
  picker = "default", --  or "fzf-lua"

  extmarks = {
    priority = 15,

    -- Exclude certain buffer or file types from showing extmarks
    excluded = {
      buftypes = {},
      filetypes = {},
    },

    throttle = 200, -- ms

    -- Mark mode definitions: icon, highlight group, and sign text
    keywords = {
      MARK = { icon = "📌", hl_group = "QFbookmarkBadgeMark" },
      FIX = { icon = "🔧", hl_group = "QFbookmarkBadgeFix" },
      DEBUG = { icon = "🚧", hl_group = "QFbookmarkBadgeDebug" },
      NOTE = { icon = "📝", hl_group = "QFbookmarkBadgeNote" },
    },
  },
  window = {
    notify = { mark = true, plugin = true },
    quickfix = {
      enabled = true,
      allow_number = true,
      theme = {
        enabled = true,
        limit = 50,
        highlight = true,
        maxheight = 7,
      },
      actions = {
        copen = "belowright copen",
        lopen = "belowright lopen",
        auto_center = true, -- center buffer on jump
        auto_unfold = true,
        default = { auto_close = true },
        split = { auto_close = false },
        vsplit = { auto_close = false },
        tab = { auto_close = true },
      },
    },
    buffers = {
      enabled = true,
      allow_number = true,
      actions = {
        win_resized = true,
      },
    },
    mark = {
      enabled = true,
      anchor = "SE", -- NW/SW --- SE/NE
      allow_number = true,
      actions = {
        win_resized = false,
      },
    },
    note = {
      -- Cursor state:
      -- The last cursor position is saved automatically.
      -- When reopening the note, the cursor will be restored
      -- to its previous location, so you don't need to scroll
      -- through long notes again.
      enabled = true,

      mode = "float", -- or "belowright split"
      wrap = true,
      anchor = "SE", -- "NW|NE|SW|SE"
      width = 0.45, -- relative size (0.1 to 1)
      height = 0.80,

      -- Syntax highlighting is not provided by this plugin,
      -- it relies on nvim built-in filetypes or external plugins :D
      filetype = "org", -- "org" | "norg" | "md" | "txt"

      -- When enabled, notes are stored in a project-local file.
      -- The target path will follow `filename` (e.g. "TODO.org") inside the current project directory.
      -- This is useful for per-project notes (e.g. TODO.org per repo/workspace).

      -- Global notes are always stored separately in `save_dir`,
      -- and are shared across all projects/workspaces.
      current_project = {
        enabled = true,
        filename = "TODO.org", -- or /path/to/mytodo.md
      },
      insert_to_note = {
        enabled = true,
        line_placeholder = "<TEXT_HERE>",
        templates = {
          notice = {
            target = "global", -- "global" | "local" | "target path"
            description = "Quick notice / reminder",
            templates = string.format(
              [[
date: %s
notice:
<TEXT_HERE>
]],
              os.date "%Y-%m-%d %H:%M"
            ),
          },

          error = {
            target = "local",
            description = "Capture an error / bug for this project",
            templates = string.format(
              [[
date: %s
error:
<TEXT_HERE>
]],
              os.date "%Y-%m-%d %H:%M"
            ),
          },

          todo = {
            target = "local",
            description = "TODO item with source reference",
            templates = function()
              return string.format(
                [[
  - [ ] error ..

    #+begin_src %s
    <TEXT_HERE>
    #+end_src

      ]],
                vim.bo.filetype
              )
            end,
          },
        },
      },
    },
  },
  keymaps = {
    -- Set to true to disable all default keymaps and define your own
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
      -- Create marks
      add_mark = "<Leader>qq",
      add_fix = "<Leader>qf",
      add_debug = "<Leader>qd",
      add_mark_annotation = "<Leader>qn",

      toggle_open = "gl",

      save_annotation = "<C-s>",

      del_mark = "dm",
      del_mark_buffer = "dM",

      next_mark = "gn",
      prev_mark = "gp",

      move_item_down = "<a-n>",
      move_item_up = "<a-p>",

      zoom = "<C-z>",

      load_all = "<C-a>",

      -- Jump directly to harpoon slot N
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
      integrations = {
        custom = { enabled = false, commands = {} },
      },
    },

    note = {
      toggle_open_global = "<Leader>fn",
      toggle_open_local = "<Leader>fN",
      layout_rotate = "<a-=>",
    },
  },
}
```
</details>

---

## Providers

<details>
<summary>Mark</summary>


#### Default Bookmark Types

| Type | Purpose |
|--------|----------|
| MARK | General bookmark |
| FIX | Something that needs fixing |
| DEBUG | Debugging location |
| NOTE | Mark Note Annotation |

#### Default Keymaps

```lua

    mark = {
      -- Create marks
      add_mark = "<Leader>qq",
      add_fix = "<Leader>qf",
      add_debug = "<Leader>qd",
      add_mark_annotation = "<Leader>qn",

      toggle_open = "gl",

      save_annotation = "<C-s>",

      del_mark = "dm",
      del_mark_buffer = "dM",

      next_mark = "gn",
      prev_mark = "gp",

      move_item_down = "<a-n>",
      move_item_up = "<a-p>",

      zoom = "<C-z>",

      load_all = "<C-a>",

      -- Jump directly to harpoon slot N
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

```

</details>

---


<details>
<summary>Quickfix</summary>


#### Default Keymaps

```lua

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

```

</details>

---

<details>
<summary>Buffers</summary>

#### Default Keymaps

```lua

    buffers = {
      toggle_open = "gb",
      integrations = {
        custom = { enabled = false, commands = {} },
      },
    },

```
</details>

---

<details>
<summary>Note</summary>

#### Default Keymaps

```lua

    note = {
      toggle_open_global = "<Leader>fn",
      toggle_open_local = "<Leader>fN",
      layout_rotate = "<a-=>",
    },

```

</details>

---


## FAQ

<details>
<summary>Why another bookmark plugin?</summary>

[**QFBookmark**](https://github.com/MadKuntilanak/qfbookmark) was built around my own coding workflow. I often found myself placing marks in different files and later forgetting the context around them especially which function, method, or code section the mark referred to. This plugin extends the idea of traditional marks by combining them with quickfix lists, notes, and contextual navigation, making it easier to revisit and organize important locations across a project.

</details>

<details>
<summary>Why 4 mark types instead of one?</summary>

The four types (MARK, FIX, DEBUG, NOTE) don't change how marks work internally — they exist purely for visual clarity. When you have many marks across multiple files, being able to tell at a glance "this is a debugging point" vs "this needs fixing" vs "this is just a reference" makes navigation significantly faster. Think of them as colored sticky notes.
</details>

<details>
<summary>Can I use only one type and ignore the rest?</summary>

Yes. All four types behave identically under the hood. You can map only `MARK` and never touch the others.
</details>

<details>
<summary>What's Mark Note Annotation different from the others?</summary>

Mark Note Annotation is the only type that supports inline annotations. You can attach text to it, which is also exposed in the mark popup and can be leveraged by external AI plugins or custom integrations for additional context.
</details>


## License

MIT
