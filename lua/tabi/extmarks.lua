---@class TabiExtmarks
local M = {}

-- Namespace for position-tracking extmarks (separate from the display namespace)
local ns = vim.api.nvim_create_namespace("tabi_positions")

-- Per-buffer mapping: bufnr -> { [note_id] -> { start_id: number, end_id: number } }
local _buf_marks = {}

--- Register extmarks for a note so its position is tracked across edits
---@param bufnr number
---@param note NoteData
function M.track(bufnr, note)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  if not _buf_marks[bufnr] then
    _buf_marks[bufnr] = {}
  end

  -- Remove stale extmarks for this note before re-creating
  M.untrack(bufnr, note.id)

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local start_row = math.min(note.line - 1, line_count - 1)
  local end_row = math.min((note.end_line or note.line) - 1, line_count - 1)

  local start_id = vim.api.nvim_buf_set_extmark(bufnr, ns, start_row, 0, {})
  local end_id = vim.api.nvim_buf_set_extmark(bufnr, ns, end_row, 0, {})

  _buf_marks[bufnr][note.id] = { start_id = start_id, end_id = end_id }
end

--- Remove extmarks for a specific note
---@param bufnr number
---@param note_id string
function M.untrack(bufnr, note_id)
  if not _buf_marks[bufnr] or not _buf_marks[bufnr][note_id] then
    return
  end
  local ids = _buf_marks[bufnr][note_id]
  pcall(vim.api.nvim_buf_del_extmark, bufnr, ns, ids.start_id)
  pcall(vim.api.nvim_buf_del_extmark, bufnr, ns, ids.end_id)
  _buf_marks[bufnr][note_id] = nil
end

--- Get current positions (1-indexed) for all tracked notes in a buffer
---@param bufnr number
---@return table<string, {line: number, end_line: number}>
function M.get_positions(bufnr)
  if not _buf_marks[bufnr] then
    return {}
  end

  local positions = {}
  for note_id, ids in pairs(_buf_marks[bufnr]) do
    local start_pos = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns, ids.start_id, {})
    local end_pos = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns, ids.end_id, {})

    if start_pos and #start_pos >= 1 and end_pos and #end_pos >= 1 then
      positions[note_id] = {
        line = start_pos[1] + 1, -- convert 0-indexed row to 1-indexed line
        end_line = end_pos[1] + 1,
      }
    end
  end
  return positions
end

--- Clear all extmarks for a buffer and remove it from the tracking table
---@param bufnr number
function M.clear(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  end
  _buf_marks[bufnr] = nil
end

return M
