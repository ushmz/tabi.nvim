---@class TabiSelectorFactory
local M = {}

local config = require("tabi.config")

--- Get the appropriate selector based on configuration
---@return table Selector module with select_session function
function M.get_selector()
  local selector_type = config.get().ui.selector
  if selector_type == "telescope" then
    return require("tabi.ui.selector.telescope")
  elseif selector_type == "float" then
    return require("tabi.ui.selector.float")
  else
    return require("tabi.ui.selector.native")
  end
end

return M
