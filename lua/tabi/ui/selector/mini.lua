---@class TabiSelector
local M = {}

local session_module = require("tabi.session")
local config = require("tabi.config")

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

  -- Build picker items. mini.pick matches/displays table items via their `text` field.
  local items = {}
  for _, session in ipairs(sessions) do
    local date = vim.fn.strftime("%Y-%m-%d", vim.fn.strptime("%Y-%m-%dT%H:%M:%SZ", session.updated_at))
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
      -- Stop the picker as soon as an item is chosen instead of allowing
      -- multi-select style continuation.
      choose = function(_)
        return false
      end,
      preview = function(buf_id, item)
        local session = item.session
        local lines = {
          "Session: " .. session.name,
          "ID: " .. session.id,
          "Branch: " .. (session.branch or "N/A"),
          "Created: " .. session.created_at,
          "Updated: " .. session.updated_at,
          "Notes: " .. #session.notes,
          "",
          "--- Notes ---",
        }

        for i, note in ipairs(session.notes) do
          table.insert(lines, string.format("%d. %s:%d", i, note.file, note.line))
          local first_line = note.content:match("^[^\n]+") or note.content
          if #first_line > 60 then
            first_line = first_line:sub(1, 57) .. "..."
          end
          table.insert(lines, "   " .. first_line)
          table.insert(lines, "")
        end

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
