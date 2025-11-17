---@class TabiSelector
local M = {}

local session_module = require("tabi.session")
local config = require("tabi.config")

--- Select a session using telescope.nvim
---@param on_select function Callback with selected session
---@param opts table|nil Options
function M.select_session(on_select, opts)
  opts = opts or {}

  local sessions = session_module.list()

  if #sessions == 0 then
    vim.notify("Tabi: No sessions found", vim.log.levels.WARN)
    return
  end

  -- Check if telescope is available
  local has_telescope, _ = pcall(require, "telescope")
  if not has_telescope then
    vim.notify("Tabi: telescope.nvim is not installed", vim.log.levels.ERROR)
    return
  end

  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local entry_display = require("telescope.pickers.entry_display")
  local previewers = require("telescope.previewers")

  -- Get telescope config
  local telescope_config = config.get().ui.telescope

  -- Create entry display
  local displayer = entry_display.create({
    separator = " ",
    items = {
      { width = 30 },
      { width = 12 },
      { width = 15 },
      { remaining = true },
    },
  })

  local make_display = function(entry)
    return displayer({
      entry.name,
      string.format("%d notes", entry.note_count),
      entry.date,
      entry.branch or "N/A",
    })
  end

  -- Create previewer to show session notes
  local previewer = previewers.new_buffer_previewer({
    title = "Session Notes",
    define_preview = function(self, entry)
      local session = entry.session
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
        -- Add first line of note content
        local first_line = note.content:match("^[^\n]+") or note.content
        if #first_line > 60 then
          first_line = first_line:sub(1, 57) .. "..."
        end
        table.insert(lines, "   " .. first_line)
        table.insert(lines, "")
      end

      vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
    end,
  })

  -- Build picker options
  local picker_opts = {
    prompt_title = "Select Session",
    finder = finders.new_table({
      results = sessions,
      entry_maker = function(session)
        local date = vim.fn.strftime("%Y-%m-%d", vim.fn.strptime("%Y-%m-%dT%H:%M:%SZ", session.updated_at))
        return {
          value = session,
          display = make_display,
          ordinal = session.name,
          name = session.name,
          note_count = #session.notes,
          date = date,
          branch = session.branch,
          session = session,
        }
      end,
    }),
    sorter = conf.generic_sorter({}),
    previewer = previewer,
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if selection then
          vim.schedule(function()
            on_select(selection.session)
          end)
        elseif opts.on_cancel then
          vim.schedule(function()
            opts.on_cancel()
          end)
        end
      end)
      return true
    end,
  }

  -- Apply theme if configured
  if telescope_config.theme then
    local theme_func = require("telescope.themes")["get_" .. telescope_config.theme]
    if theme_func then
      picker_opts = theme_func(picker_opts)
    end
  end

  -- Apply layout config
  if telescope_config.layout_config and next(telescope_config.layout_config) then
    picker_opts.layout_config =
      vim.tbl_deep_extend("force", picker_opts.layout_config or {}, telescope_config.layout_config)
  end

  pickers.new({}, picker_opts):find()
end

return M
