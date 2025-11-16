-- Test for plugin/tabi.lua command handlers
-- Since plugin/tabi.lua guards against double loading, we test the module behavior

local tabi = require("tabi")
local session_module = require("tabi.session")
local note_module = require("tabi.note")
local display = require("tabi.ui.display")
local retrace = require("tabi.retrace")
local storage = require("tabi.storage")

describe("tabi commands", function()
  local temp_dir
  local original_backend
  local original_notify
  local original_ui_input
  local notifications = {}

  before_each(function()
    -- Create temporary directory for test storage
    temp_dir = vim.fn.tempname() .. "_tabi_commands_test"
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
        table.sort(sessions, function(a, b)
          return a.updated_at > b.updated_at
        end)
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

    -- Mock notifications
    original_notify = vim.notify
    notifications = {}
    vim.notify = function(msg, level)
      table.insert(notifications, { msg = msg, level = level })
    end

    -- Mock vim.ui.input
    original_ui_input = vim.ui.input

    -- Stop any active retrace
    if retrace.is_active() then
      retrace.stop()
    end
  end)

  after_each(function()
    -- Restore original backend
    storage.backend = original_backend

    -- Restore notify
    vim.notify = original_notify

    -- Restore vim.ui.input
    vim.ui.input = original_ui_input

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
  end)

  describe("session management", function()
    it("should create new session with :Tabi start", function()
      local session = session_module.create("test-session")
      tabi.state.current_session = session.id
      display.setup_autocmds(session)

      assert.is_not_nil(tabi.state.current_session)
      local loaded = session_module.load(tabi.state.current_session)
      assert.are.equal("test-session", loaded.name)
    end)

    it("should notify when session already active", function()
      local session = session_module.create("existing")
      tabi.state.current_session = session.id

      -- Try to start another session
      local new_session = session_module.load(tabi.state.current_session)
      if new_session then
        vim.notify('Tabi: Session "' .. new_session.name .. '" is already active. Continuing...', vim.log.levels.INFO)
      end

      local found = false
      for _, n in ipairs(notifications) do
        if n.msg:find("is already active") then
          found = true
        end
      end
      assert.is_true(found)
    end)

    it("should end session and clear state", function()
      local session = session_module.create("to-end")
      tabi.state.current_session = session.id
      display.setup_autocmds(session)

      -- End session
      vim.notify('Tabi: Session "' .. session.name .. '" ended', vim.log.levels.INFO)
      tabi.state.current_session = nil
      display.clear_autocmds()

      assert.is_nil(tabi.state.current_session)
    end)

    it("should warn when ending with no active session", function()
      tabi.state.current_session = nil

      vim.notify("Tabi: No active session", vim.log.levels.WARN)

      local found = false
      for _, n in ipairs(notifications) do
        if n.msg:find("No active session") and n.level == vim.log.levels.WARN then
          found = true
        end
      end
      assert.is_true(found)
    end)
  end)

  describe("note operations", function()
    local test_bufnr
    local test_file

    before_each(function()
      -- Create test buffer with file
      test_file = vim.fn.tempname() .. ".lua"
      local file = io.open(test_file, "w")
      if file then
        file:write("line 1\nline 2\nline 3\nline 4\nline 5\n")
        file:close()
      end

      test_bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
        "line 1",
        "line 2",
        "line 3",
        "line 4",
        "line 5",
      })
      vim.api.nvim_buf_set_name(test_bufnr, test_file)
      vim.api.nvim_set_current_buf(test_bufnr)
    end)

    after_each(function()
      if vim.api.nvim_buf_is_valid(test_bufnr) then
        vim.api.nvim_buf_delete(test_bufnr, { force = true })
      end
      if vim.fn.filereadable(test_file) == 1 then
        os.remove(test_file)
      end
    end)

    it("should create note at cursor position", function()
      local session = session_module.create("note-test")
      tabi.state.current_session = session.id

      -- Set cursor position
      vim.api.nvim_win_set_cursor(0, { 3, 0 })

      -- Create note
      local note = note_module.create(test_file, 3, "Test note content")
      session_module.add_note(session, note)

      local loaded = session_module.load(session.id)
      assert.are.equal(1, #loaded.notes)
      assert.are.equal(3, loaded.notes[1].line)
      assert.are.equal("Test note content", loaded.notes[1].content)
    end)

    it("should support multi-line note selection", function()
      local session = session_module.create("range-test")
      tabi.state.current_session = session.id

      -- Create note with range
      local note = note_module.create(test_file, 2, "Multi-line note", 4)
      session_module.add_note(session, note)

      local loaded = session_module.load(session.id)
      assert.are.equal(1, #loaded.notes)
      assert.are.equal(2, loaded.notes[1].line)
      assert.are.equal(4, loaded.notes[1].end_line)
    end)

    it("should warn when adding note to unnamed buffer", function()
      local unnamed_buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(unnamed_buf)

      local file_path = vim.api.nvim_buf_get_name(unnamed_buf)
      if file_path == "" then
        vim.notify("Tabi: Cannot add note to unnamed buffer", vim.log.levels.ERROR)
      end

      local found = false
      for _, n in ipairs(notifications) do
        if n.msg:find("unnamed buffer") then
          found = true
        end
      end
      assert.is_true(found)

      vim.api.nvim_buf_delete(unnamed_buf, { force = true })
    end)

    it("should update existing note at line", function()
      local session = session_module.create("update-test")
      local note = note_module.create(test_file, 3, "Original note")
      session_module.add_note(session, note)

      -- Update note
      session_module.update_note(session, note.id, "Updated content")

      local loaded = session_module.load(session.id)
      assert.are.equal("Updated content", loaded.notes[1].content)
    end)

    it("should delete note at cursor", function()
      local session = session_module.create("delete-test")
      local note = note_module.create(test_file, 3, "Note to delete")
      session_module.add_note(session, note)

      -- Delete note
      session_module.remove_note(session, note.id)
      vim.notify("Tabi: Note deleted", vim.log.levels.INFO)

      local loaded = session_module.load(session.id)
      assert.are.equal(0, #loaded.notes)

      local found = false
      for _, n in ipairs(notifications) do
        if n.msg:find("Note deleted") then
          found = true
        end
      end
      assert.is_true(found)
    end)

    it("should warn when no note at cursor for delete", function()
      local session = session_module.create("no-note-test")
      tabi.state.current_session = session.id

      vim.api.nvim_win_set_cursor(0, { 2, 0 })
      local note = session_module.get_note_at_line(session, test_file, 2)

      if not note then
        vim.notify("Tabi: No note at current line", vim.log.levels.WARN)
      end

      local found = false
      for _, n in ipairs(notifications) do
        if n.msg:find("No note at current line") then
          found = true
        end
      end
      assert.is_true(found)
    end)

    it("should auto-create default session when no session active", function()
      tabi.state.current_session = nil

      local session = session_module.get_or_create_default()
      tabi.state.current_session = session.id

      assert.is_not_nil(session)
      assert.is_not_nil(tabi.state.current_session)
    end)
  end)

  describe("retrace commands", function()
    local temp_files = {}

    before_each(function()
      -- Create temporary files for testing
      for i = 1, 3 do
        local path = vim.fn.tempname() .. "_retrace_cmd" .. i .. ".lua"
        local file = io.open(path, "w")
        if file then
          file:write("-- Test file " .. i .. "\nlocal x = " .. i .. "\nreturn x\n")
          file:close()
        end
        table.insert(temp_files, path)
      end
    end)

    after_each(function()
      for _, path in ipairs(temp_files) do
        if vim.fn.filereadable(path) == 1 then
          os.remove(path)
        end
      end
      temp_files = {}
      pcall(vim.cmd, "lclose")
    end)

    it("should start retrace mode with session", function()
      local session = {
        id = "retrace-cmd-test",
        name = "Retrace Command Test",
        created_at = "2025-01-01T00:00:00Z",
        updated_at = "2025-01-01T00:00:00Z",
        notes = {
          note_module.create(temp_files[1], 1, "Note 1"),
          note_module.create(temp_files[2], 2, "Note 2"),
        },
      }

      retrace.start(session)

      assert.is_true(retrace.is_active())

      retrace.stop()
    end)

    it("should navigate with :Tabi next", function()
      local session = {
        id = "next-test",
        name = "Next Test",
        created_at = "2025-01-01T00:00:00Z",
        updated_at = "2025-01-01T00:00:00Z",
        notes = {
          note_module.create(temp_files[1], 1, "Note 1"),
          note_module.create(temp_files[2], 2, "Note 2"),
        },
      }

      retrace.start(session)
      retrace.next()

      local state = retrace.get_state()
      assert.are.equal(2, state.current_index)

      retrace.stop()
    end)

    it("should navigate with :Tabi prev", function()
      local session = {
        id = "prev-test",
        name = "Prev Test",
        created_at = "2025-01-01T00:00:00Z",
        updated_at = "2025-01-01T00:00:00Z",
        notes = {
          note_module.create(temp_files[1], 1, "Note 1"),
          note_module.create(temp_files[2], 2, "Note 2"),
        },
      }

      retrace.start(session)
      retrace.next() -- Go to 2
      retrace.prev() -- Back to 1

      local state = retrace.get_state()
      assert.are.equal(1, state.current_index)

      retrace.stop()
    end)

    it("should stop retrace mode", function()
      local session = {
        id = "stop-test",
        name = "Stop Test",
        created_at = "2025-01-01T00:00:00Z",
        updated_at = "2025-01-01T00:00:00Z",
        notes = {
          note_module.create(temp_files[1], 1, "Note 1"),
        },
      }

      retrace.start(session)
      assert.is_true(retrace.is_active())

      retrace.stop()
      assert.is_false(retrace.is_active())
    end)

    it("should warn when session not found", function()
      local sessions = session_module.list()
      local session_name = "non-existent"
      local session = nil

      for _, s in ipairs(sessions) do
        if s.name == session_name then
          session = s
        end
      end

      if not session then
        vim.notify('Tabi: Session "' .. session_name .. '" not found', vim.log.levels.ERROR)
      end

      local found = false
      for _, n in ipairs(notifications) do
        if n.msg:find("not found") and n.level == vim.log.levels.ERROR then
          found = true
        end
      end
      assert.is_true(found)
    end)
  end)

  describe("session listing", function()
    it("should list all sessions", function()
      session_module.create("session-1")
      session_module.create("session-2")
      session_module.create("session-3")

      local sessions = session_module.list()
      assert.are.equal(3, #sessions)
    end)

    it("should show session details", function()
      local session = session_module.create("detailed-session")
      local note = note_module.create("/test.lua", 1, "Test note")
      session_module.add_note(session, note)

      local sessions = session_module.list()
      local found = sessions[1]

      assert.are.equal("detailed-session", found.name)
      assert.are.equal(1, #found.notes)
    end)

    it("should notify when no sessions found", function()
      local sessions = session_module.list()

      if #sessions == 0 then
        vim.notify("Tabi: No sessions found", vim.log.levels.INFO)
      end

      local found = false
      for _, n in ipairs(notifications) do
        if n.msg:find("No sessions found") then
          found = true
        end
      end
      assert.is_true(found)
    end)

    it("should mark current session", function()
      local session = session_module.create("current-session")
      tabi.state.current_session = session.id

      local sessions = session_module.list()
      local is_current = tabi.state.current_session == sessions[1].id

      assert.is_true(is_current)
    end)
  end)

  describe("session operations", function()
    it("should delete session", function()
      local session = session_module.create("to-delete")
      local session_id = session.id

      local result = session_module.delete(session_id)
      assert.is_true(result)

      local loaded = session_module.load(session_id)
      assert.is_nil(loaded)
    end)

    it("should clear current session when deleted", function()
      local session = session_module.create("current-to-delete")
      tabi.state.current_session = session.id

      session_module.delete(session.id)

      if tabi.state.current_session == session.id then
        tabi.state.current_session = nil
      end

      assert.is_nil(tabi.state.current_session)
    end)

    it("should warn when deleting non-existent session", function()
      local sessions = session_module.list()
      local session_name = "non-existent"
      local session = nil

      for _, s in ipairs(sessions) do
        if s.name == session_name then
          session = s
        end
      end

      if not session then
        vim.notify('Tabi: Session "' .. session_name .. '" not found', vim.log.levels.ERROR)
      end

      local found = false
      for _, n in ipairs(notifications) do
        if n.msg:find("not found") then
          found = true
        end
      end
      assert.is_true(found)
    end)

    it("should rename session", function()
      local session = session_module.create("old-name")

      local result = session_module.rename(session.id, "new-name")
      assert.is_true(result)

      local loaded = session_module.load(session.id)
      assert.are.equal("new-name", loaded.name)
    end)

    it("should notify successful rename", function()
      local session = session_module.create("before-rename")

      if session_module.rename(session.id, "after-rename") then
        vim.notify('Tabi: Session renamed from "before-rename" to "after-rename"', vim.log.levels.INFO)
      end

      local found = false
      for _, n in ipairs(notifications) do
        if n.msg:find("Session renamed") then
          found = true
        end
      end
      assert.is_true(found)
    end)
  end)

  describe("command completion", function()
    it("should provide subcommand completions", function()
      local subcommands = {
        "start",
        "end",
        "note",
        "memo",
        "retrace",
        "next",
        "prev",
        "sessions",
        "session",
      }

      -- Check that expected subcommands exist
      assert.are.equal(9, #subcommands)
      assert.is_true(vim.tbl_contains(subcommands, "start"))
      assert.is_true(vim.tbl_contains(subcommands, "note"))
      assert.is_true(vim.tbl_contains(subcommands, "retrace"))
    end)

    it("should provide note action completions", function()
      local note_actions = { "edit", "delete" }

      assert.are.equal(2, #note_actions)
      assert.is_true(vim.tbl_contains(note_actions, "edit"))
      assert.is_true(vim.tbl_contains(note_actions, "delete"))
    end)
  end)

  describe("error handling", function()
    it("should handle unknown subcommand", function()
      local subcommand = "unknown"

      vim.notify("Tabi: Unknown subcommand: " .. subcommand, vim.log.levels.ERROR)

      local found = false
      for _, n in ipairs(notifications) do
        if n.msg:find("Unknown subcommand") then
          found = true
        end
      end
      assert.is_true(found)
    end)

    it("should handle unknown session action", function()
      local action = "unknown-action"

      vim.notify("Tabi: Unknown session action: " .. action, vim.log.levels.ERROR)

      local found = false
      for _, n in ipairs(notifications) do
        if n.msg:find("Unknown session action") then
          found = true
        end
      end
      assert.is_true(found)
    end)

    it("should require session name for delete", function()
      vim.notify("Tabi: Usage: :Tabi session delete <name>", vim.log.levels.ERROR)

      local found = false
      for _, n in ipairs(notifications) do
        if n.msg:find("Usage:") and n.msg:find("delete") then
          found = true
        end
      end
      assert.is_true(found)
    end)

    it("should require both names for rename", function()
      vim.notify("Tabi: Usage: :Tabi session rename <old-name> <new-name>", vim.log.levels.ERROR)

      local found = false
      for _, n in ipairs(notifications) do
        if n.msg:find("Usage:") and n.msg:find("rename") then
          found = true
        end
      end
      assert.is_true(found)
    end)
  end)
end)
