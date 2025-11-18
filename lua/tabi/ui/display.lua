---@class TabiDisplay
local M = {}

local config = require("tabi.config")
local note_module = require("tabi.note")

-- Namespace for virtual text and signs
local ns = vim.api.nvim_create_namespace("tabi")

-- Sign name
local SIGN_NAME = "TabiNote"

--- Initialize display (set up signs)
function M.init()
  -- Define sign
  vim.fn.sign_define(SIGN_NAME, {
    text = "", -- Use icon or fallback
    texthl = "TabiNoteSign",
    numhl = "TabiLineNr",
  })
end

--- Clear all displays in a buffer
---@param bufnr number
function M.clear_buffer(bufnr)
  -- Clear virtual text
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

  -- Clear signs
  vim.fn.sign_unplace("tabi", { buffer = bufnr })
end

--- Display a note in the buffer
---@param bufnr number
---@param note NoteData
function M.display_note(bufnr, note)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local cfg = config.get()
  local line = note.line - 1 -- 0-indexed for API

  -- Add sign
  if cfg.ui.use_icons then
    vim.fn.sign_place(0, "tabi", SIGN_NAME, bufnr, {
      lnum = note.line,
      priority = 10,
    })
  end

  -- Add virtual lines with preview above the target line
  local preview = note_module.get_preview(note, cfg.ui.note_preview_length)
  if preview and preview ~= "" then
    vim.api.nvim_buf_set_extmark(bufnr, ns, line, 0, {
      virt_lines = { { { "Note: " .. preview, "TabiNote" } } },
      virt_lines_above = true,
    })
  end
end

--- Display a note as virtual lines below the target line
---@param bufnr number
---@param note NoteData
function M.display_note_as_virtual_line(bufnr, note)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    vim.notify("Tabi: Invalid buffer " .. bufnr, vim.log.levels.DEBUG)
    return
  end

  local cfg = config.get()
  local line = note.line - 1 -- 0-indexed for API

  -- Check if line is valid
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if line < 0 or line >= line_count then
    vim.notify(
      string.format("Tabi: Line %d out of range (buffer has %d lines)", note.line, line_count),
      vim.log.levels.DEBUG
    )
    return
  end

  -- Add sign
  if cfg.ui.use_icons then
    vim.fn.sign_place(0, "tabi", SIGN_NAME, bufnr, {
      lnum = note.line,
      priority = 10,
    })
  end

  -- Split note content into lines for virtual lines
  local virt_lines = {}
  local content_lines = vim.split(note.content, "\n", { plain = true })
  for i, content_line in ipairs(content_lines) do
    local prefix = i == 1 and "Note: " or "      "
    table.insert(virt_lines, { { prefix .. content_line, "TabiNote" } })
  end

  -- Add virtual lines above the target line
  if #virt_lines > 0 then
    vim.api.nvim_buf_set_extmark(bufnr, ns, line, 0, {
      virt_lines = virt_lines,
      virt_lines_above = true,
    })
  end
end

--- Refresh display for all notes in a file
---@param bufnr number
---@param notes NoteData[]
function M.refresh_buffer(bufnr, notes)
  M.clear_buffer(bufnr)

  for _, note in ipairs(notes) do
    M.display_note(bufnr, note)
  end
end

--- Update display when entering a buffer
---@param bufnr number
---@param session SessionData
function M.update_for_session(bufnr, session)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local file_path = vim.api.nvim_buf_get_name(bufnr)
  if file_path == "" then
    return
  end

  local session_module = require("tabi.session")
  local notes = session_module.get_notes_for_file(session, file_path)

  M.refresh_buffer(bufnr, notes)
end

--- Set up autocommands for automatic display updates
---@param session SessionData
function M.setup_autocmds(session)
  local group = vim.api.nvim_create_augroup("TabiDisplay", { clear = true })

  -- Update display when entering a buffer
  vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
    group = group,
    callback = function(args)
      M.update_for_session(args.buf, session)
    end,
  })

  -- Clear display when leaving
  vim.api.nvim_create_autocmd("BufLeave", {
    group = group,
    callback = function()
      -- Optionally keep display visible
      -- M.clear_buffer(args.buf)
    end,
  })
end

--- Clear all autocommands
function M.clear_autocmds()
  vim.api.nvim_clear_autocmds({ group = "TabiDisplay" })
end

--- Display all notes from a session as virtual lines
--- Opens files as needed and displays notes
---@param session SessionData
function M.display_all_session_notes(session)
  if not session or not session.notes then
    return
  end

  -- Group notes by file (normalize paths to absolute)
  local notes_by_file = {}
  for _, note in ipairs(session.notes) do
    local abs_path = vim.fn.fnamemodify(note.file, ":p")
    if not notes_by_file[abs_path] then
      notes_by_file[abs_path] = {}
    end
    table.insert(notes_by_file[abs_path], note)
  end

  -- Display notes for each file
  for file_path, notes in pairs(notes_by_file) do
    -- Check if buffer is already loaded (try both original and normalized path)
    local bufnr = vim.fn.bufnr(file_path)

    if bufnr == -1 then
      -- Try with expanded path
      bufnr = vim.fn.bufnr(vim.fn.expand(file_path))
    end

    if bufnr == -1 then
      -- Buffer not loaded, load it silently
      bufnr = vim.fn.bufadd(file_path)
    end

    if bufnr > 0 and vim.api.nvim_buf_is_valid(bufnr) then
      -- Ensure buffer content is loaded
      if not vim.api.nvim_buf_is_loaded(bufnr) then
        vim.fn.bufload(bufnr)
      end

      -- Check if buffer has content (file might not exist or not be readable)
      local line_count = vim.api.nvim_buf_line_count(bufnr)
      if line_count == 0 then
        -- Try to read the file content explicitly
        vim.api.nvim_buf_call(bufnr, function()
          vim.cmd("silent! edit " .. vim.fn.fnameescape(file_path))
        end)
      end

      -- Clear existing displays for this buffer
      M.clear_buffer(bufnr)

      -- Display each note as virtual line
      for _, note in ipairs(notes) do
        M.display_note_as_virtual_line(bufnr, note)
      end
    end
  end
end

--- Clear all session note displays
--- Clears virtual lines from all buffers that had notes
---@param session SessionData
function M.clear_all_session_notes(session)
  if not session or not session.notes then
    return
  end

  -- Get unique files from session notes
  local files = {}
  for _, note in ipairs(session.notes) do
    files[note.file] = true
  end

  -- Clear displays for each file's buffer
  for file_path, _ in pairs(files) do
    local bufnr = vim.fn.bufnr(file_path)
    if bufnr > 0 and vim.api.nvim_buf_is_valid(bufnr) then
      M.clear_buffer(bufnr)
    end
  end
end

return M
