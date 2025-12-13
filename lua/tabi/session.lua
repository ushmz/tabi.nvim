---@class TabiSession
local M = {}

local utils = require("tabi.utils")
local storage = require("tabi.storage")

---@class SessionData
---@field id string
---@field name string
---@field created_at string
---@field updated_at string
---@field branch string|nil
---@field tag string|nil
---@field notes NoteData[]

local DEFAULT_SESSION_ID = "default"

--- Create a new session
---@param name string|nil Session name
---@return SessionData|nil
function M.create(name)
  -- Generate session name if not provided
  local session_name
  if name then
    session_name = name
  else
    -- Generate default name based on timestamp
    session_name = "session-" .. os.date("%Y%m%d-%H%M%S")
  end

  -- Check if session with same name already exists
  local existing_sessions = M.list()
  for _, existing in ipairs(existing_sessions) do
    if existing.name == session_name then
      vim.notify("Tabi: Session with name '" .. session_name .. "' already exists", vim.log.levels.WARN)
      return nil
    end
  end

  -- Always generate new UUID for session ID
  local session_id = utils.uuid()

  local session = {
    id = session_id,
    name = session_name,
    created_at = utils.timestamp(),
    updated_at = utils.timestamp(),
    branch = utils.get_git_branch(),
    tag = nil,
    notes = {},
  }

  local backend = storage.get_backend()
  if backend and backend.save_session then
    backend.save_session(session)
  end

  return session
end

--- Load a session by ID
---@param session_id string
---@return SessionData|nil
function M.load(session_id)
  local backend = storage.get_backend()
  if not backend or not backend.load_session then
    return nil
  end

  return backend.load_session(session_id)
end

--- Save a session
---@param session SessionData
---@return boolean success
function M.save(session)
  session.updated_at = utils.timestamp()

  local backend = storage.get_backend()
  if not backend or not backend.save_session then
    return false
  end

  return backend.save_session(session)
end

--- Get or create default session
---@return SessionData
function M.get_or_create_default()
  local session = M.load(DEFAULT_SESSION_ID)
  if session then
    return session
  end

  -- Create default session with fixed ID and name
  local default_session = {
    id = DEFAULT_SESSION_ID,
    name = "default",
    created_at = utils.timestamp(),
    updated_at = utils.timestamp(),
    branch = utils.get_git_branch(),
    tag = nil,
    notes = {},
  }

  local backend = storage.get_backend()
  if backend and backend.save_session then
    backend.save_session(default_session)
  end

  return default_session
end

--- List all sessions
---@return SessionData[]
function M.list()
  local backend = storage.get_backend()
  if not backend or not backend.list_sessions then
    return {}
  end

  return backend.list_sessions()
end

--- Delete a session
---@param session_id string
---@return boolean success
function M.delete(session_id)
  if session_id == DEFAULT_SESSION_ID then
    vim.notify("Tabi: Cannot delete default session", vim.log.levels.WARN)
    return false
  end

  local backend = storage.get_backend()
  if not backend or not backend.delete_session then
    return false
  end

  return backend.delete_session(session_id)
end

--- Rename a session
---@param session_id string
---@param new_name string
---@return boolean success
function M.rename(session_id, new_name)
  local session = M.load(session_id)
  if not session then
    vim.notify("Tabi: Session not found", vim.log.levels.ERROR)
    return false
  end

  session.name = new_name
  return M.save(session)
end

--- Add a note to a session
---@param session SessionData
---@param note NoteData
---@return boolean success
function M.add_note(session, note)
  table.insert(session.notes, note)
  return M.save(session)
end

--- Remove a note from a session
---@param session SessionData
---@param note_id string
---@return boolean success
function M.remove_note(session, note_id)
  for i, note in ipairs(session.notes) do
    if note.id == note_id then
      table.remove(session.notes, i)
      return M.save(session)
    end
  end
  return false
end

--- Update a note in a session
---@param session SessionData
---@param note_id string
---@param new_content string
---@return boolean success
function M.update_note(session, note_id, new_content)
  for _, note in ipairs(session.notes) do
    if note.id == note_id then
      note.content = new_content
      return M.save(session)
    end
  end
  return false
end

--- Get notes for a specific file
---@param session SessionData
---@param file_path string
---@return NoteData[]
function M.get_notes_for_file(session, file_path)
  local notes = {}
  for _, note in ipairs(session.notes) do
    if note.file == file_path then
      table.insert(notes, note)
    end
  end
  return notes
end

--- Get note at specific line
---@param session SessionData
---@param file_path string
---@param line number
---@return NoteData|nil
function M.get_note_at_line(session, file_path, line)
  for _, note in ipairs(session.notes) do
    if note.file == file_path then
      local note_end_line = note.end_line or note.line
      if line >= note.line and line <= note_end_line then
        return note
      end
    end
  end
  return nil
end

return M
