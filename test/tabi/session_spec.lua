local session = require("tabi.session")
local note_module = require("tabi.note")
local storage = require("tabi.storage")

describe("tabi.session", function()
  local temp_dir
  local original_backend

  before_each(function()
    -- Create temporary directory for test storage
    temp_dir = vim.fn.tempname() .. "_tabi_test"
    vim.fn.mkdir(temp_dir .. "/sessions", "p")

    -- Save original backend
    original_backend = storage.backend

    -- Create mock storage backend
    storage.backend = {
      save_session = function(s)
        local path = temp_dir .. "/sessions/" .. s.id .. ".json"
        local file = io.open(path, "w")
        if file then
          file:write(vim.fn.json_encode(s))
          file:close()
          return true
        end
        return false
      end,
      load_session = function(id)
        local path = temp_dir .. "/sessions/" .. id .. ".json"
        local file = io.open(path, "r")
        if not file then
          return nil
        end
        local content = file:read("*a")
        file:close()
        return vim.fn.json_decode(content)
      end,
      list_sessions = function()
        local sessions = {}
        local handle = vim.loop.fs_scandir(temp_dir .. "/sessions")
        if handle then
          while true do
            local name = vim.loop.fs_scandir_next(handle)
            if not name then
              break
            end
            if name:match("%.json$") then
              local id = name:gsub("%.json$", "")
              local s = storage.backend.load_session(id)
              if s then
                table.insert(sessions, s)
              end
            end
          end
        end
        -- Sort by updated_at descending
        table.sort(sessions, function(a, b)
          return a.updated_at > b.updated_at
        end)
        return sessions
      end,
      delete_session = function(id)
        local path = temp_dir .. "/sessions/" .. id .. ".json"
        return os.remove(path) ~= nil
      end,
      session_exists = function(id)
        local path = temp_dir .. "/sessions/" .. id .. ".json"
        return vim.fn.filereadable(path) == 1
      end,
    }
  end)

  after_each(function()
    -- Restore original backend
    storage.backend = original_backend

    -- Clean up temporary directory
    if vim.fn.isdirectory(temp_dir) == 1 then
      vim.fn.delete(temp_dir, "rf")
    end
  end)

  describe("create", function()
    it("should create named session", function()
      local s = session.create("test-session")
      assert.is_not_nil(s)
      assert.are.equal("test-session", s.name)
    end)

    it("should generate UUID for id", function()
      local s = session.create("test")
      local pattern = "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-4%x%x%x%-[89ab]%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"
      assert.is_true(s.id:match(pattern) ~= nil)
    end)

    it("should set timestamps", function()
      local s = session.create("test")
      local pattern = "^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%dZ$"
      assert.is_true(s.created_at:match(pattern) ~= nil)
      assert.is_true(s.updated_at:match(pattern) ~= nil)
    end)

    it("should initialize empty notes array", function()
      local s = session.create("test")
      assert.is_table(s.notes)
      assert.are.equal(0, #s.notes)
    end)

    it("should generate timestamp-based name when not provided", function()
      local s = session.create(nil)
      assert.is_true(s.name:match("^session%-%d%d%d%d%d%d%d%d%-%d%d%d%d%d%d$") ~= nil)
    end)

    it("should return nil when session with same name exists", function()
      session.create("duplicate")
      local s2 = session.create("duplicate")
      assert.is_nil(s2)
    end)
  end)

  describe("load", function()
    it("should load existing session", function()
      local created = session.create("test-load")
      local loaded = session.load(created.id)
      assert.is_not_nil(loaded)
      assert.are.equal(created.id, loaded.id)
      assert.are.equal(created.name, loaded.name)
    end)

    it("should return nil for non-existent id", function()
      local loaded = session.load("non-existent-id")
      assert.is_nil(loaded)
    end)
  end)

  describe("save", function()
    it("should update updated_at timestamp", function()
      local s = session.create("test-save")
      local original_updated = s.updated_at

      -- Wait a bit to ensure timestamp changes
      vim.wait(10)

      session.save(s)
      assert.is_true(s.updated_at >= original_updated)
    end)

    it("should persist changes", function()
      local s = session.create("test-persist")
      s.name = "modified-name"
      session.save(s)

      local loaded = session.load(s.id)
      assert.are.equal("modified-name", loaded.name)
    end)
  end)

  describe("list", function()
    it("should return all sessions", function()
      session.create("session1")
      session.create("session2")
      session.create("session3")

      local sessions = session.list()
      assert.are.equal(3, #sessions)
    end)

    it("should return empty array when no sessions", function()
      local sessions = session.list()
      assert.is_table(sessions)
      assert.are.equal(0, #sessions)
    end)
  end)

  describe("delete", function()
    it("should delete session", function()
      local s = session.create("to-delete")
      local id = s.id

      local result = session.delete(id)
      assert.is_true(result)

      local loaded = session.load(id)
      assert.is_nil(loaded)
    end)
  end)

  describe("rename", function()
    it("should rename session", function()
      local s = session.create("old-name")
      session.rename(s.id, "new-name")

      local loaded = session.load(s.id)
      assert.are.equal("new-name", loaded.name)
    end)

    it("should update timestamp on rename", function()
      local s = session.create("test-rename")
      local original_updated = s.updated_at

      vim.wait(10)
      session.rename(s.id, "renamed")

      local loaded = session.load(s.id)
      assert.is_true(loaded.updated_at >= original_updated)
    end)
  end)

  describe("add_note", function()
    it("should add note and save session", function()
      local s = session.create("test-add-note")
      local n = note_module.create("/test.lua", 10, "Test note")

      session.add_note(s, n)

      assert.are.equal(1, #s.notes)
      assert.are.equal(n.id, s.notes[1].id)

      -- Verify persisted
      local loaded = session.load(s.id)
      assert.are.equal(1, #loaded.notes)
    end)
  end)

  describe("remove_note", function()
    it("should remove note by id", function()
      local s = session.create("test-remove-note")
      local n1 = note_module.create("/test.lua", 10, "Note 1")
      local n2 = note_module.create("/test.lua", 20, "Note 2")

      session.add_note(s, n1)
      session.add_note(s, n2)
      assert.are.equal(2, #s.notes)

      session.remove_note(s, n1.id)
      assert.are.equal(1, #s.notes)
      assert.are.equal(n2.id, s.notes[1].id)
    end)

    it("should return false when note not found", function()
      local s = session.create("test-remove-nonexistent")
      local result = session.remove_note(s, "nonexistent-id")
      assert.is_false(result)
    end)
  end)

  describe("update_note", function()
    it("should update note content", function()
      local s = session.create("test-update-note")
      local n = note_module.create("/test.lua", 10, "Original content")
      session.add_note(s, n)

      session.update_note(s, n.id, "Updated content")

      assert.are.equal("Updated content", s.notes[1].content)

      -- Verify persisted
      local loaded = session.load(s.id)
      assert.are.equal("Updated content", loaded.notes[1].content)
    end)

    it("should return false when note not found", function()
      local s = session.create("test-update-nonexistent")
      local result = session.update_note(s, "nonexistent-id", "New content")
      assert.is_false(result)
    end)
  end)

  describe("get_notes_for_file", function()
    it("should filter notes by file path", function()
      local s = session.create("test-filter")
      local n1 = note_module.create("/file1.lua", 10, "Note 1")
      local n2 = note_module.create("/file2.lua", 20, "Note 2")
      local n3 = note_module.create("/file1.lua", 30, "Note 3")

      session.add_note(s, n1)
      session.add_note(s, n2)
      session.add_note(s, n3)

      local notes = session.get_notes_for_file(s, "/file1.lua")
      assert.are.equal(2, #notes)
    end)

    it("should return empty array when no notes for file", function()
      local s = session.create("test-no-notes")
      local notes = session.get_notes_for_file(s, "/nonexistent.lua")
      assert.is_table(notes)
      assert.are.equal(0, #notes)
    end)
  end)

  describe("get_note_at_line", function()
    it("should find note by file and line", function()
      local s = session.create("test-find-line")
      local n = note_module.create("/test.lua", 42, "Target note")
      session.add_note(s, n)

      local found = session.get_note_at_line(s, "/test.lua", 42)
      assert.is_not_nil(found)
      assert.are.equal(n.id, found.id)
    end)

    it("should find note within multi-line range", function()
      local s = session.create("test-range")
      local n = note_module.create("/test.lua", 10, "Multi-line note", 20)
      session.add_note(s, n)

      -- Should find at start, middle, and end of range
      assert.is_not_nil(session.get_note_at_line(s, "/test.lua", 10))
      assert.is_not_nil(session.get_note_at_line(s, "/test.lua", 15))
      assert.is_not_nil(session.get_note_at_line(s, "/test.lua", 20))

      -- Should not find outside range
      assert.is_nil(session.get_note_at_line(s, "/test.lua", 9))
      assert.is_nil(session.get_note_at_line(s, "/test.lua", 21))
    end)

    it("should handle notes with nil end_line (backward compatibility)", function()
      local s = session.create("test-backward-compat")
      local n = note_module.create("/test.lua", 10, "Old note")
      -- Simulate old note without end_line
      n.end_line = nil
      session.add_note(s, n)

      -- Should still find at exact line
      assert.is_not_nil(session.get_note_at_line(s, "/test.lua", 10))
      -- Should not find at other lines
      assert.is_nil(session.get_note_at_line(s, "/test.lua", 11))
    end)

    it("should return nil when not found", function()
      local s = session.create("test-not-found")
      local found = session.get_note_at_line(s, "/test.lua", 100)
      assert.is_nil(found)
    end)
  end)
end)
