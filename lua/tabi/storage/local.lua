---@class TabiStorageBackend
local M = {}

local utils = require("tabi.utils")

--- Get storage directory path
---@return string|nil
function M.get_storage_dir()
  local git_root = utils.get_git_root()
  if not git_root then
    return nil
  end
  return git_root .. "/.git/tabi"
end

--- Get sessions directory path
---@return string|nil
function M.get_sessions_dir()
  local storage_dir = M.get_storage_dir()
  if not storage_dir then
    return nil
  end
  return storage_dir .. "/sessions"
end

--- Initialize storage
function M.init()
  if not utils.is_git_repo() then
    vim.notify("Tabi: Not in a git repository", vim.log.levels.WARN)
    return
  end

  local sessions_dir = M.get_sessions_dir()
  if not sessions_dir then
    vim.notify("Tabi: Failed to get storage directory", vim.log.levels.ERROR)
    return
  end

  utils.ensure_dir(sessions_dir)
end

--- Save session to file
---@param session SessionData
---@return boolean success
function M.save_session(session)
  local sessions_dir = M.get_sessions_dir()
  if not sessions_dir then
    vim.notify("Tabi: Failed to get sessions directory", vim.log.levels.ERROR)
    return false
  end

  local file_path = sessions_dir .. "/" .. session.id .. ".json"
  local json = vim.json.encode(session)

  local file = io.open(file_path, "w")
  if not file then
    vim.notify("Tabi: Failed to save session: " .. file_path, vim.log.levels.ERROR)
    return false
  end

  file:write(json)
  file:close()
  return true
end

--- Load session from file
---@param session_id string
---@return SessionData|nil
function M.load_session(session_id)
  local sessions_dir = M.get_sessions_dir()
  if not sessions_dir then
    return nil
  end

  local file_path = sessions_dir .. "/" .. session_id .. ".json"
  local file = io.open(file_path, "r")
  if not file then
    return nil
  end

  local content = file:read("*a")
  file:close()

  local ok, session = pcall(vim.json.decode, content)
  if not ok then
    vim.notify("Tabi: Failed to parse session file: " .. file_path, vim.log.levels.ERROR)
    return nil
  end

  return session
end

--- List all sessions
---@return SessionData[]
function M.list_sessions()
  local sessions_dir = M.get_sessions_dir()
  if not sessions_dir then
    return {}
  end

  local sessions = {}
  local handle = vim.loop.fs_scandir(sessions_dir)
  if not handle then
    return {}
  end

  while true do
    local name, type = vim.loop.fs_scandir_next(handle)
    if not name then
      break
    end

    if type == "file" and name:match("%.json$") then
      local session_id = name:gsub("%.json$", "")
      local session = M.load_session(session_id)
      if session then
        table.insert(sessions, session)
      end
    end
  end

  -- Sort by updated_at (most recent first)
  table.sort(sessions, function(a, b)
    return a.updated_at > b.updated_at
  end)

  return sessions
end

--- Delete session
---@param session_id string
---@return boolean success
function M.delete_session(session_id)
  local sessions_dir = M.get_sessions_dir()
  if not sessions_dir then
    return false
  end

  local file_path = sessions_dir .. "/" .. session_id .. ".json"
  local ok, err = os.remove(file_path)
  if not ok then
    vim.notify("Tabi: Failed to delete session: " .. (err or "unknown error"), vim.log.levels.ERROR)
    return false
  end

  return true
end

--- Check if session exists
---@param session_id string
---@return boolean
function M.session_exists(session_id)
  local sessions_dir = M.get_sessions_dir()
  if not sessions_dir then
    return false
  end

  local file_path = sessions_dir .. "/" .. session_id .. ".json"
  local stat = vim.loop.fs_stat(file_path)
  return stat ~= nil
end

return M
