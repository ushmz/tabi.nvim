-- Integration tests for note lifecycle
-- Tests end-to-end workflows: create -> display -> save -> load

local tabi = require("tabi")
local session_module = require("tabi.session")
local note_module = require("tabi.note")
local display = require("tabi.ui.display")
local storage = require("tabi.storage")
local config = require("tabi.config")

describe("integration: note lifecycle", function()
  local temp_dir
  local original_backend
  local test_bufnr
  local test_file
  local ns = vim.api.nvim_create_namespace("tabi")

  before_each(function()
    -- Reset config to defaults
    config.options = vim.deepcopy(config.defaults)

    -- Create temporary directory for test storage
    temp_dir = vim.fn.tempname() .. "_note_lifecycle_test"
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

    -- Initialize display
    display.init()

    -- Reset state
    tabi.state.current_session = nil

    -- Create test file
    test_file = vim.fn.tempname() .. "_lifecycle.lua"
    local file = io.open(test_file, "w")
    if file then
      file:write("local M = {}\n")
      file:write("function M.foo()\n")
      file:write("  return 'bar'\n")
      file:write("end\n")
      file:write("return M\n")
      file:close()
    end

    -- Create test buffer
    test_bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
      "local M = {}",
      "function M.foo()",
      "  return 'bar'",
      "end",
      "return M",
    })
    vim.api.nvim_buf_set_name(test_bufnr, test_file)
    vim.api.nvim_set_current_buf(test_bufnr)
  end)

  after_each(function()
    -- Restore original backend
    storage.backend = original_backend

    -- Clean up state
    tabi.state.current_session = nil
    display.clear_autocmds()

    -- Clean up buffer
    if vim.api.nvim_buf_is_valid(test_bufnr) then
      vim.api.nvim_buf_delete(test_bufnr, { force = true })
    end

    -- Clean up test file
    if vim.fn.filereadable(test_file) == 1 then
      os.remove(test_file)
    end

    -- Clean up temporary directory
    if vim.fn.isdirectory(temp_dir) == 1 then
      vim.fn.delete(temp_dir, "rf")
    end
  end)

  describe("create -> display -> save -> load", function()
    it("should complete full note creation lifecycle", function()
      -- 1. Create session
      local session = session_module.create("lifecycle-test")
      tabi.state.current_session = session.id
      display.setup_autocmds(session)

      assert.is_not_nil(session)
      assert.are.equal("lifecycle-test", session.name)
      assert.are.equal(0, #session.notes)

      -- 2. Add note
      local note = note_module.create(test_file, 2, "This function returns 'bar'")
      session_module.add_note(session, note)

      -- Verify note was added
      assert.are.equal(1, #session.notes)
      assert.are.equal(test_file, session.notes[1].file)
      assert.are.equal(2, session.notes[1].line)

      -- 3. Update display (use refresh_buffer directly to avoid path matching issues)
      local notes = session_module.get_notes_for_file(session, test_file)
      display.refresh_buffer(test_bufnr, notes)

      -- Verify signs are placed
      local signs = vim.fn.sign_getplaced(test_bufnr, { group = "tabi" })
      assert.is_true(#signs[1].signs > 0)
      assert.are.equal(2, signs[1].signs[1].lnum)

      -- Verify virtual lines are added
      local extmarks = vim.api.nvim_buf_get_extmarks(test_bufnr, ns, 0, -1, { details = true })
      local found_virt_lines = false
      for _, mark in ipairs(extmarks) do
        if mark[4] and mark[4].virt_lines then
          found_virt_lines = true
        end
      end
      assert.is_true(found_virt_lines)

      -- 4. Verify persistence (session was saved by add_note)
      local loaded = session_module.load(session.id)
      assert.is_not_nil(loaded)
      assert.are.equal(1, #loaded.notes)
      assert.are.equal("This function returns 'bar'", loaded.notes[1].content)

      -- 5. Clean reload from storage
      tabi.state.current_session = nil
      local reloaded = session_module.load(session.id)
      assert.is_not_nil(reloaded)
      assert.are.equal(session.id, reloaded.id)
      assert.are.equal(1, #reloaded.notes)
    end)
  end)

  describe("edit -> update -> display", function()
    it("should update note content and refresh display", function()
      -- Setup: create session with note
      local session = session_module.create("edit-test")
      tabi.state.current_session = session.id
      local note = note_module.create(test_file, 3, "Original content")
      session_module.add_note(session, note)

      -- Display initial state
      local notes_before = session_module.get_notes_for_file(session, test_file)
      display.refresh_buffer(test_bufnr, notes_before)

      -- Verify initial virtual lines
      local extmarks_before = vim.api.nvim_buf_get_extmarks(test_bufnr, ns, 0, -1, { details = true })
      local original_text = nil
      for _, mark in ipairs(extmarks_before) do
        if mark[4] and mark[4].virt_lines then
          original_text = mark[4].virt_lines[1][1][1]
        end
      end
      assert.is_not_nil(original_text)
      assert.is_true(original_text:find("Original content") ~= nil)

      -- Edit note
      session_module.update_note(session, note.id, "Updated content")

      -- Refresh display
      local notes_after = session_module.get_notes_for_file(session, test_file)
      display.refresh_buffer(test_bufnr, notes_after)

      -- Verify updated virtual lines
      local extmarks_after = vim.api.nvim_buf_get_extmarks(test_bufnr, ns, 0, -1, { details = true })
      local updated_text = nil
      for _, mark in ipairs(extmarks_after) do
        if mark[4] and mark[4].virt_lines then
          updated_text = mark[4].virt_lines[1][1][1]
        end
      end
      assert.is_not_nil(updated_text)
      assert.is_true(updated_text:find("Updated content") ~= nil)

      -- Verify persistence
      local loaded = session_module.load(session.id)
      assert.are.equal("Updated content", loaded.notes[1].content)
    end)
  end)

  describe("delete -> clear display -> save", function()
    it("should remove note and clear display", function()
      -- Setup: create session with note
      local session = session_module.create("delete-test")
      tabi.state.current_session = session.id
      local note = note_module.create(test_file, 4, "Note to delete")
      session_module.add_note(session, note)

      -- Display initial state
      local notes_before = session_module.get_notes_for_file(session, test_file)
      display.refresh_buffer(test_bufnr, notes_before)

      -- Verify note exists
      local signs_before = vim.fn.sign_getplaced(test_bufnr, { group = "tabi" })
      assert.are.equal(1, #signs_before[1].signs)

      -- Delete note
      session_module.remove_note(session, note.id)

      -- Refresh display
      local notes_after = session_module.get_notes_for_file(session, test_file)
      display.refresh_buffer(test_bufnr, notes_after)

      -- Verify display is cleared
      local signs_after = vim.fn.sign_getplaced(test_bufnr, { group = "tabi" })
      assert.are.equal(0, #signs_after[1].signs)

      local extmarks_after = vim.api.nvim_buf_get_extmarks(test_bufnr, ns, 0, -1, {})
      assert.are.equal(0, #extmarks_after)

      -- Verify persistence
      local loaded = session_module.load(session.id)
      assert.are.equal(0, #loaded.notes)
    end)
  end)

  describe("multi-line note -> save -> edit from any line", function()
    it("should create multi-line note and allow editing from any line in range", function()
      -- Setup
      local session = session_module.create("multiline-test")
      tabi.state.current_session = session.id

      -- Create multi-line note (lines 2-4)
      local note = note_module.create(test_file, 2, "Function implementation", 4)
      session_module.add_note(session, note)

      -- Verify range info saved
      local loaded = session_module.load(session.id)
      assert.are.equal(2, loaded.notes[1].line)
      assert.are.equal(4, loaded.notes[1].end_line)

      -- Verify note can be found from any line in range
      local found_from_line2 = session_module.get_note_at_line(session, test_file, 2)
      local found_from_line3 = session_module.get_note_at_line(session, test_file, 3)
      local found_from_line4 = session_module.get_note_at_line(session, test_file, 4)
      local not_found_line1 = session_module.get_note_at_line(session, test_file, 1)
      local not_found_line5 = session_module.get_note_at_line(session, test_file, 5)

      assert.is_not_nil(found_from_line2)
      assert.is_not_nil(found_from_line3)
      assert.is_not_nil(found_from_line4)
      assert.is_nil(not_found_line1)
      assert.is_nil(not_found_line5)

      -- All should be the same note
      assert.are.equal(note.id, found_from_line2.id)
      assert.are.equal(note.id, found_from_line3.id)
      assert.are.equal(note.id, found_from_line4.id)

      -- Edit note from line 3 (middle of range)
      session_module.update_note(session, found_from_line3.id, "Updated from middle line")

      -- Verify update persisted
      local reloaded = session_module.load(session.id)
      assert.are.equal("Updated from middle line", reloaded.notes[1].content)
      -- Range should be preserved
      assert.are.equal(2, reloaded.notes[1].line)
      assert.are.equal(4, reloaded.notes[1].end_line)
    end)

    it("should handle backward compatibility with nil end_line", function()
      local session = session_module.create("compat-test")

      -- Simulate old note data without end_line
      local old_note = {
        id = "old-note-id",
        file = test_file,
        line = 3,
        -- end_line is nil (old format)
        content = "Old format note",
        created_at = "2025-01-01T00:00:00Z",
      }
      table.insert(session.notes, old_note)
      session_module.save(session)

      -- Load and verify note can be found at its line
      local found = session_module.get_note_at_line(session, test_file, 3)
      assert.is_not_nil(found)
      assert.are.equal("old-note-id", found.id)

      -- Should not be found on other lines
      local not_found = session_module.get_note_at_line(session, test_file, 4)
      assert.is_nil(not_found)
    end)
  end)

  describe("multiple notes in same file", function()
    it("should handle multiple notes with proper display", function()
      local session = session_module.create("multi-note-test")
      tabi.state.current_session = session.id

      -- Add multiple notes
      local note1 = note_module.create(test_file, 1, "Module definition")
      local note2 = note_module.create(test_file, 2, "Function declaration")
      local note3 = note_module.create(test_file, 5, "Module return")

      session_module.add_note(session, note1)
      session_module.add_note(session, note2)
      session_module.add_note(session, note3)

      -- Update display
      local notes = session_module.get_notes_for_file(session, test_file)
      display.refresh_buffer(test_bufnr, notes)

      -- Verify all signs are placed
      local signs = vim.fn.sign_getplaced(test_bufnr, { group = "tabi" })
      assert.are.equal(3, #signs[1].signs)

      -- Verify each note can be found
      local found1 = session_module.get_note_at_line(session, test_file, 1)
      local found2 = session_module.get_note_at_line(session, test_file, 2)
      local found5 = session_module.get_note_at_line(session, test_file, 5)

      assert.are.equal(note1.id, found1.id)
      assert.are.equal(note2.id, found2.id)
      assert.are.equal(note3.id, found5.id)

      -- Verify persistence
      local loaded = session_module.load(session.id)
      assert.are.equal(3, #loaded.notes)
    end)
  end)
end)
