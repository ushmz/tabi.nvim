---@class WanderDisplay
local M = {}

local config = require("wander.config")
local note_module = require("wander.note")

-- Namespace for virtual text and signs
local ns = vim.api.nvim_create_namespace("wander")

-- Sign name
local SIGN_NAME = "WanderNote"

--- Initialize display (set up signs)
function M.init()
  -- Define sign
  vim.fn.sign_define(SIGN_NAME, {
    text = "", -- Use icon or fallback
    texthl = "WanderNoteSign",
    numhl = "WanderLineNr",
  })
end

--- Clear all displays in a buffer
---@param bufnr number
function M.clear_buffer(bufnr)
  -- Clear virtual text
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

  -- Clear signs
  vim.fn.sign_unplace("wander", { buffer = bufnr })
end

--- Display a note in the buffer
---@param bufnr number
---@param note NoteData
function M.display_note(bufnr, note)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local cfg = config.get()
  local line = note.line - 1 -- 0-indexed for API

  -- Add sign
  if cfg.ui.use_icons then
    vim.fn.sign_place(0, "wander", SIGN_NAME, bufnr, {
      lnum = note.line,
      priority = 10,
    })
  end

  -- Add virtual text with preview
  local preview = note_module.get_preview(note, cfg.ui.note_preview_length)
  if preview and preview ~= "" then
    vim.api.nvim_buf_set_extmark(bufnr, ns, line, 0, {
      virt_text = { { " " .. preview, "WanderNote" } },
      virt_text_pos = "eol",
    })
  end
end

--- Refresh display for all notes in a file
---@param bufnr number
---@param notes NoteData[]
function M.refresh_buffer(bufnr, notes)
  M.clear_buffer(bufnr)

  for _, note in ipairs(notes) do
    M.display_note(bufnr, note)
  end
end

--- Update display when entering a buffer
---@param bufnr number
---@param session SessionData
function M.update_for_session(bufnr, session)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local file_path = vim.api.nvim_buf_get_name(bufnr)
  if file_path == "" then
    return
  end

  local session_module = require("wander.session")
  local notes = session_module.get_notes_for_file(session, file_path)

  M.refresh_buffer(bufnr, notes)
end

--- Set up autocommands for automatic display updates
---@param session SessionData
function M.setup_autocmds(session)
  local group = vim.api.nvim_create_augroup("WanderDisplay", { clear = true })

  -- Update display when entering a buffer
  vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
    group = group,
    callback = function(args)
      M.update_for_session(args.buf, session)
    end,
  })

  -- Clear display when leaving
  vim.api.nvim_create_autocmd("BufLeave", {
    group = group,
    callback = function()
      -- Optionally keep display visible
      -- M.clear_buffer(args.buf)
    end,
  })
end

--- Clear all autocommands
function M.clear_autocmds()
  vim.api.nvim_clear_autocmds({ group = "WanderDisplay" })
end

return M
