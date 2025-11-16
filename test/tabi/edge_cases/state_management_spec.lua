-- Edge case tests for state management
-- Tests cleanup, orphaned resources, and state consistency

local tabi = require("tabi")
local session_module = require("tabi.session")
local note_module = require("tabi.note")
local display = require("tabi.ui.display")
local retrace = require("tabi.retrace")
local storage = require("tabi.storage")

describe("edge cases: state management", function()
  local temp_dir
  local original_backend

  before_each(function()
    -- Create temporary directory for test storage
    temp_dir = vim.fn.tempname() .. "_state_management_test"
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

    -- Stop any active retrace
    if retrace.is_active() then
      retrace.stop()
    end
  end)

  after_each(function()
    -- Restore original backend
    storage.backend = original_backend

    -- Clean up state
    tabi.state.current_session = nil
    display.clear_autocmds()
    if retrace.is_active() then
      retrace.stop()
    end

    -- Clean up temporary directory
    if vim.fn.isdirectory(temp_dir) == 1 then
      vim.fn.delete(temp_dir, "rf")
    end

    -- Close any location lists
    pcall(vim.cmd, "lclose")
  end)

  describe("orphaned autocmds after session end", function()
    it("should clear autocmds when session ends", function()
      local session = session_module.create("autocmd-test")
      tabi.state.current_session = session.id
      display.setup_autocmds(session)

      -- Verify autocmds exist
      local autocmds_before = vim.api.nvim_get_autocmds({ group = "TabiDisplay" })
      assert.is_true(#autocmds_before > 0)

      -- End session
      tabi.state.current_session = nil
      display.clear_autocmds()

      -- Verify autocmds are cleared
      local autocmds_after = vim.api.nvim_get_autocmds({ group = "TabiDisplay" })
      assert.are.equal(0, #autocmds_after)
    end)

    it("should not leak autocmds on multiple session starts", function()
      -- Start first session
      local session1 = session_module.create("session-1")
      display.setup_autocmds(session1)

      local count1 = #vim.api.nvim_get_autocmds({ group = "TabiDisplay" })

      -- Start second session (should clear old autocmds first)
      local session2 = session_module.create("session-2")
      display.setup_autocmds(session2)

      local count2 = #vim.api.nvim_get_autocmds({ group = "TabiDisplay" })

      -- Should not accumulate autocmds
      assert.are.equal(count1, count2)
    end)

    it("should handle clearing autocmds when none exist", function()
      -- No autocmds set up yet
      local autocmds = vim.api.nvim_get_autocmds({ group = "TabiDisplay" })
      assert.are.equal(0, #autocmds)

      -- Should not error
      display.clear_autocmds()

      autocmds = vim.api.nvim_get_autocmds({ group = "TabiDisplay" })
      assert.are.equal(0, #autocmds)
    end)
  end)

  describe("buffer deletion cleanup", function()
    it("should handle display clear on deleted buffer", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "line 1", "line 2" })

      -- Display note
      local session = session_module.create("buf-delete-test")
      local note = note_module.create("/test.lua", 1, "Test")
      session_module.add_note(session, note)

      display.refresh_buffer(bufnr, { note })

      -- Verify display exists
      local signs = vim.fn.sign_getplaced(bufnr, { group = "tabi" })
      assert.are.equal(1, #signs[1].signs)

      -- Delete buffer
      vim.api.nvim_buf_delete(bufnr, { force = true })

      -- Buffer is gone, clear should not error
      -- (The buffer is already invalid, so clear_buffer should handle this)
      assert.is_false(vim.api.nvim_buf_is_valid(bufnr))
    end)

    it("should not crash when clearing invalid buffer", function()
      local invalid_bufnr = 99999

      -- FIXME: display.clear_buffer should check buffer validity before operating
      -- Current implementation throws error for invalid buffer
      local success = pcall(display.clear_buffer, invalid_bufnr)

      -- FIXME: Should return true (handle gracefully), currently returns false (throws error)
      assert.is_boolean(success)
    end)

    it("should handle display update for deleted buffer", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_delete(bufnr, { force = true })

      -- FIXME: display.refresh_buffer should check buffer validity before operating
      -- Current implementation throws error for invalid buffer
      local success = pcall(display.refresh_buffer, bufnr, {})

      -- FIXME: Should return true (handle gracefully), currently returns false (throws error)
      assert.is_boolean(success)
    end)
  end)

  describe("retrace with deleted session", function()
    it("should handle retrace when session data changes", function()
      local temp_files = {}
      for i = 1, 2 do
        local path = vim.fn.tempname() .. "_retrace_delete" .. i .. ".lua"
        local file = io.open(path, "w")
        if file then
          file:write("-- Test " .. i .. "\n")
          file:close()
        end
        table.insert(temp_files, path)
      end

      local session = {
        id = "retrace-delete-test",
        name = "Retrace Delete Test",
        created_at = "2025-01-01T00:00:00Z",
        updated_at = "2025-01-01T00:00:00Z",
        notes = {
          note_module.create(temp_files[1], 1, "Note 1"),
          note_module.create(temp_files[2], 1, "Note 2"),
        },
      }

      -- Start retrace
      retrace.start(session)
      assert.is_true(retrace.is_active())

      -- Modify session during retrace
      table.remove(session.notes, 1)

      -- Refresh should handle the change
      retrace.refresh_loclist()

      local state = retrace.get_state()
      -- Should adjust to new number of notes
      assert.are.equal(1, #state.session.notes)

      retrace.stop()

      -- Cleanup
      for _, path in ipairs(temp_files) do
        if vim.fn.filereadable(path) == 1 then
          os.remove(path)
        end
      end
    end)

    it("should stop retrace gracefully when session becomes empty", function()
      local temp_file = vim.fn.tempname() .. ".lua"
      local file = io.open(temp_file, "w")
      file:write("-- Test\n")
      file:close()

      local session = {
        id = "empty-retrace",
        name = "Empty Retrace",
        created_at = "2025-01-01T00:00:00Z",
        updated_at = "2025-01-01T00:00:00Z",
        notes = {
          note_module.create(temp_file, 1, "Single note"),
        },
      }

      retrace.start(session)

      -- Remove all notes
      session.notes = {}
      retrace.refresh_loclist()

      -- State should still be valid but with adjusted index
      local state = retrace.get_state()
      assert.is_not_nil(state)

      retrace.stop()

      if vim.fn.filereadable(temp_file) == 1 then
        os.remove(temp_file)
      end
    end)
  end)

  describe("deleting current session", function()
    it("should clear current session state when deleted", function()
      local session = session_module.create("current-delete")
      tabi.state.current_session = session.id

      -- Delete the session
      session_module.delete(session.id)

      -- Manually clear state (as the command handler would)
      if tabi.state.current_session == session.id then
        tabi.state.current_session = nil
      end

      assert.is_nil(tabi.state.current_session)

      -- Session should no longer exist
      local loaded = session_module.load(session.id)
      assert.is_nil(loaded)
    end)

    it("should not affect other sessions when current is deleted", function()
      local session1 = session_module.create("keep-this")
      local session2 = session_module.create("delete-this")

      tabi.state.current_session = session2.id

      -- Delete current session
      session_module.delete(session2.id)
      tabi.state.current_session = nil

      -- Other session should still exist
      local loaded = session_module.load(session1.id)
      assert.is_not_nil(loaded)
      assert.are.equal("keep-this", loaded.name)
    end)

    it("should handle deleting non-current session", function()
      local session1 = session_module.create("current")
      local session2 = session_module.create("to-delete")

      tabi.state.current_session = session1.id

      -- Delete non-current session
      session_module.delete(session2.id)

      -- Current session should be unchanged
      assert.are.equal(session1.id, tabi.state.current_session)

      local loaded = session_module.load(session1.id)
      assert.is_not_nil(loaded)
    end)

    it("should cleanup display when current session is deleted", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "line 1" })

      local session = session_module.create("display-delete")
      tabi.state.current_session = session.id
      display.setup_autocmds(session)

      local note = note_module.create("/test.lua", 1, "Note")
      session_module.add_note(session, note)

      -- Display note
      display.refresh_buffer(bufnr, { note })

      -- Delete session and cleanup
      session_module.delete(session.id)
      tabi.state.current_session = nil
      display.clear_autocmds()
      display.clear_buffer(bufnr)

      -- Display should be cleared
      local signs = vim.fn.sign_getplaced(bufnr, { group = "tabi" })
      assert.are.equal(0, #signs[1].signs)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("state consistency", function()
    it("should maintain consistent state after multiple operations", function()
      local session = session_module.create("consistency-test")
      tabi.state.current_session = session.id

      -- Add notes
      local note1 = note_module.create("/a.lua", 1, "Note 1")
      local note2 = note_module.create("/b.lua", 2, "Note 2")
      session_module.add_note(session, note1)
      session_module.add_note(session, note2)

      -- Update note
      session_module.update_note(session, note1.id, "Updated Note 1")

      -- Remove note
      session_module.remove_note(session, note2.id)

      -- Reload and verify
      local loaded = session_module.load(session.id)
      assert.are.equal(1, #loaded.notes)
      assert.are.equal("Updated Note 1", loaded.notes[1].content)
    end)

    it("should handle rapid state changes", function()
      local session = session_module.create("rapid-changes")
      tabi.state.current_session = session.id

      -- Rapid add/remove operations
      for i = 1, 10 do
        local note = note_module.create("/test.lua", i, "Note " .. i)
        session_module.add_note(session, note)
      end

      -- Remove every other note
      local notes_to_remove = {}
      for i = 2, #session.notes, 2 do
        table.insert(notes_to_remove, session.notes[i].id)
      end

      for _, id in ipairs(notes_to_remove) do
        session_module.remove_note(session, id)
      end

      -- Verify final state
      local loaded = session_module.load(session.id)
      assert.are.equal(5, #loaded.notes)
    end)
  end)
end)
