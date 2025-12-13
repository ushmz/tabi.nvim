---@class Tabi
local M = {}

---@class TabiState
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
  local config = require("tabi.config")
  config.setup(opts or {})

  -- Initialize storage
  local storage = require("tabi.storage")
  storage.init()

  -- Setup autocommands and highlights
  M._setup_highlights()

  -- Setup keymaps
  local keymaps = require("tabi.keymaps")
  keymaps.setup()

  -- Setup default session display
  if config.get().show_default_notes then
    vim.api.nvim_create_autocmd("VimEnter", {
      once = true,
      callback = function()
        vim.schedule(function()
          M._setup_default_session_display()
        end)
      end,
    })
  end
end

--- Setup highlight groups
function M._setup_highlights()
  vim.api.nvim_set_hl(0, "TabiNote", { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, "TabiNoteSign", { link = "DiagnosticInfo", default = true })
  vim.api.nvim_set_hl(0, "TabiLineNr", { link = "DiagnosticInfo", default = true })
end

--- Setup background display for default session
function M._setup_default_session_display()
  local config = require("tabi.config")

  -- Early return if feature is disabled
  if not config.get().show_default_notes then
    return
  end

  local session_module = require("tabi.session")
  local display = require("tabi.ui.display")

  -- Load default session
  local default_session = session_module.load("default")
  if not default_session or #default_session.notes == 0 then
    return
  end

  -- Display default session notes
  display.display_all_session_notes(default_session)

  -- Setup autocmd to update display
  local group = vim.api.nvim_create_augroup("TabiDefaultSession", { clear = true })
  vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
    group = group,
    callback = function(args)
      -- Only show when no named session or retrace is active
      if not M.state.current_session and not require("tabi.retrace").is_active() then
        display.update_for_session(args.buf, default_session)
      end
    end,
  })
end

--- Clear default session display autocmds
function M._clear_default_session_display()
  pcall(vim.api.nvim_del_augroup_by_name, "TabiDefaultSession")
end

return M
