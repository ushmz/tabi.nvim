-- Integration tests for session lifecycle
-- Tests: start -> autocmd setup -> add notes -> end -> cleanup

local tabi = require("tabi")
local session_module = require("tabi.session")
local note_module = require("tabi.note")
local display = require("tabi.ui.display")
local storage = require("tabi.storage")
local config = require("tabi.config")

describe("integration: session lifecycle", function()
  local temp_dir
  local original_backend
  local test_file

  before_each(function()
    -- Reset config to defaults
    config.options = vim.deepcopy(config.defaults)

    -- Create temporary directory for test storage
    temp_dir = vim.fn.tempname() .. "_session_lifecycle_test"
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
    test_file = vim.fn.tempname() .. "_session_test.lua"
    local file = io.open(test_file, "w")
    if file then
      file:write("local M = {}\nreturn M\n")
      file:close()
    end
  end)

  after_each(function()
    -- Restore original backend
    storage.backend = original_backend

    -- Clean up state
    tabi.state.current_session = nil
    display.clear_autocmds()

    -- Clean up test file
    if vim.fn.filereadable(test_file) == 1 then
      os.remove(test_file)
    end

    -- Clean up temporary directory
    if vim.fn.isdirectory(temp_dir) == 1 then
      vim.fn.delete(temp_dir, "rf")
    end
  end)

  describe("start -> autocmd -> notes -> end -> cleanup", function()
    it("should complete full session lifecycle", function()
      -- 1. Start session
      local session = session_module.create("lifecycle-test")
      tabi.state.current_session = session.id

      assert.is_not_nil(session)
      assert.is_not_nil(tabi.state.current_session)
      assert.are.equal(session.id, tabi.state.current_session)

      -- 2. Setup autocmds
      display.setup_autocmds(session)

      -- Verify autocmds are created
      local autocmds = vim.api.nvim_get_autocmds({ group = "TabiDisplay" })
      assert.is_true(#autocmds > 0)

      -- Verify BufEnter autocmd exists
      local buf_enter_found = false
      for _, autocmd in ipairs(autocmds) do
        if autocmd.event == "BufEnter" or autocmd.event == "BufWinEnter" then
          buf_enter_found = true
        end
      end
      assert.is_true(buf_enter_found)

      -- 3. Add notes
      local note1 = note_module.create(test_file, 1, "First note")
      local note2 = note_module.create(test_file, 2, "Second note")

      session_module.add_note(session, note1)
      session_module.add_note(session, note2)

      -- Verify notes are added
      assert.are.equal(2, #session.notes)

      -- Verify persistence
      local loaded = session_module.load(session.id)
      assert.are.equal(2, #loaded.notes)

      -- 4. End session
      tabi.state.current_session = nil

      -- 5. Cleanup autocmds
      display.clear_autocmds()

      -- Verify autocmds are cleared
      local autocmds_after = vim.api.nvim_get_autocmds({ group = "TabiDisplay" })
      assert.are.equal(0, #autocmds_after)

      -- Verify state is cleared
      assert.is_nil(tabi.state.current_session)
    end)

    it("should preserve session data after cleanup", function()
      -- Create session with notes
      local session = session_module.create("preserve-test")
      tabi.state.current_session = session.id
      display.setup_autocmds(session)

      local note = note_module.create(test_file, 1, "Preserved note")
      session_module.add_note(session, note)

      -- End session
      tabi.state.current_session = nil
      display.clear_autocmds()

      -- Session data should still be accessible
      local loaded = session_module.load(session.id)
      assert.is_not_nil(loaded)
      assert.are.equal("preserve-test", loaded.name)
      assert.are.equal(1, #loaded.notes)
      assert.are.equal("Preserved note", loaded.notes[1].content)
    end)
  end)

  describe("session switching", function()
    it("should update display when switching sessions", function()
      local test_bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
        "local M = {}",
        "return M",
      })
      vim.api.nvim_buf_set_name(test_bufnr, test_file)

      -- Create first session
      local session1 = session_module.create("session-1")
      tabi.state.current_session = session1.id
      local note1 = note_module.create(test_file, 1, "Note in session 1")
      session_module.add_note(session1, note1)

      -- Display session 1 notes
      local notes1 = session_module.get_notes_for_file(session1, test_file)
      display.refresh_buffer(test_bufnr, notes1)

      -- Verify session 1 display
      local signs1 = vim.fn.sign_getplaced(test_bufnr, { group = "tabi" })
      assert.are.equal(1, #signs1[1].signs)
      assert.are.equal(1, signs1[1].signs[1].lnum)

      -- Create second session
      local session2 = session_module.create("session-2")
      local note2 = note_module.create(test_file, 2, "Note in session 2")
      session_module.add_note(session2, note2)

      -- Switch to session 2
      tabi.state.current_session = session2.id

      -- Display session 2 notes
      local notes2 = session_module.get_notes_for_file(session2, test_file)
      display.refresh_buffer(test_bufnr, notes2)

      -- Verify session 2 display
      local signs2 = vim.fn.sign_getplaced(test_bufnr, { group = "tabi" })
      assert.are.equal(1, #signs2[1].signs)
      assert.are.equal(2, signs2[1].signs[1].lnum)

      vim.api.nvim_buf_delete(test_bufnr, { force = true })
    end)

    it("should clear display when switching to no session", function()
      local test_bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
        "local M = {}",
        "return M",
      })
      vim.api.nvim_buf_set_name(test_bufnr, test_file)

      -- Create session with notes
      local session = session_module.create("to-clear")
      tabi.state.current_session = session.id
      local note = note_module.create(test_file, 1, "Note to clear")
      session_module.add_note(session, note)

      -- Display notes
      local notes = session_module.get_notes_for_file(session, test_file)
      display.refresh_buffer(test_bufnr, notes)

      -- Verify notes are displayed
      local signs_before = vim.fn.sign_getplaced(test_bufnr, { group = "tabi" })
      assert.are.equal(1, #signs_before[1].signs)

      -- Switch to no session
      tabi.state.current_session = nil
      display.clear_buffer(test_bufnr)

      -- Verify display is cleared
      local signs_after = vim.fn.sign_getplaced(test_bufnr, { group = "tabi" })
      assert.are.equal(0, #signs_after[1].signs)

      vim.api.nvim_buf_delete(test_bufnr, { force = true })
    end)

    it("should handle multiple sessions with different notes", function()
      -- Create multiple sessions
      local session1 = session_module.create("session-a")
      local session2 = session_module.create("session-b")
      local session3 = session_module.create("session-c")

      -- Add different notes to each session
      session_module.add_note(session1, note_module.create(test_file, 1, "Session A note"))
      session_module.add_note(session2, note_module.create(test_file, 1, "Session B note"))
      session_module.add_note(session3, note_module.create(test_file, 1, "Session C note"))

      -- Verify each session has its own notes
      local loaded1 = session_module.load(session1.id)
      local loaded2 = session_module.load(session2.id)
      local loaded3 = session_module.load(session3.id)

      assert.are.equal(1, #loaded1.notes)
      assert.are.equal(1, #loaded2.notes)
      assert.are.equal(1, #loaded3.notes)

      assert.are.equal("Session A note", loaded1.notes[1].content)
      assert.are.equal("Session B note", loaded2.notes[1].content)
      assert.are.equal("Session C note", loaded3.notes[1].content)
    end)
  end)

  describe("autocmd lifecycle", function()
    it("should clear old autocmds when setting up new session", function()
      local session1 = session_module.create("autocmd-test-1")
      display.setup_autocmds(session1)

      local autocmds_before = vim.api.nvim_get_autocmds({ group = "TabiDisplay" })
      local count_before = #autocmds_before

      -- Setup new session (should clear old autocmds)
      local session2 = session_module.create("autocmd-test-2")
      display.setup_autocmds(session2)

      local autocmds_after = vim.api.nvim_get_autocmds({ group = "TabiDisplay" })
      local count_after = #autocmds_after

      -- Count should be the same (old ones cleared, new ones created)
      assert.are.equal(count_before, count_after)
    end)

    it("should not fail when clearing autocmds multiple times", function()
      local session = session_module.create("clear-test")
      display.setup_autocmds(session)

      -- Clear multiple times
      display.clear_autocmds()
      display.clear_autocmds()
      display.clear_autocmds()

      -- Should not throw error
      local autocmds = vim.api.nvim_get_autocmds({ group = "TabiDisplay" })
      assert.are.equal(0, #autocmds)
    end)
  end)

  describe("state isolation", function()
    it("should isolate session state from global state", function()
      local session = session_module.create("isolated")
      tabi.state.current_session = session.id

      -- Modify session
      local note = note_module.create(test_file, 1, "Isolated note")
      session_module.add_note(session, note)

      -- Clear global state
      tabi.state.current_session = nil

      -- Session data should still exist
      local loaded = session_module.load(session.id)
      assert.is_not_nil(loaded)
      assert.are.equal(1, #loaded.notes)

      -- Global state should be clear
      assert.is_nil(tabi.state.current_session)
    end)
  end)
end)
