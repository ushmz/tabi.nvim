---@class TabiStorage
local M = {}

local config = require("tabi.config")

---@type TabiStorageBackend|nil
M.backend = nil

--- Initialize storage backend
function M.init()
  local opts = config.get()
  if opts.storage.backend == "local" then
    M.backend = require("tabi.storage.local")
  else
    M.backend = require("tabi.storage.global")
  end

  if M.backend and M.backend.init then
    M.backend:init()
  end
end

--- Get storage backend
---@return TabiStorageBackend
function M.get_backend()
  return M.backend
end

return M
