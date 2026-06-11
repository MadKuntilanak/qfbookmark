local QfbookmarkUtils = require "qfbookmark.utils"

local M = {}

---@alias LfNextAndPrev "lprevious" | "lnext"
---@alias NavUpAndDown "k" | "j"
---@alias QFmode "open"| "only"| "cnext"| "cprev"| "lnext"| "lprev"
---@alias QfNextAndPrev "cprevious" | "cnext"
---@alias OpenMode "vsplit" | "split" | "tabnew" | "default" | "buffer" | "edit"

-- local function safe_set_cursor(win, line, col)
--   local bufnr = vim.api.nvim_win_get_buf(win)
--   local line_count = vim.api.nvim_buf_line_count(bufnr)
--
--   -- Clamp line
--   if line < 1 then
--     line = 1
--   end
--   if line > line_count then
--     line = line_count
--   end
--
--   -- Clamp col
--   local text = vim.api.nvim_buf_get_lines(bufnr, line - 1, line, false)[1] or ""
--   if col < 0 then
--     col = 0
--   end
--   if col > #text then
--     col = #text
--   end
--
--   vim.api.nvim_win_set_cursor(win, { line, col })
-- end

---@param opts {filename: string, line: integer, col: integer, text?: string, mode_open?: OpenMode, is_force_jump: boolean}
function M.jump_to(opts)
  local buf = vim.api.nvim_get_current_buf()
  local current_file = vim.api.nvim_buf_get_name(buf)

  local filename = opts.filename
  if not filename then
    return
  end

  -- normalize path
  filename = vim.fn.fnamemodify(filename, ":p")

  local mode = opts.mode_open

  -- safe open file
  if mode and mode ~= "" then
    if mode == "default" then
      mode = "edit"
    end

    local ok, _ = pcall(function()
      vim.cmd(string.format("%s %s", mode, vim.fn.fnameescape(filename)))
    end)

    if not ok then
      vim.cmd("edit " .. vim.fn.fnameescape(filename))
    end
  elseif filename ~= current_file then
    vim.cmd("edit " .. vim.fn.fnameescape(filename))
  end

  -- jump position
  if opts.line and opts.line > 0 then
    local line_count = vim.api.nvim_buf_line_count(0)
    local l = math.max(1, math.min(opts.line, line_count))
    local c = opts.col or 0

    pcall(vim.api.nvim_win_set_cursor, 0, { l, c })
  else
    local mark = vim.api.nvim_buf_get_mark(0, '"')
    local line_count = vim.api.nvim_buf_line_count(0)

    if mark[1] > 0 and mark[1] <= line_count then
      pcall(vim.api.nvim_win_set_cursor, 0, mark)
    end
  end

  -- fold safe open
  if opts.line and opts.line > 0 then
    local ok, fold_start = pcall(vim.fn.foldclosed, opts.line)
    if ok and fold_start ~= -1 then
      vim.cmd "silent! foldopen!"
    end
  end

  vim.schedule(function()
    vim.cmd "redraw"
  end)
end

local function go_first_line()
  vim.cmd "normal! gg"
end

local function go_last_line()
  vim.cmd "normal! G"
end

---@param winnr integer
---@param exclude_filetypes? table
local function find_target_win(winnr, exclude_filetypes)
  exclude_filetypes = exclude_filetypes or {}

  local candidate = vim.fn.winnr "#"
  local max_attempts = vim.fn.winnr "$"
  local attempt = 0

  while attempt < max_attempts do
    local ft = vim.fn.getwinvar(candidate, "&filetype")
    if
      candidate ~= winnr
      and not QfbookmarkUtils.is_quickfix_win(candidate)
      and not vim.tbl_contains(exclude_filetypes, ft)
    then
      return vim.fn.win_getid(candidate)
    end
    candidate = candidate - 1
    if candidate < 1 then
      candidate = vim.fn.winnr "$"
    end
    attempt = attempt + 1
  end

  -- If no suitable window found, use the first non-quickfix window
  for i = 1, vim.fn.winnr "$" do
    if i ~= winnr and not QfbookmarkUtils.is_quickfix_win(i) then
      return vim.fn.win_getid(i)
    end
  end

  return nil -- Fallback, though unlikely
end

---@param qf_mode QFmode
---@param indices integer[]
---@param open_mode OpenMode
---@param is_center boolean
---@param is_expanded boolean
---@param is_only? boolean
local function open_qf_items(qf_mode, indices, open_mode, is_center, is_expanded, is_only)
  is_center = is_center or false
  is_expanded = is_expanded or false
  is_only = is_only or false

  local current_winnr = vim.api.nvim_win_get_number(vim.api.nvim_get_current_win())
  local is_loc = QfbookmarkUtils.is_loclist_win(current_winnr)

  local target_winid = find_target_win(current_winnr)
  if not target_winid then
    return
  end

  local keep_focus = qf_mode:match "_keep$" ~= nil
  local base_cmd = keep_focus and qf_mode:gsub("_keep", "") or qf_mode

  local use_next = base_cmd:match "cnext" ~= nil or base_cmd:match "lnext" ~= nil
  local use_prev = base_cmd:match "cprev" ~= nil or base_cmd:match "lprev" ~= nil
  local use_open = not use_next and not use_prev

  local qf_open_cmd

  if use_open then
    qf_open_cmd = is_loc and "ll" or "cc"
  end

  if use_next then
    qf_open_cmd = is_loc and "lnext" or "cnext"
  end

  if use_prev then
    qf_open_cmd = is_loc and "lprev" or "cprev"
  end

  if use_next or use_prev then
    -- For next/prev, ignore multiple indices, use single
    if #indices > 1 then
      QfbookmarkUtils.warn "Visual selection not supported for next/prev commands. Using cursor position"
    end
    indices = { vim.fn.line "." }
  end

  for _, idx in ipairs(indices) do
    vim.api.nvim_set_current_win(target_winid)

    if open_mode == "vsplit" then
      vim.cmd "vertical split"
    elseif open_mode == "split" then
      vim.cmd "split"
    elseif open_mode == "tabnew" then
      vim.cmd "tabnew"
    end

    local is_failed = false

    -- Run main command
    local _, err = pcall(function()
      if use_open then
        vim.cmd(qf_open_cmd .. " " .. idx)
      else
        vim.cmd(qf_open_cmd)
      end
    end)

    if err and (string.match(err, "E42") or string.match(err, "E553")) then
      is_failed = true
    end

    if not is_failed then
      -- Force open fold
      if is_expanded then
        local qf_info = is_loc and vim.fn.getloclist(0, { idx = 0, items = 0 })
          or vim.fn.getqflist { idx = 0, items = 0 }
        local item = qf_info.items[qf_info.idx]
        if item and item.bufnr and item.lnum then
          --- Ensure current buffer matches item buffer
          if vim.api.nvim_get_current_buf() == item.bufnr then
            local fold_start = vim.fn.foldclosed(item.lnum)
            if fold_start ~= -1 then
              vim.api.nvim_win_set_cursor(0, { item.lnum, 0 })
              vim.cmd "silent! foldopen!"
            end
          end
        end
      end
      -- force to center
      if is_center then
        pcall(function()
          vim.cmd "normal! zz"
        end)
      end
    end

    -- Back to qf window
    if not is_failed and not keep_focus and is_only then
      vim.cmd "wincmd p"
    end
  end

  if open_mode then
    vim.cmd "wincmd p"
    if open_mode ~= "default" then
      vim.cmd "wincmd ="
    end
  end
end

---@param is_jump_prev boolean
---@param is_loclist? boolean
---@return QfNextAndPrev | LfNextAndPrev, NavUpAndDown
local function get_cmd_direction_and_nav_key(is_jump_prev, is_loclist)
  is_loclist = is_loclist or QfbookmarkUtils.is_loclist()

  local cmd_direction, nav_key
  if is_loclist then
    cmd_direction = is_jump_prev and "lprevious" or "lnext"
    nav_key = cmd_direction == "lnext" and "j" or "k"
  else
    cmd_direction = is_jump_prev and "cprevious" or "cnext"
    nav_key = cmd_direction == "cnext" and "j" or "k"
  end
  return cmd_direction, nav_key
end

---@param is_jump_prev boolean
---@param qf_mode QFmode
---@param is_center boolean
---@param is_expanded boolean
---@param is_only boolean
function M.handle_nav(is_jump_prev, qf_mode, is_center, is_expanded, is_only)
  qf_mode = qf_mode or "open"
  is_only = is_only or false
  is_center = is_center or false
  is_expanded = is_expanded or false

  local _, nav_key = get_cmd_direction_and_nav_key(is_jump_prev)
  local total_items = vim.api.nvim_buf_line_count(0)
  local current_idx = QfbookmarkUtils.get_current_qf_idx()
  local is_cycle_nav = true

  if tonumber(total_items) == current_idx and nav_key == "j" and not is_only then
    go_first_line() -- If the cursor is at the very bottom line
    is_cycle_nav = false
  elseif current_idx == 1 and nav_key == "k" and not is_only then
    go_last_line()
    is_cycle_nav = false
  end

  if is_cycle_nav and not is_only then
    QfbookmarkUtils.feedkey(nav_key)
  end

  vim.schedule(function()
    local indices = { vim.fn.line "." }
    open_qf_items(qf_mode, indices, "default", is_center, is_expanded, is_only)
  end)
end

local function get_items_list()
  if QfbookmarkUtils.is_loclist() then
    local results = QfbookmarkUtils.get_data_qf(true)
    return results.location.items
  end

  local results = QfbookmarkUtils.get_data_qf()
  return results.quickfix.items
end

---@param open_mode OpenMode
local function visual_vsplit(open_mode)
  local from, to
  from, to = vim.fn.line ".", vim.fn.line "v"
  if from > to then
    from, to = to, from
  end

  local items = get_items_list()

  for i = from, to do
    local item = items[i]
    if item then
      vim.cmd [[wincmd p]]

      local filename = item.filename
      local _, err = pcall(function()
        vim.cmd(open_mode .. filename)
      end)

      if err and (string.match(err, "E36") or string.match(err, "Not enough room")) then
        QfbookmarkUtils.warn "Some items cannot be opened because there is not enough room (Error E36)"
        break
      end
    end
  end
  vim.cmd [[wincmd =]]
end

---@param open_mode OpenMode
---@param is_center boolean
---@param is_expanded boolean
function M.handle_open(open_mode, is_center, is_expanded)
  local mode = vim.fn.mode(1) -- :h mode()
  if mode == "v" or mode == "V" then
    visual_vsplit(open_mode)
    return
  end

  local indices = { vim.fn.line "." }
  open_qf_items("only", indices, open_mode, is_center, is_expanded, true)
end

---@param is_set_notify? boolean
---@param is_prev? boolean
function M.handle_hist(is_set_notify, is_prev)
  is_set_notify = is_set_notify or false
  is_prev = is_prev or false

  local cmdmsg

  if QfbookmarkUtils.is_loclist() then
    cmdmsg = "lnewer"
    if is_prev then
      cmdmsg = "lolder"
    end
  else
    cmdmsg = "cnewer"
    if is_prev then
      cmdmsg = "colder"
    end
  end

  vim.schedule(function()
    local _, err = pcall(function()
      vim.fn.execute(cmdmsg)
    end)

    if err and (string.match(err, "E380") or string.match(err, "E381")) then
      local msg
      if cmdmsg == "lnewer" or cmdmsg == "cnewer" then
        msg = string.format("`%s`: no more history", cmdmsg)
      else
        msg = string.format("`%s`: already at the end", cmdmsg)
      end

      if is_set_notify then
        QfbookmarkUtils.warn(msg)
      end
      return
    end
  end)
end

local current_idx_mark = 0

---@param mark_lists QFbookBufferMarkEntry[]
---@param is_prev boolean
function M.handle_nav_mark(mark_lists, is_prev)
  local next = 1
  if is_prev then
    next = -1
  end

  current_idx_mark = current_idx_mark + next

  if is_prev then
    if current_idx_mark == 0 then
      current_idx_mark = #mark_lists
    end
  else
    if current_idx_mark > #mark_lists then
      current_idx_mark = 1
    end
  end

  ---@type QFbookBufferMarkEntry
  local next_mark = mark_lists[current_idx_mark]
  if not next_mark then
    return
  end

  local jump_opts = {
    filename = next_mark.filename,
    line = next_mark.line,
    col = next_mark.col,
    text = next_mark.text,
  }

  M.jump_to(jump_opts)
end

return M
