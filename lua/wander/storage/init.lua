---@class WanderStorage
local M = {}

local config = require("wander.config")

---@type WanderStorageBackend|nil
M.backend = nil

--- Initialize storage backend
function M.init()
  local opts = config.get()
  if opts.storage.backend == "local" then
    M.backend = require("wander.storage.local")
  else
    M.backend = require("wander.storage.global")
  end

  if M.backend and M.backend.init then
    M.backend:init()
  end
end

--- Get storage backend
---@return WanderStorageBackend
function M.get_backend()
  return M.backend
end

return M
