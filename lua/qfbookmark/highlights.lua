---@type QFBookHighlight[]
local colors = {
  -- +-----------------------------------------------------------------------------+
  -- |                                  PREVIEWER                                  |
  -- +-----------------------------------------------------------------------------+

  PreviewFloatBorder = { fg = { higroup = { fromTo = "FloatBorder", attr = "fg" } } },
  PreviewCursorline = { bg = { higroup = { fromTo = "type", attr = "fg" }, tint = { amount = -0.8 } } },
  PreviewFloatCursorLineNr = {
    fg = { higroup = { fromTo = "NormalFloat", attr = "bg" } },
    bg = {
      higroup = { fromTo = "type", attr = "fg" },
      tint = { amount = 0.5 },
    },
    bold = true,
  },
  PreviewFloatTitle = { fg = { higroup = { fromTo = "FloatTitle", attr = "fg" }, tint = { amount = 0.5 } } },
  PreviewFloatCursor = {
    fg = {
      higroup = { fromTo = "Function", attr = "fg" },
      darken = { fromTo = "Normal", attr = "bg", amount = 0.5 },
    },
    bg = { higroup = { fromTo = "NormalFloat", attr = "bg" } },
  },
  PreviewFooter = {
    fg = {
      higroup = { fromTo = "Function", attr = "fg" },
      tint = { amount = 0.5 },
    },
  },

  NormalFloat = {
    fg = { higroup = { fromTo = "Directory", attr = "fg" } },
    bg = { higroup = { fromTo = "Normal", attr = "bg" } },
  },
  FloatTitle = { fg = { higroup = { fromTo = "FloatTitle", attr = "fg" }, tint = { amount = 0.5 } } },
  FloatBorder = { fg = { higroup = { fromTo = "FloatBorder", attr = "fg" } } },
  FloatFooter = { fg = { higroup = { fromTo = "FloatTitle", attr = "fg" } } },
  FloatCursorLine = {
    fg = {
      higroup = { fromTo = "Directory", attr = "fg" },
      tint = { amount = 0.1 },
    },
    bg = {
      higroup = { fromTo = "FloatBorder", attr = "fg" },
      tint = { amount = -0.1 },
    },
    bold = false,
  },

  -- +-----------------------------------------------------------------------------+
  -- |                   ENTRY HIGHLIGHT GROUPS FOR MARK HARPOON                   |
  -- +-----------------------------------------------------------------------------+

  -- index number " N "
  EntryIdx = { fg = { higroup = { fromTo = "Comment", attr = "fg" } } },
  -- path on the header line
  EntryPath = { fg = { higroup = { fromTo = "Directory", attr = "fg" } }, bold = true },
  -- current-file indicator "●"
  EntryCurrentFile = { fg = { higroup = { fromTo = "String", attr = "fg" } }, bold = true },
  -- lnum portion ":92" on the detail line
  EntryLnum = { fg = { higroup = { fromTo = "Comment", attr = "fg" }, tint = { amount = 0.05 } } },
  -- directory value in save footer (cyan-ish)
  EntryDirectory = { fg = { higroup = { fromTo = "Special", attr = "fg" } } },

  EntrySelectTo = { bg = { higroup = { fromTo = "Include", attr = "fg" }, tint = { amount = -0.6 } } },

  -- badge: MARK
  BadgeMark = {
    fg = { higroup = { fromTo = "Function", attr = "fg" } },
    bold = true,
  },
  -- badge: FIX
  BadgeFix = {
    fg = { higroup = { fromTo = "DiagnosticError", attr = "fg" } },
    bold = true,
  },
  -- badge: NOTE
  BadgeNote = {
    fg = { higroup = { fromTo = "String", attr = "fg" }, tint = { amount = 0.5 } },
    bold = true,
  },
  -- badge: DEBUG
  BadgeDebug = {
    fg = { higroup = { fromTo = "DiagnosticWarn", attr = "fg" } },
    bold = true,
  },

  -- Preview text on the detail line
  EntryDetail = { fg = { higroup = { fromTo = "Comment", attr = "fg" }, tint = { amount = 0.7 } } },

  EntryNote = { fg = { higroup = { fromTo = "String", attr = "fg" }, tint = { amount = 0.3 } } },

  -- function name context "ƒ fn_name" on the detail line (purple)
  EntryFnName = { fg = { higroup = { fromTo = "Function", attr = "fg" }, tint = { amount = -0.2 } } },

  -- class/struct/impl symbol kind (orange-ish, from type highlight)
  EntrySymbolType = { fg = { higroup = { fromTo = "Type", attr = "fg" }, tint = { amount = -0.1 } }, italic = true },

  -- +-----------------------------------------------------------------------------+
  -- |                        SELECTED ENTRY IN MARK POPUP                         |
  -- +-----------------------------------------------------------------------------+

  EntrySelected = { bg = { higroup = { fromTo = "DiagnosticOk", attr = "fg" }, tint = { amount = -0.8 } } },
  -- EntrySelectedPath = {
  --   fg = { higroup = { fromTo = "DiagnosticOk", attr = "fg" } },
  --   bold = true,
  -- },
  EntrySelectedCheck = {
    fg = { higroup = { fromTo = "DiagnosticOk", attr = "fg" } },
    bg = {
      higroup = { fromTo = "DiagnosticOk", attr = "fg" },
      tint = { amount = -0.8 },
    },
    bold = true,
  },

  EntryUnselectedCheck = { fg = { higroup = { fromTo = "Comment", attr = "fg" }, tint = { amount = -0.05 } } },

  -- Checkbox when the cursor is on the entry (background follows cursorline)
  EntrySelectedCheckCursor = {
    fg = { higroup = { fromTo = "DiagnosticOk", attr = "fg" } },
    bg = {
      higroup = { fromTo = "FloatBorder", attr = "fg" },
      tint = { amount = -0.1 },
    },
    bold = true,
  },
  EntryUnselectedCheckCursor = {
    fg = { higroup = { fromTo = "Comment", attr = "fg" }, tint = { amount = -0.1 } },
    bg = {
      higroup = { fromTo = "FloatBorder", attr = "fg" },
      tint = { amount = -0.1 },
    },
  },

  -- +-----------------------------------------------------------------------------+
  -- |                                 NOTEEXTMARK                                 |
  -- +-----------------------------------------------------------------------------+

  NoteExtmarkMark = {
    fg = {
      higroup = { fromTo = "Function", attr = "fg" },
      darken = { fromTo = "Normal", attr = "bg", amount = 0.4 },
    },
  },
  NoteExtmarkFix = {
    fg = {
      higroup = { fromTo = "DiagnosticError", attr = "fg" },
      darken = { fromTo = "Normal", attr = "bg", amount = 0.4 },
    },
  },
  NoteExtmarkDebug = {
    fg = {
      higroup = { fromTo = "DiagnosticWarn", attr = "fg" },
      darken = { fromTo = "Normal", attr = "bg", amount = 0.4 },
    },
  },
  NoteExtmarkNoteEx = {
    fg = { higroup = { fromTo = "String", attr = "fg" }, tint = { amount = 0.1 } },
  },
  NoteExtmarkNote = {
    fg = {
      higroup = { fromTo = "DiagnosticOk", attr = "fg" },
      darken = { fromTo = "Normal", attr = "bg", amount = 0.4 },
    },
    bg = {
      higroup = { fromTo = "Normal", attr = "bg" },
      tint = { amount = 0.25 },
    },
  },

  -- +-----------------------------------------------------------------------------+
  -- |                                   BUFFER                                    |
  -- +-----------------------------------------------------------------------------+

  EntryFlag = {
    fg = {
      higroup = { fromTo = "type", attr = "fg" },
      tint = { amount = 0.4 },
    },
  },
  EntryModifiedFlag = {
    fg = {
      higroup = { fromTo = "DiagnosticError", attr = "fg" },
      tint = { amount = 0.05 },
    },
    italic = true,
  },
  EntryHiddenFlag = {
    fg = {
      higroup = { fromTo = "comment", attr = "fg" },
      tint = { amount = -0.1 },
    },
    italic = true,
  },
}

---@param hex_str string
local hex_to_rgb = function(hex_str)
  local hex = "[abcdef0-9][abcdef0-9]"
  local pat = "^#(" .. hex .. ")(" .. hex .. ")(" .. hex .. ")$"

  if hex_str == "NONE" or not hex_str then
    hex_str = "#000000" -- create base hex
  end

  hex_str = string.lower(hex_str)
  assert(string.find(hex_str, pat) ~= nil, "hex_to_rgb: invalid hex_str: " .. tostring(hex_str))

  local red, green, blue = string.match(hex_str, pat)
  return { tonumber(red, 16), tonumber(green, 16), tonumber(blue, 16) }
end

---@param opts vim.api.keyset.get_highlight?
---@return { fg:string?, bg:string?, sp:string? }
local function get_hl_as_hex(opts, ns)
  ns, opts = ns or 0, opts or {}
  opts.link = opts.link ~= nil and opts.link or false
  local hl = vim.api.nvim_get_hl(ns, opts)
  return {
    fg = hl.fg and ("#%06x"):format(hl.fg) or nil,
    bg = hl.bg and ("#%06x"):format(hl.bg) or nil,
    sp = hl.sp and ("#%06x"):format(hl.sp) or nil,
  }
end

local function clamp(val)
  return math.max(0, math.min(255, math.floor(val + 0.5)))
end

---@param fg string hex foreground color
---@param bg string hex background color
---@param alpha number 0.0 – 1.0
---@return string blended hex color
local function blend(fg, bg, alpha)
  assert(type(fg) == "string", "blend: 'fg' must be a hex string, got: " .. type(fg))
  assert(type(bg) == "string", "blend: 'bg' must be a hex string, got: " .. type(bg))
  assert(type(alpha) == "number", "blend: 'alpha' must be a number, got: " .. type(alpha))
  alpha = math.max(0.0, math.min(1.0, alpha))
  local f = hex_to_rgb(fg)
  local b = hex_to_rgb(bg)
  return string.format(
    "#%02x%02x%02x",
    clamp(alpha * f[1] + (1 - alpha) * b[1]),
    clamp(alpha * f[2] + (1 - alpha) * b[2]),
    clamp(alpha * f[3] + (1 - alpha) * b[3])
  )
end

--- Blend a color toward a background (legacy alias for M.blend).
---@param hex string hex source color
---@param amount number 0.0 – 1.0
---@param bg string hex background color
local function darken(hex, amount, bg)
  assert(type(hex) == "string", "darken: 'hex' must be a hex string, got: " .. type(hex))
  assert(type(bg) == "string", "darken: 'bg' must be a hex string, got: " .. type(bg))
  assert(type(amount) == "number", "darken: 'amount' must be a number, got: " .. type(amount))
  return blend(hex, bg, math.abs(amount))
end

--- Adjust brightness by a signed percentage.
---   percent < 0 → darken  (e.g. -0.2 = 20% darker)
---   percent > 0 → brighten (e.g.  0.2 = 20% brighter)
---@param color string hex color
---@param percent number signed float
local function tint(color, percent)
  assert(type(color) == "string", "tint: 'color' must be a hex string, got: " .. type(color))
  assert(type(percent) == "number", "tint: 'percent' must be a number, got: " .. type(percent))
  local r = tonumber(color:sub(2, 3), 16)
  local g = tonumber(color:sub(4, 5), 16)
  local b = tonumber(color:sub(6, 7), 16)
  if not r or not g or not b then
    print(
      string.format(
        "tint: could not parse color '%s'.\n" .. "  Expected format: #rrggbb (e.g. #ff0000)\n" .. "  Returning 'NONE'.",
        color
      ),
      "Highlight: tint"
    )
    return "NONE"
  end
  return string.format("#%02x%02x%02x", clamp(r * (1 + percent)), clamp(g * (1 + percent)), clamp(b * (1 + percent)))
end

---@param name string
---@return table <string>
local function h(name)
  return get_hl_as_hex { name = name }
end

---@param opts QFBookHighlightCfg
---@return string
local function get_col(opts)
  local color, color_edit, color_base

  if opts.higroup.attr == "fg" then
    color_base = h(opts.higroup.fromTo).fg
  end
  if opts.higroup.attr == "bg" then
    color_base = h(opts.higroup.fromTo).bg
  end

  -- Darken handle
  if opts.darken then
    color_edit = opts.darken
    if color_edit then
      color = darken(color_base, color_edit.amount, h(color_edit.fromTo).bg)
    end
  end

  -- Tint handle
  if opts.tint then
    color_edit = opts.tint
    if color_edit then
      color = tint(color_base, color_edit.amount)
    end
  end

  if color then
    return color
  end

  return color_base
end

---@param prefix string
return function(prefix)
  for k, col in pairs(colors) do
    local hl_name = prefix .. k
    local opts_hi = {}

    if col.fg then
      opts_hi["fg"] = get_col(col.fg)
    end
    if col.bg then
      opts_hi["bg"] = get_col(col.bg)
    end
    if col.bold then
      opts_hi["bold"] = col.bold
    end

    if col.italic then
      opts_hi["italic"] = col.italic
    end

    vim.api.nvim_set_hl(0, hl_name, opts_hi)
  end
end
