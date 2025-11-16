---@class TabiFloat
local M = {}

local config = require("tabi.config")

--- Create a centered floating window
---@param opts table|nil Options for the floating window
---@return number bufnr
---@return number winid
function M.create_float(opts)
  opts = opts or {}
  local cfg = config.get()

  -- Get dimensions from config or opts
  local width = opts.width or cfg.ui.float_config.width
  local height = opts.height or cfg.ui.float_config.height
  local border = opts.border or cfg.ui.float_config.border

  -- Calculate position
  local ui = vim.api.nvim_list_uis()[1]
  local win_width = ui.width
  local win_height = ui.height

  local row = math.floor((win_height - height) / 2)
  local col = math.floor((win_width - width) / 2)

  -- Create buffer
  local bufnr = vim.api.nvim_create_buf(false, true) -- not listed, scratch buffer

  -- Window options
  local win_opts = {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = border,
  }

  -- Create window
  local winid = vim.api.nvim_open_win(bufnr, true, win_opts)

  -- Set buffer options
  vim.api.nvim_buf_set_option(bufnr, "buftype", "acwrite")
  vim.api.nvim_buf_set_option(bufnr, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(bufnr, "filetype", "markdown")

  return bufnr, winid
end

--- Open a note editor
---@param initial_content string|nil Initial content
---@param on_save function Callback when note is saved
---@param on_cancel function|nil Callback when cancelled
function M.open_note_editor(initial_content, on_save, on_cancel)
  local bufnr, winid = M.create_float()

  -- Set initial content
  if initial_content and initial_content ~= "" then
    local lines = vim.split(initial_content, "\n")
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  end

  -- Add title as comment
  vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, {
    "<!-- Write your note here (markdown format) -->",
    "<!-- Save: <C-s> or :w | Cancel: <Esc> or :q -->",
    "",
  })

  -- Start insert mode at the end
  vim.cmd("startinsert")

  -- Move cursor to after the comments
  vim.api.nvim_win_set_cursor(winid, { 4, 0 })

  -- Save function
  local function save()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    -- Remove comment lines
    local content_lines = {}
    for _, line in ipairs(lines) do
      if not line:match("^<!%-%-") then
        table.insert(content_lines, line)
      end
    end

    local content = table.concat(content_lines, "\n")
    content = vim.trim(content)

    vim.api.nvim_win_close(winid, true)

    if on_save then
      on_save(content)
    end
  end

  -- Cancel function
  local function cancel()
    if vim.api.nvim_win_is_valid(winid) then
      vim.api.nvim_win_close(winid, true)
    end

    if on_cancel then
      on_cancel()
    end
  end

  -- Set up keymaps
  local keymap_opts = { noremap = true, silent = true, buffer = bufnr }

  vim.keymap.set("n", "<Esc>", cancel, keymap_opts)
  vim.keymap.set("n", "q", cancel, keymap_opts)
  vim.keymap.set("n", "<C-s>", save, keymap_opts)
  vim.keymap.set("i", "<C-s>", save, keymap_opts)

  -- Set up autocmd to save on :w
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = bufnr,
    callback = function()
      save()
    end,
  })

  -- Set up autocmd to cancel on window close
  vim.api.nvim_create_autocmd("WinClosed", {
    buffer = bufnr,
    once = true,
    callback = function()
      -- Clean up if window was closed without save/cancel
      if on_cancel and vim.api.nvim_buf_is_valid(bufnr) then
        on_cancel()
      end
    end,
  })
end

return M
