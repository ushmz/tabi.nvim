---@class TabiUtils
local M = {}

--- Generate a UUID v4
---@return string
function M.uuid()
  local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
  return string.gsub(template, "[xy]", function(c)
    local v = (c == "x") and math.random(0, 0xf) or math.random(8, 0xb)
    return string.format("%x", v)
  end)
end

--- Get current timestamp in ISO 8601 format
---@return string
function M.timestamp()
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

--- Convert a UTC timestamp in ISO 8601 format to Unix epoch seconds
--- (strptime()/os.time() would interpret it as local time)
---@param iso string ISO 8601 timestamp in UTC (e.g. "2024-01-01T00:00:00Z")
---@return integer|nil
function M.parse_timestamp(iso)
  local y, m, d, hour, min, sec = iso:match("^(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)Z$")
  if not y then
    return nil
  end
  y, m, d = tonumber(y), tonumber(m), tonumber(d)

  -- Days since 1970-01-01 in the proleptic Gregorian calendar
  y = m <= 2 and y - 1 or y
  local era = math.floor(y / 400)
  local yoe = y - era * 400
  local doy = math.floor((153 * ((m + 9) % 12) + 2) / 5) + d - 1
  local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
  local days = era * 146097 + doe - 719468

  return days * 86400 + tonumber(hour) * 3600 + tonumber(min) * 60 + tonumber(sec)
end

--- Format an ISO 8601 timestamp (as produced by `timestamp()`) in local time for display
---@param iso string ISO 8601 timestamp in UTC
---@param fmt string strftime-style format
---@return string Formatted time, or `iso` unchanged if it cannot be parsed
function M.format_timestamp(iso, fmt)
  local epoch = M.parse_timestamp(iso)
  if not epoch then
    return iso
  end
  return os.date(fmt, epoch) --[[@as string]]
end

--- Get current git branch
---@return string|nil
function M.get_git_branch()
  local handle = io.popen("git rev-parse --abbrev-ref HEAD 2>/dev/null")
  if not handle then
    return nil
  end
  local branch = handle:read("*a")
  handle:close()
  return branch and vim.trim(branch) or nil
end

--- Check if in git repository
---@return boolean
function M.is_git_repo()
  local handle = io.popen("git rev-parse --git-dir 2>/dev/null")
  if not handle then
    return false
  end
  local result = handle:read("*a")
  handle:close()
  return result ~= ""
end

--- Get git root directory
---@return string|nil
function M.get_git_root()
  local handle = io.popen("git rev-parse --show-toplevel 2>/dev/null")
  if not handle then
    return nil
  end
  local root = handle:read("*a")
  handle:close()
  return root and vim.trim(root) or nil
end

--- Get git common directory (resolves git worktree gitfiles to the actual .git directory)
--- In a normal repo, returns the same as .git directory.
--- In a worktree, returns the main repository's .git directory instead of the worktree-specific one.
---@return string|nil
function M.get_git_common_dir()
  local handle = io.popen("git rev-parse --git-common-dir 2>/dev/null")
  if not handle then
    return nil
  end
  local dir = handle:read("*a")
  handle:close()
  if not dir or vim.trim(dir) == "" then
    return nil
  end
  dir = vim.trim(dir)
  -- --git-common-dir may return a relative path; convert to absolute
  if not vim.startswith(dir, "/") then
    local cwd = vim.fn.getcwd()
    dir = cwd .. "/" .. dir
  end
  return dir
end

--- Ensure directory exists
---@param path string
function M.ensure_dir(path)
  local stat = vim.loop.fs_stat(path)
  if not stat then
    vim.fn.mkdir(path, "p")
  end
end

--- Get relative path from base
---@param path string
---@param base string
---@return string
function M.relative_path(path, base)
  local base_parts = vim.split(base, "/", { plain = true })
  local path_parts = vim.split(path, "/", { plain = true })

  local i = 1
  while i <= #base_parts and i <= #path_parts and base_parts[i] == path_parts[i] do
    i = i + 1
  end

  local result = {}
  for _ = i, #base_parts do
    table.insert(result, "..")
  end
  for j = i, #path_parts do
    table.insert(result, path_parts[j])
  end

  return table.concat(result, "/")
end

return M
