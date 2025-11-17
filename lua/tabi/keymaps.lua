---@class TabiKeymaps
local M = {}

--- Setup keymaps based on configuration
function M.setup()
  local config = require("tabi.config").get()
  local keymaps = config.keymaps

  if not keymaps.enabled then
    return
  end

  local opts = { silent = true }

  -- Session management
  if keymaps.start then
    vim.keymap.set(
      "n",
      keymaps.start,
      "<Cmd>Tabi start<CR>",
      vim.tbl_extend("force", opts, {
        desc = "Tabi: Start session",
      })
    )
  end

  if keymaps["end"] then
    vim.keymap.set(
      "n",
      keymaps["end"],
      "<Cmd>Tabi end<CR>",
      vim.tbl_extend("force", opts, {
        desc = "Tabi: End session",
      })
    )
  end

  if keymaps.sessions then
    vim.keymap.set(
      "n",
      keymaps.sessions,
      "<Cmd>Tabi sessions<CR>",
      vim.tbl_extend("force", opts, {
        desc = "Tabi: List sessions",
      })
    )
  end

  -- Note operations
  if keymaps.note then
    vim.keymap.set(
      "n",
      keymaps.note,
      "<Cmd>Tabi note<CR>",
      vim.tbl_extend("force", opts, {
        desc = "Tabi: Add/edit note",
      })
    )
    vim.keymap.set(
      "v",
      keymaps.note,
      ":Tabi note<CR>",
      vim.tbl_extend("force", opts, {
        desc = "Tabi: Add note for selection",
      })
    )
  end

  if keymaps.note_delete then
    vim.keymap.set(
      "n",
      keymaps.note_delete,
      "<Cmd>Tabi note delete<CR>",
      vim.tbl_extend("force", opts, {
        desc = "Tabi: Delete note",
      })
    )
  end

  -- Retrace mode
  if keymaps.retrace then
    vim.keymap.set(
      "n",
      keymaps.retrace,
      "<Cmd>Tabi retrace<CR>",
      vim.tbl_extend("force", opts, {
        desc = "Tabi: Start retrace",
      })
    )
  end

  if keymaps.retrace_end then
    vim.keymap.set(
      "n",
      keymaps.retrace_end,
      "<Cmd>Tabi retrace end<CR>",
      vim.tbl_extend("force", opts, {
        desc = "Tabi: Quit retrace",
      })
    )
  end
end

return M
