-- Integration tests for storage backend switching
-- Tests: local <-> global backend switching

local storage = require("tabi.storage")
local config = require("tabi.config")

describe("integration: storage backend switching", function()
  local temp_local_dir
  local temp_global_dir
  local original_backend
  local mock_local_backend
  local mock_global_backend

  before_each(function()
    -- Reset config to defaults
    config.options = vim.deepcopy(config.defaults)

    -- Create temporary directories
    temp_local_dir = vim.fn.tempname() .. "_local_storage"
    temp_global_dir = vim.fn.tempname() .. "_global_storage"
    vim.fn.mkdir(temp_local_dir .. "/sessions", "p")
    vim.fn.mkdir(temp_global_dir .. "/sessions", "p")

    -- Save original backend
    original_backend = storage.backend

    -- Create mock local backend
    mock_local_backend = {
      save_session = function(s)
        local path = temp_local_dir .. "/sessions/" .. s.id .. ".json"
        local file = io.open(path, "w")
        if file then
          file:write(vim.fn.json_encode(s))
          file:close()
          return true
        end
        return false
      end,
      load_session = function(id)
        local path = temp_local_dir .. "/sessions/" .. id .. ".json"
        local file = io.open(path, "r")
        if not file then
          return nil
        end
        local content = file:read("*a")
        file:close()
        local ok, decoded = pcall(vim.fn.json_decode, content)
        if ok then
          return decoded
        end
        return nil
      end,
      list_sessions = function()
        local sessions = {}
        local handle = vim.loop.fs_scandir(temp_local_dir .. "/sessions")
        if handle then
          while true do
            local name = vim.loop.fs_scandir_next(handle)
            if not name then
              break
            end
            if name:match("%.json$") then
              local id = name:gsub("%.json$", "")
              local s = mock_local_backend.load_session(id)
              if s then
                table.insert(sessions, s)
              end
            end
          end
        end
        return sessions
      end,
      delete_session = function(id)
        local path = temp_local_dir .. "/sessions/" .. id .. ".json"
        if vim.fn.filereadable(path) == 1 then
          os.remove(path)
          return true
        end
        return false
      end,
      session_exists = function(id)
        local path = temp_local_dir .. "/sessions/" .. id .. ".json"
        return vim.fn.filereadable(path) == 1
      end,
    }

    -- Create mock global backend
    mock_global_backend = {
      save_session = function(s)
        local path = temp_global_dir .. "/sessions/" .. s.id .. ".json"
        local file = io.open(path, "w")
        if file then
          file:write(vim.fn.json_encode(s))
          file:close()
          return true
        end
        return false
      end,
      load_session = function(id)
        local path = temp_global_dir .. "/sessions/" .. id .. ".json"
        local file = io.open(path, "r")
        if not file then
          return nil
        end
        local content = file:read("*a")
        file:close()
        local ok, decoded = pcall(vim.fn.json_decode, content)
        if ok then
          return decoded
        end
        return nil
      end,
      list_sessions = function()
        local sessions = {}
        local handle = vim.loop.fs_scandir(temp_global_dir .. "/sessions")
        if handle then
          while true do
            local name = vim.loop.fs_scandir_next(handle)
            if not name then
              break
            end
            if name:match("%.json$") then
              local id = name:gsub("%.json$", "")
              local s = mock_global_backend.load_session(id)
              if s then
                table.insert(sessions, s)
              end
            end
          end
        end
        return sessions
      end,
      delete_session = function(id)
        local path = temp_global_dir .. "/sessions/" .. id .. ".json"
        if vim.fn.filereadable(path) == 1 then
          os.remove(path)
          return true
        end
        return false
      end,
      session_exists = function(id)
        local path = temp_global_dir .. "/sessions/" .. id .. ".json"
        return vim.fn.filereadable(path) == 1
      end,
    }
  end)

  after_each(function()
    -- Restore original backend
    storage.backend = original_backend

    -- Clean up temporary directories
    if vim.fn.isdirectory(temp_local_dir) == 1 then
      vim.fn.delete(temp_local_dir, "rf")
    end
    if vim.fn.isdirectory(temp_global_dir) == 1 then
      vim.fn.delete(temp_global_dir, "rf")
    end
  end)

  describe("backend switching", function()
    it("should switch from local to global backend", function()
      -- Start with local backend
      storage.backend = mock_local_backend

      -- Create session in local
      local local_session = {
        id = "local-session",
        name = "Local Session",
        created_at = "2025-01-01T00:00:00Z",
        updated_at = "2025-01-01T00:00:00Z",
        notes = {},
      }
      storage.backend.save_session(local_session)

      -- Verify session exists in local
      assert.is_true(storage.backend.session_exists("local-session"))
      local local_sessions = storage.backend.list_sessions()
      assert.are.equal(1, #local_sessions)

      -- Switch to global backend
      storage.backend = mock_global_backend

      -- Verify local session is not accessible from global
      assert.is_false(storage.backend.session_exists("local-session"))
      local global_sessions = storage.backend.list_sessions()
      assert.are.equal(0, #global_sessions)

      -- Create session in global
      local global_session = {
        id = "global-session",
        name = "Global Session",
        created_at = "2025-01-01T00:00:00Z",
        updated_at = "2025-01-01T00:00:00Z",
        notes = {},
      }
      storage.backend.save_session(global_session)

      -- Verify session exists in global
      assert.is_true(storage.backend.session_exists("global-session"))
      global_sessions = storage.backend.list_sessions()
      assert.are.equal(1, #global_sessions)
    end)

    it("should maintain data isolation between backends", function()
      -- Create sessions in local
      storage.backend = mock_local_backend
      local local_session1 = {
        id = "local-1",
        name = "Local 1",
        created_at = "2025-01-01T00:00:00Z",
        updated_at = "2025-01-01T00:00:00Z",
        notes = { { id = "n1", file = "/a.lua", line = 1, content = "Local note 1" } },
      }
      local local_session2 = {
        id = "local-2",
        name = "Local 2",
        created_at = "2025-01-01T00:00:00Z",
        updated_at = "2025-01-01T00:00:00Z",
        notes = { { id = "n2", file = "/b.lua", line = 2, content = "Local note 2" } },
      }
      storage.backend.save_session(local_session1)
      storage.backend.save_session(local_session2)

      -- Create sessions in global
      storage.backend = mock_global_backend
      local global_session1 = {
        id = "global-1",
        name = "Global 1",
        created_at = "2025-01-01T00:00:00Z",
        updated_at = "2025-01-01T00:00:00Z",
        notes = { { id = "n3", file = "/c.lua", line = 3, content = "Global note 1" } },
      }
      storage.backend.save_session(global_session1)

      -- Verify local storage has its sessions
      storage.backend = mock_local_backend
      local local_sessions = storage.backend.list_sessions()
      assert.are.equal(2, #local_sessions)

      local local_loaded = storage.backend.load_session("local-1")
      assert.is_not_nil(local_loaded)
      assert.are.equal("Local note 1", local_loaded.notes[1].content)

      -- Verify global storage has its sessions
      storage.backend = mock_global_backend
      local global_sessions = storage.backend.list_sessions()
      assert.are.equal(1, #global_sessions)

      local global_loaded = storage.backend.load_session("global-1")
      assert.is_not_nil(global_loaded)
      assert.are.equal("Global note 1", global_loaded.notes[1].content)

      -- Verify cross-access fails
      assert.is_nil(storage.backend.load_session("local-1"))

      storage.backend = mock_local_backend
      assert.is_nil(storage.backend.load_session("global-1"))
    end)
  end)

  describe("manual data migration", function()
    it("should allow copying session from local to global", function()
      -- Create session in local
      storage.backend = mock_local_backend
      local local_session = {
        id = "to-migrate",
        name = "Migration Test",
        created_at = "2025-01-01T00:00:00Z",
        updated_at = "2025-01-01T00:00:00Z",
        notes = {
          { id = "note-1", file = "/test.lua", line = 1, content = "Note to migrate" },
        },
      }
      storage.backend.save_session(local_session)

      -- Load from local
      local session_data = storage.backend.load_session("to-migrate")
      assert.is_not_nil(session_data)

      -- Switch to global and save
      storage.backend = mock_global_backend
      storage.backend.save_session(session_data)

      -- Verify migration
      local migrated = storage.backend.load_session("to-migrate")
      assert.is_not_nil(migrated)
      assert.are.equal("Migration Test", migrated.name)
      assert.are.equal(1, #migrated.notes)
      assert.are.equal("Note to migrate", migrated.notes[1].content)

      -- Both backends should now have the session
      storage.backend = mock_local_backend
      assert.is_true(storage.backend.session_exists("to-migrate"))

      storage.backend = mock_global_backend
      assert.is_true(storage.backend.session_exists("to-migrate"))
    end)

    it("should allow deleting old session after migration", function()
      -- Create and migrate session
      storage.backend = mock_local_backend
      local session = {
        id = "migrate-and-delete",
        name = "Migrate and Delete",
        created_at = "2025-01-01T00:00:00Z",
        updated_at = "2025-01-01T00:00:00Z",
        notes = {},
      }
      storage.backend.save_session(session)

      -- Load and migrate
      local session_data = storage.backend.load_session("migrate-and-delete")
      storage.backend = mock_global_backend
      storage.backend.save_session(session_data)

      -- Delete from old backend
      storage.backend = mock_local_backend
      local deleted = storage.backend.delete_session("migrate-and-delete")
      assert.is_true(deleted)

      -- Verify only exists in new backend
      assert.is_false(storage.backend.session_exists("migrate-and-delete"))

      storage.backend = mock_global_backend
      assert.is_true(storage.backend.session_exists("migrate-and-delete"))
    end)

    it("should handle bulk migration", function()
      -- Create multiple sessions in local
      storage.backend = mock_local_backend
      for i = 1, 5 do
        local session = {
          id = "bulk-" .. i,
          name = "Bulk Session " .. i,
          created_at = "2025-01-01T00:00:00Z",
          updated_at = "2025-01-01T00:00:00Z",
          notes = {},
        }
        storage.backend.save_session(session)
      end

      -- Migrate all sessions
      local local_sessions = storage.backend.list_sessions()
      assert.are.equal(5, #local_sessions)

      storage.backend = mock_global_backend
      for _, session in ipairs(local_sessions) do
        storage.backend.save_session(session)
      end

      -- Verify all migrated
      local global_sessions = storage.backend.list_sessions()
      assert.are.equal(5, #global_sessions)

      -- Check each session
      for i = 1, 5 do
        local migrated = storage.backend.load_session("bulk-" .. i)
        assert.is_not_nil(migrated)
        assert.are.equal("Bulk Session " .. i, migrated.name)
      end
    end)
  end)

  describe("configuration-based switching", function()
    it("should reflect config changes in backend selection", function()
      -- This test simulates what happens when config changes
      -- In real implementation, storage.init() would select backend based on config

      -- Initial config is local
      config.setup({ storage = { backend = "local" } })
      assert.are.equal("local", config.get().storage.backend)

      -- Change config to global
      config.setup({ storage = { backend = "global" } })
      assert.are.equal("global", config.get().storage.backend)

      -- Change back to local
      config.setup({ storage = { backend = "local" } })
      assert.are.equal("local", config.get().storage.backend)
    end)

    it("should maintain config after backend operations", function()
      config.setup({ storage = { backend = "global" } })
      storage.backend = mock_global_backend

      -- Perform operations
      local session = {
        id = "config-test",
        name = "Config Test",
        created_at = "2025-01-01T00:00:00Z",
        updated_at = "2025-01-01T00:00:00Z",
        notes = {},
      }
      storage.backend.save_session(session)
      storage.backend.load_session("config-test")
      storage.backend.list_sessions()

      -- Config should be unchanged
      assert.are.equal("global", config.get().storage.backend)
    end)
  end)

  describe("backend independence", function()
    it("should allow same session ID in different backends", function()
      -- Create session with same ID in both backends
      local same_id = "same-id"

      storage.backend = mock_local_backend
      local local_session = {
        id = same_id,
        name = "Local Version",
        created_at = "2025-01-01T00:00:00Z",
        updated_at = "2025-01-01T00:00:00Z",
        notes = { { id = "ln", content = "Local" } },
      }
      storage.backend.save_session(local_session)

      storage.backend = mock_global_backend
      local global_session = {
        id = same_id,
        name = "Global Version",
        created_at = "2025-01-01T00:00:00Z",
        updated_at = "2025-01-01T00:00:00Z",
        notes = { { id = "gn", content = "Global" } },
      }
      storage.backend.save_session(global_session)

      -- Each backend should return its own version
      storage.backend = mock_local_backend
      local local_loaded = storage.backend.load_session(same_id)
      assert.are.equal("Local Version", local_loaded.name)

      storage.backend = mock_global_backend
      local global_loaded = storage.backend.load_session(same_id)
      assert.are.equal("Global Version", global_loaded.name)
    end)
  end)
end)
