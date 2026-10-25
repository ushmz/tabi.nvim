---@class TabiSelector
local M = {}

local session_module = require("tabi.session")
local utils = require("tabi.utils")

--- Select a session from list
---@param on_select function Callback with selected session
---@param opts table|nil Options
function M.select_session(on_select, opts)
  opts = opts or {}

  local sessions = session_module.list()

  if #sessions == 0 then
    vim.notify("Tabi: No sessions found", vim.log.levels.WARN)
    return
  end

  -- Format sessions for display
  local items = {}
  for _, session in ipairs(sessions) do
    local item_text = string.format(
      "%s (%d notes, %s)",
      session.name,
      #session.notes,
      utils.format_timestamp(session.updated_at, "%Y-%m-%d")
    )
    table.insert(items, item_text)
  end

  vim.ui.select(items, {
    prompt = "Select session:",
    format_item = function(item)
      return item
    end,
  }, function(choice, idx)
    if not choice or not idx then
      if opts.on_cancel then
        opts.on_cancel()
      end
      return
    end

    -- Defer execution to allow UI to clean up
    vim.schedule(function()
      on_select(sessions[idx])
    end)
  end)
end

return M
