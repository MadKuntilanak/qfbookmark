local api = vim.api

-- ---------------------------------------------------------------------------
-- Spec yang dipakai berulang (sebelumnya di-copy-paste berkali-kali)
-- ---------------------------------------------------------------------------

local FLOAT_BORDER_FG = { higroup = { fromTo = "FloatBorder", attr = "fg" } }
local FLOAT_TITLE_FG = { higroup = { fromTo = "FloatTitle", attr = "fg" } }
local FLOAT_TITLE_BG = { higroup = { fromTo = "FloatTitle", attr = "bg" } }
local FLOAT_BG = { higroup = { fromTo = "NormalFloat", attr = "bg" } }

local OK_FG = { higroup = { fromTo = "DiagnosticOk", attr = "fg" } }
local OK_BG = { higroup = { fromTo = "DiagnosticOk", attr = "fg" }, tint = { amount = -0.8 } }

local CURSORLINE_BG = {
  higroup = { fromTo = "FloatBorder", attr = "fg" },
  darken = { fromTo = "NormalFloat", attr = "bg", amount = -0.7 },
}

---@type table<string, QFBookHighlight>
local colors = {
  -- +-----------------------------------------------------------------------+
  -- |                               PREVIEWER                               |
  -- +-----------------------------------------------------------------------+

  PreviewFloatBorder = { fg = FLOAT_BORDER_FG },
  PreviewCursorline = {
    bg = {
      higroup = { fromTo = "Type", attr = "fg" },
      darken = { fromTo = "NormalFloat", attr = "bg", amount = -0.15 },
    },
  },
  PreviewFloatCursorLineNr = {
    fg = FLOAT_BG,
    bg = {
      higroup = { fromTo = "Type", attr = "fg" },
      tint = { amount = 0.5 },
    },
    bold = true,
  },
  PreviewFloatTitle = { fg = FLOAT_TITLE_FG, bg = FLOAT_TITLE_BG, bold = true },
  PreviewFloatCursor = {
    fg = {
      higroup = { fromTo = "Function", attr = "fg" },
      darken = { fromTo = "Normal", attr = "bg", amount = 0.5 },
    },
    bg = FLOAT_BG,
  },
  PreviewFooter = {
    fg = {
      higroup = { fromTo = "Function", attr = "fg" },
      tint = { amount = 0.5 },
    },
  },

  NormalFloat = {
    fg = { higroup = { fromTo = "Directory", attr = "fg" } },
    bg = FLOAT_BG,
  },
  FloatTitle = { fg = FLOAT_TITLE_FG, bg = FLOAT_TITLE_BG, bold = true },
  FloatBorder = { fg = FLOAT_BORDER_FG },
  FloatFooter = { fg = { higroup = { fromTo = "FloatFooter", attr = "fg" } } },
  FloatCursorLine = { bg = CURSORLINE_BG },

  -- +-----------------------------------------------------------------------+
  -- |                 ENTRY HIGHLIGHT GROUPS FOR MARK HARPOON               |
  -- +-----------------------------------------------------------------------+

  -- index number " N "
  EntryIdx = {
    fg = { higroup = { fromTo = "LineNr", attr = "fg" }, tint = { amount = 0.8 } },
  },
  -- path on the header line
  EntryPath = { fg = { higroup = { fromTo = "Directory", attr = "fg" } }, bold = true },
  -- basename more bright
  EntryBasename = {
    fg = { higroup = { fromTo = "Directory", attr = "fg" }, tint = { amount = 0.3 } },
    bold = true,
  },
  -- current-file indicator "●"
  EntryCurrentFile = { fg = { higroup = { fromTo = "String", attr = "fg" } }, bold = true },
  -- lnum portion ":92" on the detail line
  EntryLnum = { fg = { higroup = { fromTo = "Type", attr = "fg" }, tint = { amount = -0.2 } } },
  -- directory value in save footer
  EntryDirectory = { fg = { higroup = { fromTo = "Special", attr = "fg" } } },

  EntrySelectTo = { bg = { higroup = { fromTo = "Include", attr = "fg" }, tint = { amount = -0.6 } } },

  BadgeMark = { fg = { higroup = { fromTo = "Function", attr = "fg" } }, bold = true },
  BadgeFix = { fg = { higroup = { fromTo = "DiagnosticError", attr = "fg" } }, bold = true },
  BadgeNote = {
    fg = { higroup = { fromTo = "String", attr = "fg" }, tint = { amount = 0.5 } },
    bold = true,
  },
  BadgeDebug = { fg = { higroup = { fromTo = "DiagnosticWarn", attr = "fg" } }, bold = true },

  -- preview text on the detail line
  EntryDetail = { fg = { higroup = { fromTo = "Comment", attr = "fg" }, tint = { amount = 0.05 } } },
  EntryNote = { fg = { higroup = { fromTo = "String", attr = "fg" }, tint = { amount = 0.3 } } },
  -- function name context on the detail line
  EntryFnName = { fg = { higroup = { fromTo = "Function", attr = "fg" }, tint = { amount = 0.05 } }
 },
  -- class/struct/impl symbol kind
  EntrySymbolType = {
    fg = { higroup = { fromTo = "Type", attr = "fg" }, tint = { amount = 0.05 } },
    italic = true,
  },

  -- +-----------------------------------------------------------------------+
  -- |                      SELECTED ENTRY IN MARK POPUP                     |
  -- +-----------------------------------------------------------------------+

  EntrySelected = { bg = OK_BG },
  EntrySelectedPath = { fg = OK_FG, bold = true },
  EntrySelectedCheck = { fg = OK_FG, bg = OK_BG, bold = true },
  -- cursor on entry: sama persis dengan EntrySelectedCheck, jadi pakai spec yang sama
  EntrySelectedCheckCursor = { fg = OK_FG, bg = OK_BG, bold = true },

  EntryUnselectedCheck = { fg = { higroup = { fromTo = "Comment", attr = "fg" }, tint = { amount = -0.15 } } },
  EntryUnselectedCheckCursor = {
    fg = { higroup = { fromTo = "Comment", attr = "fg" }, tint = { amount = -0.1 } },
    bg = CURSORLINE_BG,
  },

  -- +-----------------------------------------------------------------------+
  -- |                              NOTEEXTMARK                              |
  -- +-----------------------------------------------------------------------+

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

  -- +-----------------------------------------------------------------------+
  -- |                                 BUFFER                                |
  -- +-----------------------------------------------------------------------+

  EntryFlag = {
    fg = { higroup = { fromTo = "DiagnosticWarn", attr = "fg" }, tint = { amount = 0.4 } },
  },
  EntryModifiedFlag = {
    fg = { higroup = { fromTo = "DiagnosticError", attr = "fg" }, tint = { amount = 0.05 } },
    italic = true,
  },
  EntryHiddenFlag = {
    fg = { higroup = { fromTo = "Comment", attr = "fg" }, tint = { amount = -0.1 } },
    italic = true,
  },
}

-- ---------------------------------------------------------------------------
-- Color helpers (semua nil-safe: input tidak valid -> return nil, bukan crash)
-- ---------------------------------------------------------------------------

local HEX_PAT = "^#(%x%x)(%x%x)(%x%x)$" -- %x sudah case-insensitive

---@param hex string?
---@return integer? r, integer? g, integer? b
local function hex_to_rgb(hex)
  if type(hex) ~= "string" then
    return nil
  end
  local r, g, b = hex:match(HEX_PAT)
  if not r then
    return nil
  end
  return tonumber(r, 16), tonumber(g, 16), tonumber(b, 16)
end

local function clamp(val)
  return math.max(0, math.min(255, math.floor(val + 0.5)))
end

local function to_hex(r, g, b)
  return string.format("#%02x%02x%02x", clamp(r), clamp(g), clamp(b))
end

--- Campur `fgc` ke atas `bgc` dengan opacity `alpha` (0..1).
---@param fgc string?
---@param bgc string?
---@param alpha number
---@return string?
local function blend(fgc, bgc, alpha)
  local fr, fg, fb = hex_to_rgb(fgc)
  local br, bg, bb = hex_to_rgb(bgc)
  if not (fr and br) or type(alpha) ~= "number" then
    return nil
  end
  alpha = math.max(0, math.min(1, alpha))
  local inv = 1 - alpha
  return to_hex(alpha * fr + inv * br, alpha * fg + inv * bg, alpha * fb + inv * bb)
end

--- Campur `hex` ke `bg`. NOTE: tanda `amount` diabaikan (math.abs), jadi
--- -0.15 dan 0.15 hasilnya sama. Dipertahankan demi kompatibilitas config.
---@param hex string?
---@param amount number
---@param bg string?
---@return string?
local function darken(hex, amount, bg)
  if type(amount) ~= "number" then
    return nil
  end
  return blend(hex, bg, math.abs(amount))
end

--- Ubah brightness: percent < 0 gelap, percent > 0 terang (perkalian per channel).
---@param color string?
---@param percent number
---@return string?
local function tint(color, percent)
  local r, g, b = hex_to_rgb(color)
  if not r or type(percent) ~= "number" then
    return nil
  end
  local k = 1 + percent
  return to_hex(r * k, g * k, b * k)
end

-- ---------------------------------------------------------------------------
-- Highlight lookup (di-cache per pemanggilan apply)
-- ---------------------------------------------------------------------------

---@type table<string, { fg: string?, bg: string? }>
local cache = {}

---@param name string
---@return { fg: string?, bg: string? }
local function h(name)
  local c = cache[name]
  if c then
    return c
  end
  -- pcall: group yang tidak ada / versi nvim lama tidak boleh membuat crash
  local ok, hl = pcall(api.nvim_get_hl, 0, { name = name, link = false })
  if not ok or type(hl) ~= "table" then
    hl = {}
  end
  c = {
    fg = hl.fg and ("#%06x"):format(hl.fg) or nil,
    bg = hl.bg and ("#%06x"):format(hl.bg) or nil,
  }
  cache[name] = c
  return c
end

--- Warna target untuk darken, dengan fallback bertingkat:
--- group -> Normal -> default berdasarkan 'background'.
---@param edit { fromTo: string, attr: string? }
---@return string
local function resolve_target(edit)
  local attr = edit.attr or "bg"
  local dark = vim.o.background ~= "light"
  local default
  if attr == "bg" then
    default = dark and "#000000" or "#ffffff"
  else
    default = dark and "#ffffff" or "#000000"
  end
  return h(edit.fromTo)[attr] or h("Normal")[attr] or default
end

---@param spec QFBookHighlightCfg
---@return string?
local function get_col(spec)
  local hg = spec.higroup
  if not hg then
    return nil
  end

  local color = h(hg.fromTo)[hg.attr]
  -- darken lalu tint dirantai (sebelumnya tint menimpa hasil darken)
  if spec.darken then
    color = darken(color, spec.darken.amount, resolve_target(spec.darken)) or color
  end
  if spec.tint then
    color = tint(color, spec.tint.amount) or color
  end
  return color
end

---@param prefix string
return function(prefix)
  cache = {} -- reset supaya mengikuti colorscheme terbaru
  for name, def in pairs(colors) do
    api.nvim_set_hl(0, prefix .. name, {
      fg = def.fg and get_col(def.fg) or nil,
      bg = def.bg and get_col(def.bg) or nil,
      bold = def.bold,
      italic = def.italic,
    })
  end
end
