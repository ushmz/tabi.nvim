---@class TabiSelector
local M = {}

local session_module = require("tabi.session")
local config = require("tabi.config")
local selector_util = require("tabi.ui.selector.util")
local utils = require("tabi.utils")

--- Select a session using mini.pick (mini.nvim)
---@param on_select function Callback with selected session
---@param opts table|nil Options
function M.select_session(on_select, opts)
  opts = opts or {}

  local sessions = session_module.list()

  if #sessions == 0 then
    vim.notify("Tabi: No sessions found", vim.log.levels.WARN)
    return
  end

  -- Checking the global (rather than `require`) ensures the user explicitly set
  -- up mini.pick, as recommended in `:h MiniPick-in-other-plugins`.
  if _G.MiniPick == nil then
    vim.notify("Tabi: mini.pick is not set up (call `require('mini.pick').setup()`)", vim.log.levels.ERROR)
    return
  end

  -- Build picker items. mini.pick displays table items via their `text` field.
  -- Matching is done against session names only (see `match` below).
  local items = {}
  local names = {}
  for _, session in ipairs(sessions) do
    table.insert(names, session.name)
    local date = utils.format_timestamp(session.updated_at, "%Y-%m-%d")
    table.insert(items, {
      text = string.format(
        "%s (%d notes, %s, branch: %s)",
        session.name,
        #session.notes,
        date,
        session.branch or "N/A"
      ),
      session = session,
    })
  end

  -- Let users pass through arbitrary MiniPick.start() options (e.g. `window`,
  -- `mappings`). `source` is always controlled by tabi.nvim and cannot be
  -- overridden this way.
  local user_opts = vim.deepcopy(config.get().ui.mini.opts or {})
  user_opts.source = nil

  local start_opts = vim.tbl_deep_extend("force", user_opts, {
    source = {
      items = items,
      name = "Sessions",
      -- Match against session names only (like the telescope selector) so that
      -- the query does not hit note counts, dates or branches in the display text.
      match = function(_, inds, query)
        return _G.MiniPick.default_match(names, inds, query)
      end,
      -- The chosen item is handled via MiniPick.start()'s return value. Override
      -- the default choose, which would print the whole item (our items have no
      -- path or buffer). Returning false stops the picker.
      choose = function(_)
        return false
      end,
      preview = function(buf_id, item)
        local lines = selector_util.build_preview_lines(item.session)
        vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)
      end,
    },
  })

  local chosen = _G.MiniPick.start(start_opts)

  if chosen then
    vim.schedule(function()
      on_select(chosen.session)
    end)
  elseif opts.on_cancel then
    vim.schedule(function()
      opts.on_cancel()
    end)
  end
end

return M
