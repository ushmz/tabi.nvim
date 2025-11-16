local M = {}

--- Setup test environment
function M.setup()
  -- Add project root to runtime path
  local root = vim.fn.getcwd()
  vim.opt.runtimepath:prepend(root)
  vim.opt.runtimepath:append(root .. "/lua")
end

--- Create a temporary directory for tests
---@return string path to temporary directory
function M.create_temp_dir()
  local temp_dir = vim.fn.tempname()
  vim.fn.mkdir(temp_dir, "p")
  return temp_dir
end

--- Remove a directory and its contents
---@param dir string path to directory
function M.remove_dir(dir)
  if vim.fn.isdirectory(dir) == 1 then
    vim.fn.delete(dir, "rf")
  end
end

--- Create a temporary buffer with optional content
---@param content string[]|nil lines to set in buffer
---@return number bufnr
function M.create_temp_buffer(content)
  local bufnr = vim.api.nvim_create_buf(false, true)
  if content then
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content)
  end
  return bufnr
end

--- Create a temporary file with content
---@param content string file content
---@param extension string|nil file extension
---@return string path to temporary file
function M.create_temp_file(content, extension)
  local path = vim.fn.tempname() .. (extension or ".lua")
  local file = io.open(path, "w")
  if file then
    file:write(content)
    file:close()
  end
  return path
end

--- Clean up test artifacts
function M.cleanup()
  -- Clear all buffers except current
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    end
  end
end

-- Initialize helper
M.setup()

return M
