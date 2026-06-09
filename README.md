# QFbookmark

[**qfbookmark**](https://github.com/MadKuntilanak/qfbookmark) was built around my own coding workflow. I often found myself placing marks in different files and later forgetting the context around them especially which function, method, or code section the mark referred to. This plugin extends the idea of traditional marks by combining them with quickfix lists, notes, and contextual navigation, making it easier to revisit and organize important locations across a project.


> **Note**

> WORK IN PROGRESS 🚀
>
> This plugin is actively developed and some features may not be fully polished yet. You may occasionally encounter bugs, breaking changes, or incomplete integrations as new functionality is added.
>
> Please report issues if you find any problems. 

`qfbookmark` combines:

- File bookmarks
- Quickfix management
- Location list management
- Notes attached to files
- Extmark visualization
- [**Trouble**](https://github.com/folke/trouble.nvim) and [**Grug Far**](https://github.com/MagicDuck/grug-far.nvim) integration
 

The goal is to provide a single workflow for navigating, annotating, organizing, and revisiting code locations.

---

## Features

### Bookmark Categories

Create categorized bookmarks:

- MARK
- FIX
- DEBUG
- NOTE

Each category can be highlighted independently through extmarks.

### Quickfix & Location List

- Add entries to quickfix
- Add entries to location list
- Navigate entries quickly
- Manage list history
- Custom quickfix formatting (`qftf`)

### Notes

Attach notes to files.

Supports:

- Local notes
- Global notes

Configurable filetype and extension.

### Extmarks

Optional virtual indicators directly inside buffers.

Supports:

- Custom highlights
- Cyclic navigation
- Refresh throttling
- Filetype exclusion
- Buftype exclusion

### Persistence

Save and restore:

- Bookmarks
- Notes
- Metadata

### Integrations

- Trouble.nvim
- GrugFar
- Copyline

---

## Installation

### lazy.nvim

```lua
{
    "MadKuntilanak/qfbookmark",
    opts = {},
}
```

### packer.nvim

```lua
use {
  "MadKuntilanak/qfbookmark",
  config = function()
    require("qfbookmark").setup()
  end,
}
```

---

## Configuration

<details>
<summary>Default configuration</summary>

```lua
require("qfbookmark").setup {
  save_dir = vim.fn.stdpath "data" .. "/qfbookmark",

  picker = "default",

  extmarks = {
    enabled = true,
    priority = 20,
    builtin_marks = false,
    cyclic_navigation = true,

    excluded = {
      buftypes = {},
      filetypes = {},
    },
  },

  persistence = {
    builtin_marks = false,
    force_write_shada = false,
  },

  window = {
    notify = {
      mark = true,
      plugin = true,
    },

    layout = {
      enabled = true,
    },

    actions = {
      auto_center = true,
      auto_unfold = true,
    },

    note = {
      open_cmd = "botright vsplit",
      filetype = "org",
      file_ext = "org",
    },
  },
}
```
</details>



<details>
<summary>Keymaps</summary>

```lua

  keymaps = {
    disable_all = false,

    actions = {
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
      cmdline_strings = {
        enabled = false,
        commands = {},
      },
    },
  },

```
</details>

---

## Default Bookmark Types

| Type | Purpose |
|--------|----------|
| MARK | General bookmark |
| FIX | Something that needs fixing |
| DEBUG | Debugging location |
| NOTE | Note location |

---

## Default Keymaps

### Bookmark Actions

| Key | Action |
|------|----------|
| qq | Add MARK |
| qf | Add FIX |
| qd | Add DEBUG |
| qn | Add NOTE |
| dm | Delete bookmark |
| dM | Delete all bookmarks in current buffer |

### Quickfix

| Key | Action |
|------|----------|
| qj | Toggle quickfix |
| tt | Add item to quickfix |

### Location List

| Key | Action |
|------|----------|
| ql | Toggle location list |
| ty | Add item to location list |

### Notes

| Key | Action |
|------|----------|
| fn | Toggle local note |
| fN | Toggle global note |

### Navigation

| Key | Action |
|------|----------|
| gj | Next bookmark |
| gk | Previous bookmark |
| gl | Next list history |
| gh | Previous list history |

---

## Integrations

### Trouble.nvim

```lua
integrations = {
  trouble = {
    enabled = true,
  },
}
```

### GrugFar

```lua
integrations = {
  grugfar = {
    enabled = true,
  },
}
```

### Copyline

```lua
integrations = {
  copyline = {
    enabled = true,
  },
}
```

---

## Disable All Default Keymaps

```lua
require("qfbookmark").setup {
  keymaps = {
    disable_all = true,
  },
}
```

Then define only the mappings you want.

---

## Why qfbookmark?

Many plugins solve only one problem:

- bookmarks
- quickfix
- notes
- marks
- navigation

`qfbookmark` combines them into a single workflow centered around Neovim's quickfix ecosystem.

---

## License

MIT
