local Config = require("qfbookmark.config").defaults

local QfbookmarkUtils = require "qfbookmark.utils"
local QfbookmarkTreesitter = require "qfbookmark.treesitter"
local QfbookmarkPaths = require "qfbookmark.path"
local QfbookmarkPathUtils = require "qfbookmark.path.utils"
local QfbookmarkMarkUtils = require "qfbookmark.mark.utils"
local QfbookmarkMarkSign = require "qfbookmark.mark.sign"
local QfbookmarkMarkExtmark = require "qfbookmark.mark.extmark"

local M = {
  note_namespace = "qfbookmark_note_namespace",
  note_signs_namespace = "qfbookmark_annotations_signs",
  note_extmark = "qfbookmark_note_extmark",

  mark_extmark = "qfbookmark_mark_extmark",
  dropdown_extmark = "qfbookmark_dropdown_extmark",
}

-- whether range signs (sign column filled from start_line to end_line) are
-- currently shown. toggle with m.toggle_range_signs().
local range_signs_enabled = true

-- tracks which extmark ids we've already warned about, so we don't spam
-- bufnr:extmark_id -> true
local warned = {}
local atth_extmark_key = {}

---@type integer ms timestamp of last branch check (for debounce)
local last_check = 0

---@type integer minimum ms between branch checks
local CHECK_INTERVAL = 1500

---@param bufnr integer
---@param key integer
local function warn_key(bufnr, key)
  return string.format("%d:%d", bufnr, key)
end

local function attach_key(bufnr, key)
  return string.format("%d:%d", bufnr, key)
end

M.dirty = false

function M.mark_dirty()
  M.dirty = true
end

---@type uv.uv_timer_t?
M.timer = assert(vim.uv.new_timer())

---@param key integer
---@param category QFBookMarkMode
---@return QFbookBufferMarkEntry|nil
function M.get_meta(key, category)
  local qf = require "qfbookmark.qf"
  local mark_lists = qf.get_buffers()

  if not mark_lists[category] or not mark_lists[category][key] then
    return nil
  end

  return mark_lists[category][key]
end

---@return boolean
function M.range_signs_enabled()
  return range_signs_enabled
end

---@param bufnr integer
---@param sign_ids integer[]
local function clear_range_signs(bufnr, sign_ids)
  local ns_signs = QfbookmarkMarkUtils.register_namespace(M.note_signs_namespace)
  for _, id in ipairs(sign_ids or {}) do
    QfbookmarkMarkExtmark.del_extmark(bufnr, ns_signs, id)
  end
end

---@param key integer
---@param category QFBookMarkMode
---@param bufnr integer
---@param lnum integer
local function insert_sign_or_extmark(key, category, bufnr, lnum)
  if category == "NOTE" then
    local meta = M.get_meta(key, category)
    if not meta then
      return
    end

    local opts = {
      start_line = meta.start_line,
      end_line = meta.end_line,
      bufnr = meta.bufnr,
    }

    clear_range_signs(bufnr, meta.sign_ids)

    local __annon_meta = M.create_annotation(meta.sign_category, meta.note, opts)
    if not __annon_meta then
      return
    end

    meta.id = __annon_meta.extmark_id
    meta.sign_ids = __annon_meta.sign_ids
  else
    -- insert sign like mark, debug, etc
    QfbookmarkMarkSign.insert_sign(key, category, bufnr, lnum)
  end
end

---Toggle whether range signs (sign column filled across the whole range)
---are shown. Re-renders all existing annotations immediately.
---@param value? boolean  explicit value; omit to flip the current state
function M.toggle_range_signs(value)
  value = value or false
  range_signs_enabled = not value and not range_signs_enabled or value

  local ns = QfbookmarkMarkUtils.register_namespace(M.note_namespace)
  local ns_signs = QfbookmarkMarkUtils.register_namespace(M.note_signs_namespace)

  local qf = require "qfbookmark.qf"
  local mark_lists = qf.get_buffers()

  for category, marks in pairs(mark_lists) do
    if category == "NOTE" then
      for _, m in pairs(marks) do
        clear_range_signs(m.bufnr, m.sign_ids)

        m.sign_ids = {}

        if range_signs_enabled then
          local range = QfbookmarkMarkExtmark.get_annotation_range(m.bufnr, ns, m.id)
          local keyword_def = QfbookmarkMarkUtils.get_keyword_def(m.sign_category)

          if range and keyword_def then
            m.sign_ids = QfbookmarkMarkExtmark.render_range_signs(
              m.bufnr,
              range_signs_enabled,
              ns_signs,
              range.start_row + 1,
              range.end_row + 1,
              keyword_def.hl_group
            )
          end
        end
      end
    end
  end

  QfbookmarkUtils.info(string.format("range signs %s", range_signs_enabled and "enabled" or "disabled"))
end

---@param mark_lists QFBookmarkBufferMark
---@param s_opts { bufnr?: integer, key?: integer, no_key?: boolean }
---@return { id: integer, key: integer, category: QFBookMarkMode, extmarkspec: QFBookSpec, bufnr?: integer}
function M.is_current_line_got_mark(mark_lists, s_opts)
  local bufnr = s_opts.bufnr or vim.api.nvim_get_current_buf()
  local no_key = s_opts.no_key or false

  if vim.tbl_isempty(mark_lists) then
    return {}
  end

  local extmark, sign, has_extmark, has_valid_sign

  if no_key then
    local line_opts = QfbookmarkUtils.get_line_pos_col_buffer()

    sign = QfbookmarkMarkSign.get_sign_at_line(bufnr, line_opts.line)

    local ns = QfbookmarkMarkUtils.register_namespace(M.note_namespace)
    extmark = QfbookmarkMarkExtmark.get_extmark_at_line(bufnr, ns, line_opts.line)[1]

    has_valid_sign = sign and sign.group == Config.sign_group
    has_extmark = extmark ~= nil
  end

  for category, _ in pairs(mark_lists) do
    local mode_marks = mark_lists[category]
    for key, x in pairs(mode_marks) do
      local opts
      local keyword_def = QfbookmarkMarkUtils.get_keyword_def(category)
      if has_valid_sign then
        if tonumber(x.line) == tonumber(sign.lnum) and sign.group == Config.sign_group then
          opts = {
            id = x.id,
            key = x.key,
            category = category,
            extmarkspec = keyword_def,
            bufnr = mark_lists[category][key].bufnr,
          }
          return opts
        end
      elseif has_extmark then
        if tonumber(x.line) == tonumber(extmark.lnum) then
          opts = {
            id = x.id,
            key = x.key,
            category = category,
            extmarkspec = keyword_def,
            bufnr = mark_lists[category][key].bufnr,
          }
          return opts
        end
      else
        goto continue
      end
    end
    ::continue::
  end
  return {}
end

---@param bufnr integer| nil
function M.clear_buf_attach_and_warnings_extmark(bufnr)
  local function __nil(_tbl, spec)
    if not spec then
      return
    end

    for k in pairs(_tbl) do
      if k:match("^" .. spec .. ":") then
        _tbl[k] = nil
      end
    end
  end

  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    __nil(warned, bufnr)
  end
end

---Scan all annotations in a buffer, notify (once) on newly-orphaned ones.
---@param bufnr integer
---@param key integer
function M.scan_buffer(bufnr, key)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local ns = QfbookmarkMarkUtils.register_namespace(M.note_namespace)

  for _, ann in ipairs(M.list_annotations(bufnr, key)) do
    local wk = warn_key(bufnr, ann.id)
    local orphaned = QfbookmarkMarkExtmark.is_orphaned(bufnr, ns, ann.id)

    if orphaned and not warned[wk] then
      warned[wk] = true
      QfbookmarkUtils.warn(
        string.format(
          "annotation '%s' (%s) might be orphaned — its source range seems to have been deleted",
          ann.text ~= "" and ann.text or ann.category,
          ann.category
        )
      )
    elseif not orphaned and warned[wk] then
      -- range came back (e.g. undo) — allow re-warning if it disappears again
      warned[wk] = nil
    end
  end
end

---@param mark_lists QFBookmarkBufferMark
---@param force_refresh boolean
---@param bufnr? integer
local function refresh_mark(mark_lists, force_refresh, bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not QfbookmarkUtils.exclude_default_filetype_dan_buftype(bufnr) then
    return
  end

  if force_refresh and not M.timer:is_active() then
    -- Stop the timer if it's running (safe to call even if not running)
    M.timer:stop()

    M.timer:start(
      Config.extmarks.throttle,
      0,
      vim.schedule_wrap(function()
        M.update_mark_sign(mark_lists, bufnr)
      end)
    )
  end
end

---@param mark_lists QFbookBufferMarkEntry[]
local function __save_marks(mark_lists, target_path)
  if not QfbookmarkPathUtils.is_file(target_path) then
    QfbookmarkPathUtils.create_file(target_path)
  end

  QfbookmarkUtils.save_table_to_file(mark_lists, target_path)
end

---@param mark_lists QFbookBufferMarkEntry[]
function M.save_marks(mark_lists, target_path, is_global)
  is_global = is_global or false

  target_path = target_path or QfbookmarkPaths.get_target_file_path(is_global)

  -- Remove saved file when there are no marks left
  if #mark_lists == 0 then
    if QfbookmarkPathUtils.is_file(target_path) then
      vim.fn.delete(target_path)
    end
    return
  end

  __save_marks(mark_lists, target_path)
end

--- Save current in-memory marks to the previously active branch file,
--- then load marks for the newly active branch file, and refresh
--- extmarks in all currently open buffers.
---@param mark_lists QFbookBufferMarkEntry[]
---@param new_root string
---@param new_branch string
function M.switch_to(mark_lists, new_root, new_branch)
  local current_root = QfbookmarkPaths.path_opts.current_root
  local current_branch = QfbookmarkPaths.path_opts.current_branch
  local dirty = M.dirty

  -- Nothing changed — skip
  if new_root == current_root and new_branch == current_branch then
    return
  end

  -- Save current marks before switching, but only if something changed
  if dirty and current_root and current_branch then
    local old_path = QfbookmarkPaths.resolve_marks_path(current_root, current_branch)
    M.save_marks(mark_lists, old_path)
    M.dirty = false
  end

  local new_path = QfbookmarkPaths.resolve_marks_path(new_root, new_branch, false, true)

  local is_empty = false

  -- Offer to seed from a sensible default when no marks exist yet for this branch.
  -- Most useful right after creating a new feature branch
  if vim.fn.filereadable(new_path) == 0 and new_root then
    is_empty = true

    -- return
    --   unplan: do I need this?
    --   local seed_choice = Config.get.something --> retrieve the user's preferred choice from the config
    --   if seed_choice then
    --     local choice = vim.fn.confirm(
    --       string.format("No marks found for branch '%s'. Copy marks from previous branch?", new_branch or "?"),
    --       "&Yes\n&No, start empty",
    --       2
    --     )
    --     if choice == 1 and current_root and current_branch then
    --       local old_path = QfbookmarkPaths.resolve_marks_path(current_root, current_branch)
    --       ...copy
    --     end
    --   end
  end

  QfbookmarkPaths.path_opts.current_root = new_root
  QfbookmarkPaths.path_opts.current_branch = new_branch

  local qf = require "qfbookmark.qf"

  -- Refresh extmarks/signs in every currently loaded buffer:
  -- 1. Clean up the sign first
  qf.__remove_all_signs()

  -- 2. Load a new sign
  qf.load_mark_lists(nil, true)
  qf.__resync_setup()

  local label = new_branch and (" · " .. new_branch) or ""
  local msg = "Marks reloaded: " .. label
  if is_empty then
    msg = msg .. " is empty.\nTry adding some marks first."
    QfbookmarkUtils.warn(msg)
    return
  end
  QfbookmarkUtils.info(msg)
end

--- Check whether the active branch/root has changed since last check,
--- and switch marks accordingly. Debounced via CHECK_INTERVAL.
---@param mark_lists QFbookBufferMarkEntry[]
---@param force boolean  skip debounce, always check
function M.check_and_reload(mark_lists, force)
  local now = vim.uv.now()

  if not force and (now - last_check) < CHECK_INTERVAL then
    return
  end

  last_check = now

  local _, root, branch = QfbookmarkPaths.resolve_active_marks_file()
  if root and branch then
    M.switch_to(mark_lists, root, branch)
  end
end

---@param mark_lists QFBookmarkBufferMark
---@param category QFBookMarkMode
---@param key integer
---@param bufnr? integer
---@param lnum integer
---@param col integer
---@param line_text string
---@param ann_opts? {extmark_id: integer, note: string[], sign_ids: integer[], original_span: integer, start_line: integer, end_line: integer, sign_category: string}
---@param inserted_at? integer
---@return QFBookmarkBufferMark | nil
local function register_mark(mark_lists, category, key, bufnr, lnum, col, line_text, ann_opts, inserted_at)
  ann_opts = ann_opts or {}
  M.mark_dirty()

  bufnr = bufnr or vim.api.nvim_get_current_buf()
  inserted_at = inserted_at or os.time()

  local filename = vim.api.nvim_buf_get_name(bufnr)

  -- Validate line before registering
  if QfbookmarkMarkUtils.is_not_valid_line_and_col(bufnr, lnum, col) then
    return nil
  end

  if not mark_lists[category] then
    mark_lists[category] = {}
  end

  if not mark_lists[category][key] then
    local cwd = vim.uv.cwd()
    local filename_trim = filename:gsub(cwd .. "/", "")
    local harpoon = string.format("%s:%s:%s:%s", filename_trim, lnum, col, category)

    mark_lists[category][key] = {
      bufnr = bufnr,
      filename = filename,
      line = ann_opts.start_line and ann_opts.start_line or lnum,
      col = col,
      text = QfbookmarkUtils.strip_whitespace(line_text),
      harpoon = harpoon,
      category = category,
      sign_category = ann_opts.sign_category and ann_opts.sign_category or category,
      fn_name = QfbookmarkTreesitter.resolve_symbol(bufnr, lnum, col or 0),
      inserted_at = inserted_at, -- Unix timestamp (seconds); consistent across sessions
      id = ann_opts.extmark_id and ann_opts.extmark_id or key,
      key = key,
      note = ann_opts.note,
      start_line = ann_opts.start_line,
      end_line = ann_opts.end_line,
      sign_ids = ann_opts.sign_ids,
      original_span = ann_opts.original_span,
    }
  end

  return mark_lists
end

---@param bufnr integer
---@param key integer
---@param id integer
---@param text string[]
function M.set_text(bufnr, key, id, category, text)
  local meta = M.get_meta(key, category)
  if not meta then
    return
  end

  meta.note = text

  local keyword_def = QfbookmarkMarkUtils.get_keyword_def(meta.sign_category)
  if not keyword_def then
    return
  end

  local ns = QfbookmarkMarkUtils.register_namespace(M.note_namespace)
  local range = QfbookmarkMarkExtmark.get_annotation_range(bufnr, ns, id)
  if not range then
    return
  end

  -- re-set the extmark in place to refresh virt_text (extmarks are immutable-ish:
  -- easiest correct way to "update" virt_text is to set_extmark again with same id)
  QfbookmarkMarkExtmark.set_extmark(bufnr, ns, range.start_row, range.start_col, {
    id = meta.id,
    end_row = range.end_row,
    end_col = range.end_col,
    end_right_gravity = false,
    right_gravity = true,
    virt_text = QfbookmarkMarkUtils.render_virt_text(keyword_def, text),
    virt_text_pos = "eol",
  })

  -- range may have grown/shrunk since creation; re-render signs to match
  clear_range_signs(bufnr, meta.sign_ids)

  local ns_signs = QfbookmarkMarkUtils.register_namespace(M.note_signs_namespace)
  meta.sign_ids = QfbookmarkMarkExtmark.render_range_signs(
    bufnr,
    range_signs_enabled,
    ns_signs,
    range.start_row + 1,
    range.end_row + 1,
    keyword_def.hl_group
  )
end

---@param key integer
---@param mark_lists? QFBookmarkBufferMark
---@param category QFBookMarkMode | {category: QFBookMarkMode, sign_category: string}
---@param bufnr? integer
---@param line_opts? { pos: integer, line: integer, col: integer, text: string, from_qf?: boolean}
local function __place_next_mark_annontation(mark_lists, category, key, bufnr, line_opts)
  category = category or "NOTE"

  mark_lists = mark_lists or require("qfbookmark.qf").get_buffers()
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  line_opts = line_opts or QfbookmarkUtils.get_line_pos_col_buffer()

  local annon_opts = {}

  local _category

  if type(category) == "table" then
    annon_opts.category = category.sign_category
    _category = category.category
  else
    _category = category
  end

  local QfbookmarkUI = require "qfbookmark.ui"

  -- +-----------------------------------------------------------------------------+
  -- | Edit extmark note                                                           |
  -- +-----------------------------------------------------------------------------+

  local meta = M.get_meta(key, _category)
  if meta then
    local row = vim.api.nvim_win_get_cursor(0)[1] - 1
    local keyword_def = QfbookmarkMarkUtils.get_keyword_def(meta.sign_category)

    for _, ann in ipairs(M.list_annotations(bufnr, key)) do
      if ann.range and row >= ann.range.start_row and row <= ann.range.end_row then
        QfbookmarkUI.place_mark_annotation(
          meta.sign_category,
          function(text)
            M.set_text(bufnr, key, ann.id, _category, text)
          end,
          nil,
          { load_chunk = true, chunk = meta },
          {
            anchor = line_opts.from_qf and "editor" or "cursor",
            keyword_def = keyword_def,
            bufnr = bufnr,
            is_edit = true,
            start_line = meta.start_line,
            end_line = meta.end_line,
          }
        )
        return
      end
    end
    return
  end

  -- +-----------------------------------------------------------------------------+
  -- | Adding extmark for note                                                     |
  -- +-----------------------------------------------------------------------------+

  if line_opts.from_qf then
    annon_opts.start_line = line_opts.line
    annon_opts.end_line = line_opts.line
  else
    local start_line, end_line = QfbookmarkMarkUtils.visual_range()
    annon_opts.start_line = start_line
    annon_opts.end_line = end_line
  end

  if bufnr then
    annon_opts.bufnr = bufnr
  end
  local function after_category(__category)
    local keyword_def = QfbookmarkMarkUtils.get_keyword_def(__category)
    QfbookmarkUI.place_mark_annotation(
      __category,
      function(text)
        local ann_opts = M.create_annotation(__category, text, annon_opts)
        if not ann_opts then
          return
        end

        if not line_opts.col or not line_opts.line then
          line_opts = QfbookmarkUtils.get_line_pos_col_buffer()
        end

        local lnum = line_opts.line
        local col = line_opts.col
        local line_text = line_opts.text

        local atch_key = attach_key(bufnr, key)
        if not atth_extmark_key[atch_key] then
          atth_extmark_key[atch_key] = true
        end

        register_mark(mark_lists, _category, key, bufnr, lnum, col, line_text, ann_opts)

        if line_opts.from_qf then
          local qf = require "qfbookmark.qf"
          local _mark_lists = qf.get_buffers()
          local had_marks = false

          if mark_lists then
            for _, marks in pairs(_mark_lists) do
              if next(marks) ~= nil then
                had_marks = true
                break
              end
            end
          end

          if not had_marks then
            for _, mark in pairs(mark_lists[category]) do
              qf.load_mark_lists({ mark }, true)
            end
          end

          require("qfbookmark.qf").__update_mark_lists()

          if not had_marks then
            qf.open_mark_harpoon_window()
          end
        end
      end,
      nil,
      nil,
      {
        anchor = line_opts.from_qf and "editor" or "cursor",
        keyword_def = keyword_def,
        bufnr = bufnr,
        start_line = annon_opts.start_line,
        end_line = annon_opts.end_line,
      }
    )
  end

  if annon_opts.category then
    after_category(annon_opts.category) -- skip dropdown, e.g. mapped shortcut like add_extmark_to("fix")
  else
    QfbookmarkUI.select_category(after_category)
  end
end

---@param mark_lists QFBookmarkBufferMark
---@param category QFBookMarkMode | {category: QFBookMarkMode, sign_category: string}
---@param key integer
---@param bufnr? integer
---@param line_opts? { pos: integer, line: integer, col: integer, text: string, from_qf?: boolean}
function M.place_next_mark(mark_lists, category, key, bufnr, line_opts)
  line_opts = line_opts or {}
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local _category

  if type(category) == "table" then
    _category = category.category
  else
    _category = category
  end

  if not line_opts.col or not line_opts.line then
    line_opts = QfbookmarkUtils.get_line_pos_col_buffer()
  end

  local lnum = line_opts.line
  local col = line_opts.col
  local line_text = line_opts.text

  if _category ~= "NOTE" then
    insert_sign_or_extmark(key, _category, bufnr, lnum)
    register_mark(mark_lists, _category, key, bufnr, lnum, col, line_text)
    require("qfbookmark.qf").__update_mark_lists()
  else
    __place_next_mark_annontation(mark_lists, category, key, bufnr, line_opts)
  end
end

---@param mark_lists QFBookmarkBufferMark
---@param bufnr integer
function M.update_mark_sign(mark_lists, bufnr)
  if vim.tbl_isempty(mark_lists) then
    return
  end

  if not QfbookmarkUtils.is_valid(bufnr) then
    return
  end

  local ns = QfbookmarkMarkUtils.register_namespace(M.note_namespace)

  local filename = vim.api.nvim_buf_get_name(bufnr)

  for category, mark in pairs(mark_lists) do
    for _, m in pairs(mark) do
      -- Do not normalize the path, as it may no longer match Fugitive's tracked path
      if m.filename ~= filename then
        goto continue
      end

      if QfbookmarkMarkUtils.is_not_valid_line_and_col(bufnr, m.line, m.col) then
        M.delete_mark(mark_lists, category, m.key, m.id, bufnr)
      else
        if m.category ~= "NOTE" then
          local sign = QfbookmarkMarkSign.get_sign_at_line(bufnr, m.line)
          if vim.tbl_isempty(sign) then
            insert_sign_or_extmark(m.key, category, bufnr, m.line)
          end
        else
          local extmark = QfbookmarkMarkExtmark.get_extmark_at_line(bufnr, ns, m.line)[1]
          local atch_key = attach_key(bufnr, m.key)
          if not extmark and not atth_extmark_key[atch_key] then
            insert_sign_or_extmark(m.key, category, bufnr, m.line)
            atth_extmark_key[atch_key] = true
          end
        end
      end
      ::continue::
    end
  end
end

---Open a preview popup for an annotation's context before sending/copying.
---Lets the user cycle templates live and pick send vs copy-only.
---@param bufnr integer
---@param key integer
---@param opts? QFbookPreviewOpts
function M.preview(bufnr, key, opts)
  opts = opts or {}

  if not opts.ns then
    opts.ns = QfbookmarkMarkUtils.register_namespace(M.note_namespace)
  end

  local QfbookmarkUI = require "qfbookmark.ui"
  QfbookmarkUI.preview_mark_annotation(bufnr, key, opts)
end

---Create an extmark annotation over a (possibly multi-line) range.
---@param category string  -- key into Config.extmarks.keywords
---@param note string[] -- short note text shown inline
---@param opts? { bufnr?: integer, start_line?: integer, end_line?: integer }
---@return {extmark_id: integer, note: string[], sign_ids: integer[], original_span: integer, start_line: integer, end_line: integer, sign_category: string}|nil  { bufnr, extmark_id, category, text }
function M.create_annotation(category, note, opts)
  opts = opts or {}

  local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()

  local start_line, end_line
  if opts.start_line and opts.end_line then
    start_line, end_line = opts.start_line, opts.end_line
  else
    start_line, end_line = QfbookmarkMarkUtils.visual_range()
  end

  start_line, end_line = QfbookmarkMarkUtils.clamp_range(bufnr, start_line, end_line)

  local keyword_def = QfbookmarkMarkUtils.get_keyword_def(category)

  if not keyword_def then
    QfbookmarkUtils.warn(string.format("unknown extmark category '%s'", tostring(category)))
    return nil
  end

  local ns = QfbookmarkMarkUtils.register_namespace(M.note_namespace)

  local id = QfbookmarkMarkExtmark.set_extmark(bufnr, ns, start_line - 1, 0, {
    end_row = end_line - 1,
    end_col = 0,
    end_right_gravity = false, -- new lines appended right at end_row get absorbed into the range
    right_gravity = true,
    virt_text = QfbookmarkMarkUtils.render_virt_text(keyword_def, note),
    virt_text_pos = "eol",
    priority = 2,
  })

  if not id then
    return nil
  end

  local ns_signs = QfbookmarkMarkUtils.register_namespace(M.note_signs_namespace)

  local sign_ids = QfbookmarkMarkExtmark.render_range_signs(
    bufnr,
    range_signs_enabled,
    ns_signs,
    start_line,
    end_line,
    keyword_def.hl_group
  )

  return {
    extmark_id = id,
    note = note,
    sign_category = category,
    sign_ids = sign_ids,
    start_line = start_line,
    end_line = end_line,
    -- original span, used to disambiguate "legit single-line annotation"
    -- from "range collapsed because its lines got deleted"
    original_span = end_line - start_line,
  }
end

---@param bufnr integer
---@param key integer
---@param id integer
---@param category string
function M.delete_annotation(bufnr, key, id, category)
  local meta = M.get_meta(key, category)
  if meta then
    clear_range_signs(bufnr, meta.sign_ids)
  end

  local ns = QfbookmarkMarkUtils.register_namespace(M.note_namespace)
  QfbookmarkMarkExtmark.delete_extmark(id, ns, bufnr)
end

---@class QFbookBufferMarkEntryWithRange : QFbookBufferMarkEntry
---@field range QFBookmarkExtermarkAnnotationRange

---List all live annotations in a buffer (does not filter orphaned ones).
---@param bufnr integer
---@param key integer
---@return QFbookBufferMarkEntryWithRange[]
function M.list_annotations(bufnr, key)
  local ns = QfbookmarkMarkUtils.register_namespace(M.note_namespace)
  local marks = QfbookmarkMarkExtmark.get_buf_extmark(bufnr, ns)

  local out = {}

  for _, m in ipairs(marks) do
    local id = m[1]
    local meta = M.get_meta(key, "NOTE")
    if meta then
      table.insert(
        out,
        vim.tbl_extend("force", {}, meta, {
          range = QfbookmarkMarkExtmark.get_annotation_range(bufnr, ns, id),
        })
      )
    end
  end

  return out
end

--- Remove a mark entry and its associated sign.
--- Returns `true` when the mark exists and is successfully removed from
--- the internal storage; otherwise returns `false`.
---@param mark_lists QFBookmarkBufferMark
---@param category QFBookMarkMode
---@param key integer
---@param id integer
---@param bufnr integer
---@param clear_buffer? boolean
---@return boolean
function M.delete_mark(mark_lists, category, key, id, bufnr, clear_buffer)
  clear_buffer = clear_buffer or false
  M.mark_dirty()

  if category == "NOTE" then
    M.delete_annotation(bufnr, key, id, category)
    if clear_buffer then
      QfbookmarkMarkExtmark.clear_extmarks(M.note_namespace, bufnr)
      local atch_key = attach_key(bufnr, key)
      if atth_extmark_key[atch_key] then
        atth_extmark_key[atch_key] = nil
      end
    end
  else
    QfbookmarkMarkSign.delete_sign(id, bufnr)
  end

  mark_lists[category][key] = nil
  return true
end

--- Add a new mark at the current cursor position.
--- Uses the current buffer, line, and column to create a mark and store
--- it through `place_next_mark()`.
---@param mark_lists QFBookmarkBufferMark
---@param category QFBookMarkMode | {category: QFBookMarkMode, sign_category: string}
function M.add_mark(mark_lists, category)
  local line_opts = QfbookmarkUtils.get_line_pos_col_buffer()

  local bufnr = vim.api.nvim_get_current_buf()
  local key = tonumber(line_opts.line .. bufnr)
  if not key then
    QfbookmarkUtils.warn "Unexpected error while getting line number"
    return nil
  end

  M.place_next_mark(mark_lists, category, key, bufnr, line_opts)
end

---@param bufnr integer
---@param line integer
---@param col integer
---@param line_text string
---@param category QFBookMarkMode
function M.add_mark_at(bufnr, line, col, line_text, category)
  local allow_category = { "MARK", "DEBUG", "FIX", "NOTE" }
  assert(
    vim.tbl_contains(allow_category, category),
    string.format("invalid category '%s', expected one of: %s", category, table.concat(allow_category, ", "))
  )

  M.mark_dirty()

  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local key = tonumber(line .. bufnr)

  if not key then
    QfbookmarkUtils.warn "Unexpected error while getting line number"
    return
  end

  local qf = require "qfbookmark.qf"
  local mark_lists = qf.get_buffers()

  -- Check whether any marks exist before registering a new one.
  -- If this is the first mark, refresh the mark list so the new
  -- entry is displayed immediately.
  local had_marks = false

  if mark_lists then
    for _, marks in pairs(mark_lists) do
      if next(marks) ~= nil then
        had_marks = true
        break
      end
    end
  end

  if not mark_lists[category] then
    mark_lists[category] = {}
  end

  if mark_lists[category][key] then
    return false
  end

  local from_qf = vim.bo.buftype == "quickfix"

  M.place_next_mark(mark_lists, category, key, bufnr, { col = col, line = line, text = line_text, from_qf = from_qf })

  if not had_marks then
    for _, mark in pairs(mark_lists[category]) do
      qf.load_mark_lists({ mark }, true)
    end
  end

  return true
end

local autocmds_set_once = false

---@param mark_lists QFBookmarkBufferMark
---@param force_set? boolean
function M.setup_mark_autocmds(mark_lists, force_set)
  force_set = force_set or false

  if autocmds_set_once and not force_set then
    return
  end

  autocmds_set_once = true

  QfbookmarkUtils.clear_autocmd_group(Config.sign_group .. "RefreshMark")
  local refresh_group = QfbookmarkUtils.create_augroup_name "RefreshMark"

  vim.api.nvim_create_autocmd("BufReadPost", {
    group = refresh_group,
    pattern = "*",
    callback = function(ctx)
      refresh_mark(mark_lists, true, ctx.buf)
    end,
    desc = "QFBookmark: refresh marks after read post buffer",
  })

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = refresh_group,
    pattern = "*",
    callback = function(ctx)
      refresh_mark(mark_lists, true, ctx.buf)
    end,
    desc = "QFBookmark: refresh marks after text changed or edited",
  })

  vim.api.nvim_create_autocmd("BufEnter", {
    group = refresh_group,
    pattern = "*",
    callback = function(ctx)
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(ctx.buf) or not vim.api.nvim_buf_is_loaded(ctx.buf) then
          return
        end

        local filename = vim.api.nvim_buf_get_name(ctx.buf)
        local ns = QfbookmarkMarkUtils.register_namespace(M.note_namespace)

        for _, mark in pairs(mark_lists) do
          for _, m in pairs(mark) do
            if m.filename ~= filename then
              goto continue
            end
            M.scan_buffer(ctx.buf, m.key)

            -- Clear the cached attachment key if the extmark no longer exists.
            local atch_key = attach_key(ctx.buf, m.key)
            local extmark = QfbookmarkMarkExtmark.get_extmark_at_line(ctx.buf, ns, m.line)[1]
            if not extmark then
              if atth_extmark_key[atch_key] then
                atth_extmark_key[atch_key] = nil
              end
            end
          end
          ::continue::
        end
      end)
    end,
    desc = "QFBookmark: warn about orphaned annotations on buffer enter",
  })

  vim.api.nvim_create_autocmd("BufDelete", {
    group = refresh_group,
    pattern = "*",
    callback = function(ctx)
      M.clear_buf_attach_and_warnings_extmark(ctx.buf)
    end,
    desc = "QFBookmark: clear buffer warnings and extmark state",
  })
end

return M
