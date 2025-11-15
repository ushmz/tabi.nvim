---@class WanderConfig
local M = {}

---@class WanderOptions
---@field storage WanderStorageConfig
---@field ui WanderUIConfig

---@class WanderStorageConfig
---@field backend 'local'|'global'

---@class WanderUIConfig
---@field selector 'native'|'telescope'|'float'
---@field note_preview_length number
---@field use_icons boolean
---@field float_config WanderFloatConfig
---@field telescope WanderTelescopeConfig

---@class WanderFloatConfig
---@field width number
---@field height number
---@field border string

---@class WanderTelescopeConfig
---@field theme string|nil
---@field layout_config table

--- Default configuration
M.defaults = {
  storage = {
    backend = 'local', -- 'local' (.git/wander/) or 'global' (XDG_DATA_HOME)
  },
  ui = {
    selector = 'native', -- 'native', 'telescope', or 'float'
    note_preview_length = 30,
    use_icons = true,
    float_config = {
      width = 60,
      height = 10,
      border = 'rounded',
    },
    telescope = {
      theme = nil,
      layout_config = {},
    },
  },
}

--- Current configuration
M.options = vim.deepcopy(M.defaults)

--- Setup configuration
---@param opts WanderOptions|nil
function M.setup(opts)
  M.options = vim.tbl_deep_extend('force', M.defaults, opts or {})
end

--- Get current configuration
---@return WanderOptions
function M.get()
  return M.options
end

return M
