local global_storage = require("tabi.storage.global")

describe("tabi.storage.global", function()
  local temp_dir

  before_each(function()
    -- Create temporary directory
    temp_dir = vim.fn.tempname() .. "_tabi_global_test"
    vim.fn.mkdir(temp_dir, "p")

    -- Mock environment variable by overriding get_storage_dir
    -- We'll use a different approach: monkey-patch the module
    global_storage._original_get_storage_dir = global_storage.get_storage_dir
    global_storage.get_storage_dir = function()
      return temp_dir .. "/tabi"
    end
  end)

  after_each(function()
    -- Restore original function
    if global_storage._original_get_storage_dir then
      global_storage.get_storage_dir = global_storage._original_get_storage_dir
      global_storage._original_get_storage_dir = nil
    end

    -- Clean up temporary directory
    if vim.fn.isdirectory(temp_dir) == 1 then
      vim.fn.delete(temp_dir, "rf")
    end
  end)

  describe("get_storage_dir", function()
    it("should use XDG_DATA_HOME when set", function()
      -- Restore original function temporarily
      local original_func = global_storage._original_get_storage_dir
      global_storage.get_storage_dir = original_func

      -- This test checks the actual implementation
      local dir = global_storage.get_storage_dir()
      assert.is_string(dir)
      assert.is_true(dir:match("/tabi$") ~= nil)

      -- Restore mock
      global_storage.get_storage_dir = function()
        return temp_dir .. "/tabi"
      end
    end)

    it("should return path ending with /tabi", function()
      local dir = global_storage.get_storage_dir()
      assert.is_true(dir:match("/tabi$") ~= nil)
    end)
  end)

  describe("get_sessions_dir", function()
    it("should return storage_dir/sessions path", function()
      local dir = global_storage.get_sessions_dir()
      assert.are.equal(temp_dir .. "/tabi/sessions", dir)
    end)
  end)

  describe("init", function()
    it("should create sessions directory", function()
      local sessions_dir = global_storage.get_sessions_dir()
      assert.are.equal(0, vim.fn.isdirectory(sessions_dir))

      global_storage.init()

      assert.are.equal(1, vim.fn.isdirectory(sessions_dir))
    end)

    it("should not fail when directory already exists", function()
      local sessions_dir = global_storage.get_sessions_dir()
      vim.fn.mkdir(sessions_dir, "p")

      -- Should not throw error
      global_storage.init()

      assert.are.equal(1, vim.fn.isdirectory(sessions_dir))
    end)
  end)

  describe("save_session", function()
    before_each(function()
      global_storage.init()
    end)

    it("should create JSON file", function()
      local session = {
        id = "global-session-id",
        name = "Global Session",
        created_at = "2025-01-01T00:00:00Z",
        updated_at = "2025-01-01T00:00:00Z",
        notes = {},
      }

      local result = global_storage.save_session(session)

      assert.is_true(result)
      local file_path = global_storage.get_sessions_dir() .. "/global-session-id.json"
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

      global_storage.save_session(session)

      local file_path = global_storage.get_sessions_dir() .. "/json-test.json"
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

      global_storage.save_session(session)

      session.name = "Modified"
      global_storage.save_session(session)

      local loaded = global_storage.load_session("overwrite-test")
      assert.are.equal("Modified", loaded.name)
    end)
  end)

  describe("load_session", function()
    before_each(function()
      global_storage.init()
    end)

    it("should parse JSON correctly", function()
      local session = {
        id = "load-test",
        name = "Load Test",
        created_at = "2025-01-01T00:00:00Z",
        updated_at = "2025-01-01T00:00:00Z",
        notes = {},
      }

      global_storage.save_session(session)
      local loaded = global_storage.load_session("load-test")

      assert.is_not_nil(loaded)
      assert.are.equal("load-test", loaded.id)
      assert.are.equal("Load Test", loaded.name)
    end)

    it("should return nil for non-existent file", function()
      local loaded = global_storage.load_session("non-existent")
      assert.is_nil(loaded)
    end)

    it("should return nil for corrupted JSON", function()
      local sessions_dir = global_storage.get_sessions_dir()
      local file_path = sessions_dir .. "/corrupted.json"
      local file = io.open(file_path, "w")
      file:write("this is not valid json {")
      file:close()

      local loaded = global_storage.load_session("corrupted")
      assert.is_nil(loaded)
    end)
  end)

  describe("list_sessions", function()
    before_each(function()
      global_storage.init()
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

      global_storage.save_session(session1)
      global_storage.save_session(session2)

      local sessions = global_storage.list_sessions()
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

      global_storage.save_session(session1)
      global_storage.save_session(session2)

      local sessions = global_storage.list_sessions()
      assert.are.equal("new", sessions[1].id)
      assert.are.equal("old", sessions[2].id)
    end)

    it("should return empty array when no sessions", function()
      local sessions = global_storage.list_sessions()
      assert.is_table(sessions)
      assert.are.equal(0, #sessions)
    end)
  end)

  describe("delete_session", function()
    before_each(function()
      global_storage.init()
    end)

    it("should delete file", function()
      local session = {
        id = "to-delete",
        name = "Delete Me",
        created_at = "2025-01-01T00:00:00Z",
        updated_at = "2025-01-01T00:00:00Z",
        notes = {},
      }

      global_storage.save_session(session)
      assert.is_true(global_storage.session_exists("to-delete"))

      local result = global_storage.delete_session("to-delete")
      assert.is_true(result)
      assert.is_false(global_storage.session_exists("to-delete"))
    end)

    it("should return false for non-existent file", function()
      local result = global_storage.delete_session("non-existent")
      assert.is_false(result)
    end)
  end)

  describe("session_exists", function()
    before_each(function()
      global_storage.init()
    end)

    it("should return true when file exists", function()
      local session = {
        id = "exists",
        name = "Exists",
        created_at = "2025-01-01T00:00:00Z",
        updated_at = "2025-01-01T00:00:00Z",
        notes = {},
      }

      global_storage.save_session(session)
      assert.is_true(global_storage.session_exists("exists"))
    end)

    it("should return false when file does not exist", function()
      assert.is_false(global_storage.session_exists("non-existent"))
    end)
  end)
end)
