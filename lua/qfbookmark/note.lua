local Config = require("qfbookmark.config").defaults

local QfbookmarkUtils = require "qfbookmark.utils"
local QfbookmarkPath = require "qfbookmark.path"
local QfbookmarkPathUtils = require "qfbookmark.path.utils"

local QfbookmarkUI = require "qfbookmark.ui"
local QfbookmarkUiUtils = require "qfbookmark.ui.utils"

local M = {}

local last_position = nil

-- +-----------------------------------------------------------------------------+
-- |                                    MISC                                     |
-- +-----------------------------------------------------------------------------+

--- Resolve a template definition by name from the configured templates table.
---@param templates table<string, QFBookNoteIntegrationsTemplates>
---@param name string
---@return QFBookNoteIntegrationsTemplates | nil
local function resolve_template(templates, name)
  if not templates then
    return nil
  end
  return templates[name]
end

--- Render a template string by substituting the line placeholder with
--- the captured text. Multi-line captures are joined with newlines so
--- the placeholder can sit on its own line in the template and still
--- expand to multiple lines correctly.
---@param template string|function
---@param lines    string[]
---@return string[] | nil
local function render(template, lines)
  if not Config.window.note.insert_to_note.line_placeholder then
    QfbookmarkUtils.warn "`line_placeholder` cannot be nil or an empty string"
    return
  end

  local LINE_PLACEHOLDER = Config.window.note.insert_to_note.line_placeholder

  local placeholder = vim.pesc(LINE_PLACEHOLDER)

  local rendered = template:gsub("([ \t]*)" .. placeholder, function(indent)
    local prefix = indent

    local result = {}
    for _, line in ipairs(lines) do
      result[#result + 1] = prefix .. line
    end

    return table.concat(result, "\n")
  end)

  return vim.split(rendered, "\n", { plain = true })
end

--- Resolve the note file path for a given target.
---@param target string
---@return string | nil
local function resolve_note_path(target)
  local path = ""

  -- global: use global config path
  if target == "global" then
    path = QfbookmarkPath.get_target_dir_path(true) .. "/note.org"

    -- local: project-specific note, alongside the project's marks dir
  elseif target == "local" then
    if Config.window.note.current_project and Config.window.note.current_project.enabled then
      path = Config.window.note.current_project.filename
    else
      local dir = QfbookmarkPath.get_target_dir_path(false)
      path = dir .. "/note.org"
    end
  else
    path = target
  end

  assert(QfbookmarkPathUtils.is_file(path), string.format("invalid target '%s': file does not exist", path))

  return path
end

--- Append rendered lines to a note file, creating the file/dir if needed.
---@param path string
---@param lines string[]
local function append_to_note(path, lines)
  local dir = vim.fn.fnamemodify(path, ":h")
  if not QfbookmarkPathUtils.is_dir(dir) then
    QfbookmarkPathUtils.create_dir(dir)
  end

  local existing = {}
  if QfbookmarkPathUtils.is_file(path) then
    local f = io.open(path, "r")
    if f then
      for line in f:lines() do
        existing[#existing + 1] = line
      end
      f:close()
    end
  end

  -- separate entries with a single blank line for readability
  if #existing > 0 and existing[#existing] ~= "" then
    existing[#existing + 1] = ""
  end

  for _, line in ipairs(lines) do
    existing[#existing + 1] = line
  end

  local f = io.open(path, "w")
  if not f then
    QfbookmarkUtils.warn("Could not write note file: " .. path)
    return false
  end
  f:write(table.concat(existing, "\n") .. "\n")
  f:close()
  return true
end

---@param note_path string
---@param cfg_note QFBookWindowNotes
---@param is_insert_to? boolean
---@param window_command string
local function toggle_note(note_path, cfg_note, is_global, is_insert_to, window_command)
  is_insert_to = is_insert_to or false

  local win_note = QfbookmarkUtils.find_window_by_filename(note_path)

  if not win_note then
    if cfg_note.mode ~= "float" then
      vim.cmd(window_command)
      vim.cmd("edit " .. vim.fn.fnameescape(note_path))

      local win = vim.api.nvim_get_current_win()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_call(win, function()
          local editor = QfbookmarkUiUtils.get_editor_size()

          local cfg_width = cfg_note.width * 100
          local cfg_height = cfg_note.height * 100

          local width = math.floor(editor.width * cfg_width / 100)
          local height = math.floor(editor.height * cfg_height / 100)

          vim.api.nvim_win_set_width(win, width)
          vim.api.nvim_win_set_height(win, height)

          vim.api.nvim_set_option_value("winfixheight", true, { scope = "local", win = win })
        end)
      end
    else
      QfbookmarkUI.open_note_in_float(note_path, cfg_note, is_global)
    end

    -- Open folds at the cursor position and restore the last cursor location
    vim.schedule(function()
      local line = vim.api.nvim_win_get_cursor(0)[1]
      if not line then
        return
      end
      local fold_start = vim.fn.foldclosed(line)
      if fold_start ~= -1 then
        vim.cmd "silent! foldopen!"
      end

      if not is_insert_to then
        local mark
        if last_position then
          mark = last_position
        else
          -- Fallback: go to last known cursor position (mark ")
          mark = vim.api.nvim_buf_get_mark(0, '"')
        end

        local line_count = vim.api.nvim_buf_line_count(0)

        if mark[1] > 0 and mark[1] <= line_count then
          pcall(vim.api.nvim_win_set_cursor, 0, mark)
        end
      else
        -- Move cursor to the end of the note after inserting text
        local text = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        pcall(vim.api.nvim_win_set_cursor, 0, { #text, 0 })
      end

      local win = vim.api.nvim_get_current_win()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_call(win, function()
          if Config.window.note.wrap then
            vim.api.nvim_set_option_value("wrap", true, { scope = "local", win = win })
          end
        end)
      end
    end)
  else
    if win_note and vim.api.nvim_win_is_valid(win_note) then
      vim.api.nvim_set_current_win(win_note)
      local row = vim.api.nvim_win_get_cursor(0)[1]
      local col = vim.api.nvim_win_get_cursor(0)[2]
      last_position = { row, col }
    end

    local buf_note = vim.api.nvim_win_get_buf(win_note)

    -- Auto save enabled
    vim.api.nvim_buf_call(buf_note, function()
      if vim.bo[buf_note].modified then
        vim.cmd "silent write"
      end
    end)

    QfbookmarkUtils.delete_buffer_by_name(note_path)
  end
end

---@param is_global boolean
---@param cfg_note QFBookWindowNotes
---@param is_insert_to boolean
---@param window_command? string
function M.handle_open(is_global, cfg_note, is_insert_to, window_command)
  window_command = window_command or ""

  local note_path

  local file_extension = "." .. cfg_note.filetype

  if is_global then
    QfbookmarkPath.setup_path(is_global)
    note_path = QfbookmarkPath.get_target_file_path(is_global)
    note_path = note_path .. "/note" .. file_extension
  else
    if cfg_note.current_project.enabled then
      note_path = cfg_note.current_project.filename
      note_path = vim.uv.cwd() .. "/" .. note_path
    else
      QfbookmarkPath.setup_path(is_global)
      note_path = QfbookmarkPathUtils.get_base_path_root(note_path, is_global) .. file_extension
    end
  end

  if not QfbookmarkPathUtils.is_file(note_path) then
    QfbookmarkPathUtils.create_file(note_path)
  end

  toggle_note(note_path, cfg_note, is_global, is_insert_to, window_command)
end

--- Insert captured text (visual selection, falling back to the current
--- line) into a note file using a configured template.
---@param template_name string
function M.add_to_note(template_name)
  if not Config.window.note.insert_to_note or not Config.window.note.insert_to_note.enabled then
    QfbookmarkUtils.warn "Custom templates are disabled in config."
    return
  end

  local templates_cfg = Config.window.note.insert_to_note and Config.window.note.insert_to_note.templates

  local template = resolve_template(templates_cfg, template_name)
  if not template then
    QfbookmarkUtils.warn(string.format("Note template '%s' not found.", template_name))
    return
  end

  -- Resolve dynamic templates at runtime so values like vim.bo.filetype
  -- are evaluated from the current buffer instead of when the config is loaded.
  if type(template.templates) == "function" then
    template.templates = template.templates()
  end

  -- capture BEFORE any vim.schedule — visual marks ('<, '>) only survive
  -- until the next normal-mode command, so this must run synchronously
  -- in the same call stack as the keymap/command invocation.
  local sel = QfbookmarkUtils.get_visual_selection { exit_from_visual = true }

  if not sel then
    return
  end

  if not QfbookmarkUtils.has_content(sel.lines) then
    QfbookmarkUtils.warn "Nothing to insert — selection and current line are both empty."
    return
  end

  local rendered = render(template.templates, sel.lines)
  if not rendered then
    return
  end

  local note_path = resolve_note_path(template.target)

  if not note_path then
    QfbookmarkUtils.warn(string.format("Could not resolve note path for target '%s'.", template.target))
    return
  end

  local ok = append_to_note(note_path, rendered)
  if not ok then
    return
  end

  QfbookmarkUtils.info(string.format("Added to %s note (template: %s)", template.target, template_name))

  local cfg_note = Config.window.note
  local is_insert_to = true

  toggle_note(note_path, cfg_note, false, is_insert_to, "")
end

return M
