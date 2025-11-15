---@class WanderRetrace
local M = {}

local float = require('wander.ui.float')

---@class RetraceState
---@field session SessionData
---@field current_index number
---@field win_id number|nil Floating window showing note content
---@field loclist_win number Window ID that owns the location list

local state = nil

--- Start retrace mode with a session
---@param session SessionData
function M.start(session)
  if #session.notes == 0 then
    vim.notify('Wander: Session has no notes to retrace', vim.log.levels.WARN)
    return false
  end

  -- Get current window ID for location list
  local winid = vim.api.nvim_get_current_win()

  -- Create location list items from notes
  local loclist_items = {}
  for _, note in ipairs(session.notes) do
    table.insert(loclist_items, {
      filename = note.file,
      lnum = note.line,
      col = 1,
      text = note.content:gsub('\n', ' '), -- Single line for location list
    })
  end

  -- Set location list for current window
  vim.fn.setloclist(winid, loclist_items)

  state = {
    session = session,
    current_index = 1,
    win_id = nil,
    loclist_win = winid,
  }

  -- Jump to first note
  M.show_current()

  vim.notify('Wander: Retrace mode started (' .. #session.notes .. ' notes)', vim.log.levels.INFO)
  return true
end

--- End retrace mode
function M.stop()
  if not state then
    vim.notify('Wander: Not in retrace mode', vim.log.levels.WARN)
    return
  end

  -- Close floating window if open
  if state.win_id and vim.api.nvim_win_is_valid(state.win_id) then
    vim.api.nvim_win_close(state.win_id, true)
  end

  -- Clear location list if the window is still valid
  if state.loclist_win and vim.api.nvim_win_is_valid(state.loclist_win) then
    vim.fn.setloclist(state.loclist_win, {})
  end

  state = nil
  vim.notify('Wander: Retrace mode ended', vim.log.levels.INFO)
end

--- Show current note
function M.show_current()
  if not state then
    vim.notify('Wander: Not in retrace mode', vim.log.levels.WARN)
    return
  end

  local note = state.session.notes[state.current_index]
  if not note then
    return
  end

  -- Jump to location list item
  -- Use silent! to suppress error messages if location list is somehow invalid
  vim.cmd('silent! ll ' .. state.current_index)

  -- Center the line
  vim.cmd('normal! zz')

  -- Show note content in floating window
  M.show_note_float(note)

  -- Show progress
  vim.notify(
    string.format('Wander: Note %d/%d', state.current_index, #state.session.notes),
    vim.log.levels.INFO
  )
end

--- Show note content in a floating window
---@param note NoteData
function M.show_note_float(note)
  -- Close previous window if exists
  if state.win_id and vim.api.nvim_win_is_valid(state.win_id) then
    vim.api.nvim_win_close(state.win_id, true)
  end

  -- Create floating window
  local bufnr, winid = float.create_float({ height = 15, width = 70 })
  state.win_id = winid

  -- Set content
  local lines = vim.split(note.content, '\n')
  table.insert(lines, 1, '# Note at ' .. vim.fn.fnamemodify(note.file, ':~:.') .. ':' .. note.line)
  table.insert(lines, 2, '')

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(bufnr, 'modifiable', false)

  -- Set up keymaps to close
  vim.keymap.set('n', 'q', function()
    if vim.api.nvim_win_is_valid(winid) then
      vim.api.nvim_win_close(winid, true)
    end
  end, { buffer = bufnr, noremap = true, silent = true })
end

--- Go to next note
function M.next()
  if not state then
    vim.notify('Wander: Not in retrace mode', vim.log.levels.WARN)
    return
  end

  if state.current_index >= #state.session.notes then
    vim.notify('Wander: Already at last note', vim.log.levels.WARN)
    return
  end

  state.current_index = state.current_index + 1
  M.show_current()
end

--- Go to previous note
function M.prev()
  if not state then
    vim.notify('Wander: Not in retrace mode', vim.log.levels.WARN)
    return
  end

  if state.current_index <= 1 then
    vim.notify('Wander: Already at first note', vim.log.levels.WARN)
    return
  end

  state.current_index = state.current_index - 1
  M.show_current()
end

--- Check if in retrace mode
---@return boolean
function M.is_active()
  return state ~= nil
end

--- Get current retrace state
---@return RetraceState|nil
function M.get_state()
  return state
end

return M
