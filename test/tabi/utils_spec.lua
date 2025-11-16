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
