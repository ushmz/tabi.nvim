---@class TabiSelectorUtil
local M = {}

--- Build preview lines showing session details and its notes
---@param session TabiSession
---@return string[]
function M.build_preview_lines(session)
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
    -- Add first non-empty line of note content (buffer lines must not contain newlines)
    local first_line = note.content:match("[^\n]+") or ""
    -- Count characters rather than bytes so multibyte text is not cut mid-character
    if vim.fn.strchars(first_line) > 60 then
      first_line = vim.fn.strcharpart(first_line, 0, 57) .. "..."
    end
    table.insert(lines, "   " .. first_line)
    table.insert(lines, "")
  end

  return lines
end

return M
