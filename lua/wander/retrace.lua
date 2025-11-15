---@class WanderRetrace
local M = {}

---@class RetraceState
---@field session SessionData
---@field current_index number
---@field loclist_win number Window ID that owns the location list
---@field loclist_bufwin number|nil Location list window ID

local state = nil

--- Start retrace mode with a session
---@param session SessionData
function M.start(session)
  if #session.notes == 0 then
    vim.notify("Wander: Session has no notes to retrace", vim.log.levels.WARN)
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
      text = note.content:gsub("\n", " "), -- Single line for location list
    })
  end

  -- Set location list for current window
  vim.fn.setloclist(winid, loclist_items)

  state = {
    session = session,
    current_index = 1,
    loclist_win = winid,
    loclist_bufwin = nil,
  }

  -- Open location list window
  vim.cmd("silent! lopen")

  -- Store the location list window ID
  state.loclist_bufwin = vim.api.nvim_get_current_win()

  -- Jump to first note (this will focus the location list)
  M.show_current(true) -- silent=true to avoid double notification

  vim.notify(string.format("Wander: Retrace mode started - Note 1/%d", #session.notes), vim.log.levels.INFO)
  return true
end

--- End retrace mode
function M.stop()
  if not state then
    vim.notify("Wander: Not in retrace mode", vim.log.levels.WARN)
    return
  end

  -- Clear location list if the window is still valid
  if state.loclist_win and vim.api.nvim_win_is_valid(state.loclist_win) then
    vim.fn.setloclist(state.loclist_win, {})
  end

  state = nil
  vim.notify("Wander: Retrace mode ended", vim.log.levels.INFO)
end

--- Show current note
---@param silent boolean|nil If true, suppress notification
function M.show_current(silent)
  if not state then
    vim.notify("Wander: Not in retrace mode", vim.log.levels.WARN)
    return
  end

  local note = state.session.notes[state.current_index]
  if not note then
    return
  end

  -- Focus location list window if it's still valid
  if state.loclist_bufwin and vim.api.nvim_win_is_valid(state.loclist_bufwin) then
    vim.api.nvim_set_current_win(state.loclist_bufwin)

    -- Move cursor to the current item in location list
    vim.api.nvim_win_set_cursor(state.loclist_bufwin, { state.current_index, 0 })

    -- Center the line
    vim.cmd("normal! zz")
  end

  -- Show progress (unless silent)
  if not silent then
    vim.notify(string.format("Wander: Note %d/%d", state.current_index, #state.session.notes), vim.log.levels.INFO)
  end
end

--- Go to next note
function M.next()
  if not state then
    vim.notify("Wander: Not in retrace mode", vim.log.levels.WARN)
    return
  end

  if state.current_index >= #state.session.notes then
    vim.notify("Wander: Already at last note", vim.log.levels.WARN)
    return
  end

  state.current_index = state.current_index + 1
  M.show_current()
end

--- Go to previous note
function M.prev()
  if not state then
    vim.notify("Wander: Not in retrace mode", vim.log.levels.WARN)
    return
  end

  if state.current_index <= 1 then
    vim.notify("Wander: Already at first note", vim.log.levels.WARN)
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
