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
    -- Add first line of note content
    local first_line = note.content:match("^[^\n]+") or note.content
    if #first_line > 60 then
      first_line = first_line:sub(1, 57) .. "..."
    end
    table.insert(lines, "   " .. first_line)
    table.insert(lines, "")
  end

  return lines
end

return M
