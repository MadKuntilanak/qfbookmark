---@type QFBookHighlight[]
local colors = {
  PreviewFooter = {
    fg = {
      higroup = { fromTo = "Function", attr = "fg" },
      darken = { fromTo = "Normal", attr = "bg", amount = 0.5 },
    },
    bg = { higroup = { fromTo = "NormalFloat", attr = "bg" } },
  },
  PreviewCursorline = {
    bg = {
      higroup = { fromTo = "Error", attr = "fg" },
      darken = { fromTo = "Normal", attr = "bg", amount = 0.1 },
    },
  },
  PreviewFloatTitle = {
    fg = { higroup = { fromTo = "FloatTitle", attr = "fg" } },
    bg = { higroup = { fromTo = "FloatTitle", attr = "bg" } },
    bold = true,
  },
  PreviewFloatCursor = {
    fg = {
      higroup = { fromTo = "Function", attr = "fg" },
      darken = { fromTo = "Normal", attr = "bg", amount = 0.5 },
    },
    bg = { higroup = { fromTo = "NormalFloat", attr = "bg" } },
  },
  SaveFloatNormal = {
    fg = { higroup = { fromTo = "Function", attr = "fg" } },
    bg = { higroup = { fromTo = "NormalFloat", attr = "bg" } },
  },
  FloatNormal = {
    fg = {
      higroup = { fromTo = "Error", attr = "fg" },
      darken = { fromTo = "Normal", attr = "bg", amount = 0.4 },
    },
    bg = { higroup = { fromTo = "Normal", attr = "bg" } },
  },
  FloatTitle = {
    fg = {
      higroup = { fromTo = "FloatBorder", attr = "fg" },
      darken = { fromTo = "FloatBorder", attr = "fg", amount = 4 },
    },
    bold = true,
  },
  FloatFooter = {
    fg = {
      higroup = { fromTo = "FloatBorder", attr = "fg" },
      darken = { fromTo = "FloatBorder", attr = "fg", amount = 4 },
    },
    bold = false,
  },
  FloatBorder = { fg = { higroup = { fromTo = "FloatBorder", attr = "fg" } } },
  FloatCursorLine = {
    fg = {
      higroup = { fromTo = "Error", attr = "fg" },
      darken = { fromTo = "Keyword", attr = "bg", amount = 0.7 },
    },
    bold = true,
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

---@param opts vim.api.keyset.get_highlight
---@return vim.api.keyset.get_hl_info
local function get_hl_as_hex(opts, ns)
  ns, opts = ns or 0, opts or {}
  opts.link = opts.link ~= nil and opts.link or false
  local hl = vim.api.nvim_get_hl(ns, opts)
  hl.fg = hl.fg and ("#%06x"):format(hl.fg)
  hl.bg = hl.bg and ("#%06x"):format(hl.bg)
  hl.sp = hl.sp and ("#%06x"):format(hl.sp)
  return hl
end

---@param fg string
---@param bg string
---@param alpha number number between 0 and 1. 0 results in bg, 1 results in fg
local function blend(fg, bg, alpha)
  bg = hex_to_rgb(bg)
  fg = hex_to_rgb(fg)

  local blendChannel = function(i)
    local ret = (alpha * fg[i] + ((1 - alpha) * bg[i]))
    return math.floor(math.min(math.max(0, ret), 255) + 0.5)
  end

  return string.format("#%02X%02X%02X", blendChannel(1), blendChannel(2), blendChannel(3))
end

---@param hex string
---@param amount integer
---@param bg string
local function darken(hex, amount, bg)
  return blend(hex, bg, math.abs(amount))
end

---@param name string
---@return table <string>
local function h(name)
  return get_hl_as_hex { name = name }
end

---@param prefix string
return function(prefix)
  ---@param opts ColCfg
  ---@return string
  local function get_col(opts)
    local col, c, basecol

    if opts.higroup.attr == "fg" then
      basecol = h(opts.higroup.fromTo).fg
    end
    if opts.higroup.attr == "bg" then
      basecol = h(opts.higroup.fromTo).bg
    end

    if opts.darken then
      c = opts.darken
      if c then
        col = darken(basecol, c.amount, h(c.fromTo).bg)
      end
    end

    if opts.tint then
      c = opts.tint
      if c then
        col = blend(basecol, h(c.fromTo).bg, c.amount)
      end
    end

    if not col then
      return basecol
    end

    return col
  end

  for k, col in pairs(colors) do
    local hi_footer = prefix .. k
    local existing = vim.api.nvim_get_hl(0, { name = hi_footer, link = false })

    if existing and (existing.fg or existing.bg or existing.sp) then
      goto continue
    end

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

    vim.api.nvim_set_hl(0, hi_footer, opts_hi)
  end

  ::continue::
end
