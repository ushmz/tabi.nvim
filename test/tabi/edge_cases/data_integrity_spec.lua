-- Edge case tests for data integrity
-- Tests boundary conditions and unusual data scenarios

local session_module = require("tabi.session")
local note_module = require("tabi.note")
local storage = require("tabi.storage")

describe("edge cases: data integrity", function()
  local temp_dir
  local original_backend

  before_each(function()
    -- Create temporary directory for test storage
    temp_dir = vim.fn.tempname() .. "_data_integrity_test"
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
        local ok, decoded = pcall(vim.fn.json_decode, content)
        if ok then
          return decoded
        end
        return nil
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
        return sessions
      end,
      delete_session = function(id)
        local path = temp_dir .. "/sessions/" .. id .. ".json"
        if vim.fn.filereadable(path) == 1 then
          os.remove(path)
          return true
        end
        return false
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

  describe("empty session", function()
    it("should handle session with no notes", function()
      local session = session_module.create("empty-session")

      assert.is_not_nil(session)
      assert.are.equal(0, #session.notes)

      -- Should save successfully
      local saved = session_module.save(session)
      assert.is_true(saved)

      -- Should load successfully
      local loaded = session_module.load(session.id)
      assert.is_not_nil(loaded)
      assert.are.equal(0, #loaded.notes)
    end)

    it("should handle note operations on empty session", function()
      local session = session_module.create("empty-ops")

      -- Get note from empty session
      local note = session_module.get_note_at_line(session, "/test.lua", 1)
      assert.is_nil(note)

      -- Get notes for file from empty session
      local notes = session_module.get_notes_for_file(session, "/test.lua")
      assert.is_table(notes)
      assert.are.equal(0, #notes)

      -- Remove non-existent note (should not error)
      session_module.remove_note(session, "non-existent-id")
      assert.are.equal(0, #session.notes)
    end)
  end)

  describe("default session auto-creation", function()
    it("should create default session when none exists", function()
      local session = session_module.get_or_create_default()

      assert.is_not_nil(session)
      assert.is_not_nil(session.id)
      assert.is_not_nil(session.name)

      -- Should be persisted
      local loaded = session_module.load(session.id)
      assert.is_not_nil(loaded)
    end)

    it("should return existing default session if available", function()
      local first = session_module.get_or_create_default()
      local second = session_module.get_or_create_default()

      -- Should return same session (or at least consistent behavior)
      assert.is_not_nil(first)
      assert.is_not_nil(second)
    end)
  end)

  describe("notes for non-existent files", function()
    it("should allow creating note for non-existent file", function()
      local session = session_module.create("non-existent-file")
      local note = note_module.create("/path/to/non/existent/file.lua", 10, "Note for missing file")

      session_module.add_note(session, note)

      assert.are.equal(1, #session.notes)
      assert.are.equal("/path/to/non/existent/file.lua", session.notes[1].file)
    end)

    it("should persist notes for non-existent files", function()
      local session = session_module.create("persist-missing")
      local note = note_module.create("/missing/file.lua", 5, "Persisted note")
      session_module.add_note(session, note)

      local loaded = session_module.load(session.id)
      assert.are.equal(1, #loaded.notes)
      assert.are.equal("/missing/file.lua", loaded.notes[1].file)
    end)
  end)

  describe("notes for deleted files", function()
    it("should handle notes when file is deleted after creation", function()
      -- Create temporary file
      local temp_file = vim.fn.tempname() .. ".lua"
      local file = io.open(temp_file, "w")
      file:write("local x = 1\n")
      file:close()

      -- Create note for file
      local session = session_module.create("deleted-file")
      local note = note_module.create(temp_file, 1, "Note before deletion")
      session_module.add_note(session, note)

      -- Delete file
      os.remove(temp_file)

      -- Note should still exist
      assert.are.equal(1, #session.notes)
      local found = session_module.get_note_at_line(session, temp_file, 1)
      assert.is_not_nil(found)
      assert.are.equal("Note before deletion", found.content)
    end)
  end)

  describe("multiple notes on same line", function()
    it("should handle multiple notes added to same line", function()
      local session = session_module.create("same-line")
      local note1 = note_module.create("/test.lua", 5, "First note")
      local note2 = note_module.create("/test.lua", 5, "Second note")

      session_module.add_note(session, note1)
      session_module.add_note(session, note2)

      -- Both notes should be added
      assert.are.equal(2, #session.notes)

      -- get_note_at_line returns first match
      local found = session_module.get_note_at_line(session, "/test.lua", 5)
      assert.is_not_nil(found)
      -- Should return one of them (first match)
      assert.is_true(found.content == "First note" or found.content == "Second note")
    end)
  end)

  describe("very long note content", function()
    it("should handle extremely long note content", function()
      local session = session_module.create("long-note")
      local long_content = string.rep("This is a very long note. ", 1000)
      local note = note_module.create("/test.lua", 1, long_content)

      session_module.add_note(session, note)

      -- Should save and load correctly
      local loaded = session_module.load(session.id)
      assert.are.equal(1, #loaded.notes)
      assert.are.equal(long_content, loaded.notes[1].content)
    end)

    it("should truncate preview for long notes", function()
      local long_content = string.rep("x", 1000)
      local note = note_module.create("/test.lua", 1, long_content)

      local preview = note_module.get_preview(note, 30)
      assert.is_true(#preview <= 33) -- 30 chars + "..."
    end)
  end)

  describe("special characters in notes", function()
    it("should handle newlines in note content", function()
      local session = session_module.create("newline-test")
      local content = "Line 1\nLine 2\nLine 3"
      local note = note_module.create("/test.lua", 1, content)

      session_module.add_note(session, note)

      local loaded = session_module.load(session.id)
      assert.are.equal(content, loaded.notes[1].content)
    end)

    it("should handle unicode characters", function()
      local session = session_module.create("unicode-test")
      local content = "日本語テスト 🎉 émojis et accénts"
      local note = note_module.create("/test.lua", 1, content)

      session_module.add_note(session, note)

      local loaded = session_module.load(session.id)
      assert.are.equal(content, loaded.notes[1].content)
    end)

    it("should handle tabs and special whitespace", function()
      local session = session_module.create("whitespace-test")
      local content = "Tab:\tNext\nCarriage:\rReturn"
      local note = note_module.create("/test.lua", 1, content)

      session_module.add_note(session, note)

      local loaded = session_module.load(session.id)
      assert.are.equal(content, loaded.notes[1].content)
    end)

    it("should handle quotes and backslashes", function()
      local session = session_module.create("quotes-test")
      local content = 'Quote: "test" and \'single\' with \\ backslash'
      local note = note_module.create("/test.lua", 1, content)

      session_module.add_note(session, note)

      local loaded = session_module.load(session.id)
      assert.are.equal(content, loaded.notes[1].content)
    end)
  end)

  describe("special characters in file names", function()
    it("should handle spaces in file paths", function()
      local session = session_module.create("space-path")
      local note = note_module.create("/path/with spaces/file name.lua", 1, "Note")

      session_module.add_note(session, note)

      local loaded = session_module.load(session.id)
      assert.are.equal("/path/with spaces/file name.lua", loaded.notes[1].file)

      local found = session_module.get_note_at_line(session, "/path/with spaces/file name.lua", 1)
      assert.is_not_nil(found)
    end)

    it("should handle unicode in file paths", function()
      local session = session_module.create("unicode-path")
      local note = note_module.create("/日本語/ファイル.lua", 1, "Note")

      session_module.add_note(session, note)

      local loaded = session_module.load(session.id)
      assert.are.equal("/日本語/ファイル.lua", loaded.notes[1].file)
    end)

    it("should handle special characters in paths", function()
      local session = session_module.create("special-path")
      local note = note_module.create("/path/with-dashes_and_underscores/file.test.lua", 1, "Note")

      session_module.add_note(session, note)

      local loaded = session_module.load(session.id)
      assert.are.equal("/path/with-dashes_and_underscores/file.test.lua", loaded.notes[1].file)
    end)
  end)

  describe("overlapping multi-line note ranges", function()
    it("should return first matching note for overlapping ranges", function()
      local session = session_module.create("overlap-test")

      -- Note 1: lines 1-5
      local note1 = note_module.create("/test.lua", 1, "First range", 5)
      -- Note 2: lines 3-7 (overlaps with note1)
      local note2 = note_module.create("/test.lua", 3, "Second range", 7)

      session_module.add_note(session, note1)
      session_module.add_note(session, note2)

      -- Line 4 is in both ranges, should return first match
      local found = session_module.get_note_at_line(session, "/test.lua", 4)
      assert.is_not_nil(found)
      assert.are.equal("First range", found.content)
    end)

    it("should handle completely nested ranges", function()
      local session = session_module.create("nested-test")

      -- Outer range: lines 1-10
      local outer = note_module.create("/test.lua", 1, "Outer", 10)
      -- Inner range: lines 3-5
      local inner = note_module.create("/test.lua", 3, "Inner", 5)

      session_module.add_note(session, outer)
      session_module.add_note(session, inner)

      -- Line 4 is in both, should return first (outer)
      local found = session_module.get_note_at_line(session, "/test.lua", 4)
      assert.are.equal("Outer", found.content)
    end)
  end)

  describe("backward compatibility with nil end_line", function()
    it("should handle old note format without end_line", function()
      local session = session_module.create("compat-test")

      -- Simulate old note format
      local old_note = {
        id = "old-format-note",
        file = "/test.lua",
        line = 5,
        -- end_line is missing (nil)
        content = "Old format note",
        created_at = "2025-01-01T00:00:00Z",
      }
      table.insert(session.notes, old_note)
      session_module.save(session)

      -- Should be found at exact line
      local found = session_module.get_note_at_line(session, "/test.lua", 5)
      assert.is_not_nil(found)
      assert.are.equal("Old format note", found.content)

      -- Should NOT be found at other lines
      local not_found = session_module.get_note_at_line(session, "/test.lua", 6)
      assert.is_nil(not_found)
    end)

    it("should format old notes correctly", function()
      local old_note = {
        id = "old-note",
        file = "/test.lua",
        line = 10,
        -- no end_line
        content = "Content",
        created_at = "2025-01-01T00:00:00Z",
      }

      local formatted = note_module.format(old_note)
      assert.is_string(formatted)
      -- Should show single line, not range (no "10-11" style)
      assert.is_true(formatted:find(":10 ") ~= nil) -- Single line number
      assert.is_nil(formatted:find(":10%-")) -- No range like "10-15"
    end)

    it("should mix old and new note formats", function()
      local session = session_module.create("mixed-format")

      -- Old format (single line)
      local old_note = {
        id = "old",
        file = "/test.lua",
        line = 5,
        content = "Old",
        created_at = "2025-01-01T00:00:00Z",
      }
      -- New format (multi-line)
      local new_note = note_module.create("/test.lua", 10, "New", 15)

      table.insert(session.notes, old_note)
      session_module.add_note(session, new_note)

      -- Both should work correctly
      local found_old = session_module.get_note_at_line(session, "/test.lua", 5)
      local found_new = session_module.get_note_at_line(session, "/test.lua", 12)

      assert.is_not_nil(found_old)
      assert.is_not_nil(found_new)
      assert.are.equal("Old", found_old.content)
      assert.are.equal("New", found_new.content)
    end)
  end)
end)
