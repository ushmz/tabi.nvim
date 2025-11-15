---@class WanderUtils
local M = {}

--- Generate a UUID v4
---@return string
function M.uuid()
  local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
  return string.gsub(template, '[xy]', function(c)
    local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
    return string.format('%x', v)
  end)
end

--- Get current timestamp in ISO 8601 format
---@return string
function M.timestamp()
  return os.date('!%Y-%m-%dT%H:%M:%SZ')
end

--- Get current git branch
---@return string|nil
function M.get_git_branch()
  local handle = io.popen('git rev-parse --abbrev-ref HEAD 2>/dev/null')
  if not handle then
    return nil
  end
  local branch = handle:read('*a')
  handle:close()
  return branch and vim.trim(branch) or nil
end

--- Check if in git repository
---@return boolean
function M.is_git_repo()
  local handle = io.popen('git rev-parse --git-dir 2>/dev/null')
  if not handle then
    return false
  end
  local result = handle:read('*a')
  handle:close()
  return result ~= ''
end

--- Get git root directory
---@return string|nil
function M.get_git_root()
  local handle = io.popen('git rev-parse --show-toplevel 2>/dev/null')
  if not handle then
    return nil
  end
  local root = handle:read('*a')
  handle:close()
  return root and vim.trim(root) or nil
end

--- Ensure directory exists
---@param path string
function M.ensure_dir(path)
  local stat = vim.loop.fs_stat(path)
  if not stat then
    vim.fn.mkdir(path, 'p')
  end
end

--- Get relative path from base
---@param path string
---@param base string
---@return string
function M.relative_path(path, base)
  local base_parts = vim.split(base, '/', { plain = true })
  local path_parts = vim.split(path, '/', { plain = true })

  local i = 1
  while i <= #base_parts and i <= #path_parts and base_parts[i] == path_parts[i] do
    i = i + 1
  end

  local result = {}
  for _ = i, #base_parts do
    table.insert(result, '..')
  end
  for j = i, #path_parts do
    table.insert(result, path_parts[j])
  end

  return table.concat(result, '/')
end

return M
