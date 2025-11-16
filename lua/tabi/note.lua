---@class TabiNote
local M = {}

local utils = require("tabi.utils")

---@class NoteData
---@field id string
---@field file string
---@field line number
---@field end_line number|nil
---@field content string
---@field created_at string

--- Create a new note
---@param file_path string
---@param line number
---@param content string
---@param end_line number|nil
---@return NoteData
function M.create(file_path, line, content, end_line)
  return {
    id = utils.uuid(),
    file = file_path,
    line = line,
    end_line = end_line or line,
    content = content or "",
    created_at = utils.timestamp(),
  }
end

--- Get preview text for a note (first N characters)
---@param note NoteData
---@param length number|nil
---@return string
function M.get_preview(note, length)
  length = length or 30
  local content = note.content:gsub("\n", " "):gsub("%s+", " ")
  if #content <= length then
    return content
  end
  return content:sub(1, length) .. "..."
end

--- Check if note is empty
---@param note NoteData
---@return boolean
function M.is_empty(note)
  return note.content == "" or note.content:match("^%s*$") ~= nil
end

--- Get note title (first line of content)
---@param note NoteData
---@return string
function M.get_title(note)
  local first_line = note.content:match("^[^\n]+")
  if not first_line then
    return ""
  end

  -- Remove markdown heading markers
  first_line = first_line:gsub("^#+%s*", "")
  return vim.trim(first_line)
end

--- Format note for display
---@param note NoteData
---@return string
function M.format(note)
  local title = M.get_title(note)
  if title == "" then
    title = M.get_preview(note, 50)
  end

  local file_name = vim.fn.fnamemodify(note.file, ":t")
  local line_info
  if note.end_line and note.end_line ~= note.line then
    line_info = string.format("%d-%d", note.line, note.end_line)
  else
    line_info = tostring(note.line)
  end
  return string.format("%s:%s - %s", file_name, line_info, title)
end

return M
