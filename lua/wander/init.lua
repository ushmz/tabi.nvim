---@class Wander
local M = {}

---@class WanderState
---@field current_session string|nil
---@field retrace_mode boolean
---@field retrace_index number|nil
M.state = {
  current_session = nil,
  retrace_mode = false,
  retrace_index = nil,
}

--- Setup function to initialize the plugin
---@param opts table|nil User configuration options
function M.setup(opts)
  local config = require("wander.config")
  config.setup(opts or {})

  -- Initialize storage
  local storage = require("wander.storage")
  storage.init()

  -- Setup autocommands and highlights
  M._setup_highlights()
end

--- Setup highlight groups
function M._setup_highlights()
  vim.api.nvim_set_hl(0, "WanderNote", { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, "WanderNoteSign", { link = "DiagnosticInfo", default = true })
  vim.api.nvim_set_hl(0, "WanderLineNr", { link = "DiagnosticInfo", default = true })
end

return M
