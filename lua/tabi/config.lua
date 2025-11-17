---@class TabiConfig
local M = {}

---@class TabiOptions
---@field storage TabiStorageConfig
---@field ui TabiUIConfig
---@field keymaps TabiKeymapsConfig

---@class TabiStorageConfig
---@field backend 'local'|'global'

---@class TabiKeymapsConfig
---@field enabled boolean
---@field start string|false
---@field ["end"] string|false
---@field note string|false
---@field note_delete string|false
---@field retrace string|false
---@field retrace_end string|false
---@field sessions string|false

---@class TabiUIConfig
---@field selector 'native'|'telescope'|'float'
---@field note_preview_length number
---@field use_icons boolean
---@field float_config TabiFloatConfig
---@field telescope TabiTelescopeConfig

---@class TabiFloatConfig
---@field width number
---@field height number
---@field border string

---@class TabiTelescopeConfig
---@field theme string|nil
---@field layout_config table

--- Default configuration
M.defaults = {
  storage = {
    backend = "local", -- 'local' (.git/tabi/) or 'global' (XDG_DATA_HOME)
  },
  ui = {
    selector = "native", -- 'native', 'telescope', or 'float'
    note_preview_length = 30,
    use_icons = true,
    float_config = {
      width = 60,
      height = 10,
      border = "rounded",
    },
    telescope = {
      theme = nil,
      layout_config = {},
    },
  },
  keymaps = {
    enabled = true,
    start = "<Leader>ts",
    ["end"] = "<Leader>te",
    note = "<Leader>tn",
    note_delete = "<Leader>td",
    retrace = "<Leader>tr",
    retrace_end = "<Leader>tq",
    sessions = "<Leader>tl",
  },
}

--- Current configuration
M.options = vim.deepcopy(M.defaults)

--- Setup configuration
---@param opts TabiOptions|nil
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

--- Get current configuration
---@return TabiOptions
function M.get()
  return M.options
end

return M
