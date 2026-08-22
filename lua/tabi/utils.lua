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

--- Check whether two paths refer to the same file, tolerating symlink
--- differences (e.g. macOS's /tmp -> /private/tmp) that can make Neovim
--- report a different buffer name than the path a note was created with.
--- Falls back to plain absolute-path comparison when either side can't be
--- resolved (e.g. the file was deleted after a note was created for it).
---@param a string
---@param b string
---@return boolean
function M.paths_equal(a, b)
  if a == b then
    return true
  end
  local real_a = vim.loop.fs_realpath(a)
  local real_b = vim.loop.fs_realpath(b)
  if real_a and real_b then
    return real_a == real_b
  end
  return vim.fn.fnamemodify(a, ":p") == vim.fn.fnamemodify(b, ":p")
end

--- Find the buffer number for a path, falling back to its resolved realpath
--- (e.g. macOS's /tmp -> /private/tmp) if a direct lookup doesn't match.
---@param path string
---@return number bufnr -1 if not found
function M.find_bufnr(path)
  local bufnr = vim.fn.bufnr(path)
  if bufnr ~= -1 then
    return bufnr
  end

  local realpath = vim.loop.fs_realpath(path)
  if realpath and realpath ~= path then
    return vim.fn.bufnr(realpath)
  end

  return -1
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
