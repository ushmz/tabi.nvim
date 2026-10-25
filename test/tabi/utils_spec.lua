local utils = require("tabi.utils")

describe("tabi.utils", function()
  describe("uuid", function()
    it("should generate valid UUID v4 format", function()
      local uuid = utils.uuid()
      -- UUID v4 format: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
      local pattern = "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-4%x%x%x%-[89ab]%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"
      assert.is_true(uuid:match(pattern) ~= nil, "UUID should match v4 pattern: " .. uuid)
    end)

    it("should generate unique UUIDs", function()
      local uuids = {}
      for _ = 1, 100 do
        local uuid = utils.uuid()
        assert.is_nil(uuids[uuid], "UUID should be unique")
        uuids[uuid] = true
      end
    end)
  end)

  describe("timestamp", function()
    it("should generate ISO 8601 format", function()
      local ts = utils.timestamp()
      -- ISO 8601 format: YYYY-MM-DDTHH:MM:SSZ
      local pattern = "^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%dZ$"
      assert.is_true(ts:match(pattern) ~= nil, "Timestamp should match ISO 8601: " .. ts)
    end)

    it("should be in UTC", function()
      local ts = utils.timestamp()
      assert.is_true(ts:sub(-1) == "Z", "Timestamp should end with Z (UTC)")
    end)
  end)

  describe("relative_path", function()
    it("should calculate relative path from base", function()
      local base = "/home/user/project"
      local full = "/home/user/project/src/main.lua"
      local result = utils.relative_path(full, base)
      assert.are.equal("src/main.lua", result)
    end)

    it("should handle paths with no common prefix", function()
      local base = "/home/user/project"
      local path = "/opt/lib/module.lua"
      local result = utils.relative_path(path, base)
      -- Goes up 4 levels (/, home, user, project) then down to opt/lib/module.lua
      assert.is_true(result:match("^%.%./") ~= nil, "Should contain .. for parent directories")
    end)

    it("should handle nested directories", function()
      local base = "/home/user/project"
      local full = "/home/user/project/src/lib/utils/helper.lua"
      local result = utils.relative_path(full, base)
      assert.are.equal("src/lib/utils/helper.lua", result)
    end)

    it("should handle sibling directories", function()
      local base = "/home/user/project/src"
      local full = "/home/user/project/test/main_spec.lua"
      local result = utils.relative_path(full, base)
      assert.are.equal("../test/main_spec.lua", result)
    end)
  end)

  describe("get_git_common_dir", function()
    it("should return a non-empty string when in a git repo", function()
      -- This test runs inside the tabi.nvim git repo
      local dir = utils.get_git_common_dir()
      -- May be nil in environments without git, so only assert format when non-nil
      if dir ~= nil then
        assert.is_string(dir)
        assert.is_true(#dir > 0)
        -- Must be an absolute path
        assert.is_true(vim.startswith(dir, "/"), "get_git_common_dir should return an absolute path, got: " .. dir)
      end
    end)
  end)

  describe("paths_equal", function()
    it("should return true for identical strings", function()
      assert.is_true(utils.paths_equal("/foo/bar.lua", "/foo/bar.lua"))
    end)

    it("should return false for unrelated paths", function()
      assert.is_false(utils.paths_equal("/foo/bar.lua", "/foo/baz.lua"))
    end)

    it("should treat a symlinked path and its resolved target as equal", function()
      local dir = vim.fn.tempname()
      vim.fn.mkdir(dir, "p")
      local real_dir = dir .. "/real"
      local link_dir = dir .. "/link"
      vim.fn.mkdir(real_dir, "p")
      vim.loop.fs_symlink(real_dir, link_dir)

      local file = real_dir .. "/note.lua"
      local f = io.open(file, "w")
      f:write("-- test\n")
      f:close()

      local via_symlink = link_dir .. "/note.lua"
      assert.is_true(utils.paths_equal(file, via_symlink))

      vim.fn.delete(dir, "rf")
    end)

    it("should fall back to absolute-path comparison when a file no longer exists", function()
      local missing_a = "/tmp/does-not-exist-a.lua"
      local missing_b = "/tmp/does-not-exist-a.lua"
      assert.is_true(utils.paths_equal(missing_a, missing_b))
      assert.is_false(utils.paths_equal(missing_a, "/tmp/does-not-exist-b.lua"))
    end)
  end)

  describe("find_bufnr", function()
    it("should find an already-loaded buffer by exact path", function()
      local path = vim.fn.tempname() .. "_find_bufnr.lua"
      local bufnr = vim.fn.bufadd(path)
      vim.fn.bufload(bufnr)

      assert.are.equal(bufnr, utils.find_bufnr(path))

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should return -1 when no buffer matches", function()
      assert.are.equal(-1, utils.find_bufnr("/no/such/buffer-should-exist.lua"))
    end)
  end)

  describe("ensure_dir", function()
    local temp_dir

    before_each(function()
      temp_dir = vim.fn.tempname()
    end)

    after_each(function()
      if vim.fn.isdirectory(temp_dir) == 1 then
        vim.fn.delete(temp_dir, "rf")
      end
    end)

    it("should create directory if not exists", function()
      assert.are.equal(0, vim.fn.isdirectory(temp_dir))
      utils.ensure_dir(temp_dir)
      assert.are.equal(1, vim.fn.isdirectory(temp_dir))
    end)

    it("should not fail if directory already exists", function()
      vim.fn.mkdir(temp_dir, "p")
      assert.are.equal(1, vim.fn.isdirectory(temp_dir))
      -- Should not throw error
      utils.ensure_dir(temp_dir)
      assert.are.equal(1, vim.fn.isdirectory(temp_dir))
    end)
  end)
end)
