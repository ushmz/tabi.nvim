---@class TabiSelectorFactory
local M = {}

local config = require("tabi.config")

--- Get the appropriate selector based on configuration
---@return table Selector module with select_session function
function M.get_selector()
  local selector_type = config.get().ui.selector
  if selector_type == "telescope" then
    return require("tabi.ui.selector.telescope")
  elseif selector_type == "mini" then
    return require("tabi.ui.selector.mini")
  else
    if selector_type ~= nil and selector_type ~= "native" then
      vim.notify(
        string.format("Tabi: Unknown ui.selector '%s', falling back to 'native'", tostring(selector_type)),
        vim.log.levels.WARN
      )
    end
    return require("tabi.ui.selector.native")
  end
end

return M
