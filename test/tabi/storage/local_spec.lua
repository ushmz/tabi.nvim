local local_storage = require("tabi.storage.local")
local utils = require("tabi.utils")

describe("tabi.storage.local", function()
  local temp_dir
  local original_get_git_root
  local original_is_git_repo

  before_each(function()
    -- Create temporary directory to simulate git repo
    temp_dir = vim.fn.tempname() .. "_tabi_local_test"
    vim.fn.mkdir(temp_dir .. "/.git", "p")

    -- Mock git functions
    original_get_git_root = utils.get_git_root
    original_is_git_repo = utils.is_git_repo

    utils.get_git_root = function()
      return temp_dir
    end

    utils.is_git_repo = function()
      return true
    end
  end)

  after_each(function()
    -- Restore original functions
    utils.get_git_root = original_get_git_root
    utils.is_git_repo = original_is_git_repo

    -- Clean up temporary directory
    if vim.fn.isdirectory(temp_dir) == 1 then
      vim.fn.delete(temp_dir, "rf")
    end
  end)

  describe("get_storage_dir", function()
    it("should return .git/tabi path", function()
      local dir = local_storage.get_storage_dir()
      assert.are.equal(temp_dir .. "/.git/tabi", dir)
    end)

    it("should return nil when not in git repo", function()
      utils.get_git_root = function()
        return nil
      end
      local dir = local_storage.get_storage_dir()
      assert.is_nil(dir)
    end)
  end)

  describe("get_sessions_dir", function()
    it("should return .git/tabi/sessions path", function()
      local dir = local_storage.get_sessions_dir()
      assert.are.equal(temp_dir .. "/.git/tabi/sessions", dir)
    end)

    it("should return nil when not in git repo", function()
      utils.get_git_root = function()
        return nil
      end
      local dir = local_storage.get_sessions_dir()
      assert.is_nil(dir)
    end)
  end)

  describe("init", function()
    it("should create .git/tabi/sessions directory", function()
      local sessions_dir = local_storage.get_sessions_dir()
      assert.are.equal(0, vim.fn.isdirectory(sessions_dir))

      local_storage.init()

      assert.are.equal(1, vim.fn.isdirectory(sessions_dir))
    end)

    it("should not fail when directory already exists", function()
      local sessions_dir = local_storage.get_sessions_dir()
      vim.fn.mkdir(sessions_dir, "p")

      -- Should not throw error
      local_storage.init()

      assert.are.equal(1, vim.fn.isdirectory(sessions_dir))
    end)
  end)

  describe("save_session", function()
    before_each(function()
      local_storage.init()
    end)

    it("should create JSON file", function()
      local session = {
        id = "test-session-id",
        name = "test-session",
        created_at = "2025-01-01T00:00:00Z",
        updated_at = "2025-01-01T00:00:00Z",
        notes = {},
      }

      local result = local_storage.save_session(session)

      assert.is_true(result)
      local file_path = local_storage.get_sessions_dir() .. "/test-session-id.json"
      assert.are.equal(1, vim.fn.filereadable(file_path))
    end)

    it("should save valid JSON format", function()
      local session = {
        id = "json-test",
        name = "JSON Test",
        created_at = "2025-01-01T00:00:00Z",
        updated_at = "2025-01-01T00:00:00Z",
        notes = {
          {
            id = "note-1",
            file = "/test.lua",
            line = 10,
            content = "Test note",
            created_at = "2025-01-01T00:00:00Z",
          },
        },
      }

      local_storage.save_session(session)

      local file_path = local_storage.get_sessions_dir() .. "/json-test.json"
      local file = io.open(file_path, "r")
      local content = file:read("*a")
      file:close()

      local ok, decoded = pcall(vim.json.decode, content)
      assert.is_true(ok)
      assert.are.equal("JSON Test", decoded.name)
      assert.are.equal(1, #decoded.notes)
    end)

    it("should overwrite existing file", function()
      local session = {
        id = "overwrite-test",
        name = "Original",
        created_at = "2025-01-01T00:00:00Z",
        updated_at = "2025-01-01T00:00:00Z",
        notes = {},
      }

      local_storage.save_session(session)

      session.name = "Modified"
      local_storage.save_session(session)

      local loaded = local_storage.load_session("overwrite-test")
      assert.are.equal("Modified", loaded.name)
    end)
  end)

  describe("load_session", function()
    before_each(function()
      local_storage.init()
    end)

    it("should parse JSON correctly", function()
      local session = {
        id = "load-test",
        name = "Load Test",
        created_at = "2025-01-01T00:00:00Z",
        updated_at = "2025-01-01T00:00:00Z",
        notes = {},
      }

      local_storage.save_session(session)
      local loaded = local_storage.load_session("load-test")

      assert.is_not_nil(loaded)
      assert.are.equal("load-test", loaded.id)
      assert.are.equal("Load Test", loaded.name)
    end)

    it("should return nil for non-existent file", function()
      local loaded = local_storage.load_session("non-existent")
      assert.is_nil(loaded)
    end)

    it("should return nil for corrupted JSON", function()
      local sessions_dir = local_storage.get_sessions_dir()
      local file_path = sessions_dir .. "/corrupted.json"
      local file = io.open(file_path, "w")
      file:write("this is not valid json {")
      file:close()

      local loaded = local_storage.load_session("corrupted")
      assert.is_nil(loaded)
    end)
  end)

  describe("list_sessions", function()
    before_each(function()
      local_storage.init()
    end)

    it("should return all JSON files as sessions", function()
      local session1 = {
        id = "session-1",
        name = "Session 1",
        created_at = "2025-01-01T00:00:00Z",
        updated_at = "2025-01-01T00:00:00Z",
        notes = {},
      }
      local session2 = {
        id = "session-2",
        name = "Session 2",
        created_at = "2025-01-01T00:00:00Z",
        updated_at = "2025-01-02T00:00:00Z",
        notes = {},
      }

      local_storage.save_session(session1)
      local_storage.save_session(session2)

      local sessions = local_storage.list_sessions()
      assert.are.equal(2, #sessions)
    end)

    it("should sort by updated_at descending", function()
      local session1 = {
        id = "old",
        name = "Old Session",
        created_at = "2025-01-01T00:00:00Z",
        updated_at = "2025-01-01T00:00:00Z",
        notes = {},
      }
      local session2 = {
        id = "new",
        name = "New Session",
        created_at = "2025-01-01T00:00:00Z",
        updated_at = "2025-01-02T00:00:00Z",
        notes = {},
      }

      local_storage.save_session(session1)
      local_storage.save_session(session2)

      local sessions = local_storage.list_sessions()
      assert.are.equal("new", sessions[1].id)
      assert.are.equal("old", sessions[2].id)
    end)

    it("should return empty array when no sessions", function()
      local sessions = local_storage.list_sessions()
      assert.is_table(sessions)
      assert.are.equal(0, #sessions)
    end)

    it("should skip non-JSON files", function()
      local session = {
        id = "valid",
        name = "Valid Session",
        created_at = "2025-01-01T00:00:00Z",
        updated_at = "2025-01-01T00:00:00Z",
        notes = {},
      }
      local_storage.save_session(session)

      -- Create non-JSON file
      local sessions_dir = local_storage.get_sessions_dir()
      local file = io.open(sessions_dir .. "/readme.txt", "w")
      file:write("This is not a session file")
      file:close()

      local sessions = local_storage.list_sessions()
      assert.are.equal(1, #sessions)
      assert.are.equal("valid", sessions[1].id)
    end)
  end)

  describe("delete_session", function()
    before_each(function()
      local_storage.init()
    end)

    it("should delete file", function()
      local session = {
        id = "to-delete",
        name = "Delete Me",
        created_at = "2025-01-01T00:00:00Z",
        updated_at = "2025-01-01T00:00:00Z",
        notes = {},
      }

      local_storage.save_session(session)
      assert.is_true(local_storage.session_exists("to-delete"))

      local result = local_storage.delete_session("to-delete")
      assert.is_true(result)
      assert.is_false(local_storage.session_exists("to-delete"))
    end)

    it("should return false for non-existent file", function()
      local result = local_storage.delete_session("non-existent")
      assert.is_false(result)
    end)
  end)

  describe("session_exists", function()
    before_each(function()
      local_storage.init()
    end)

    it("should return true when file exists", function()
      local session = {
        id = "exists",
        name = "Exists",
        created_at = "2025-01-01T00:00:00Z",
        updated_at = "2025-01-01T00:00:00Z",
        notes = {},
      }

      local_storage.save_session(session)
      assert.is_true(local_storage.session_exists("exists"))
    end)

    it("should return false when file does not exist", function()
      assert.is_false(local_storage.session_exists("non-existent"))
    end)
  end)
end)
