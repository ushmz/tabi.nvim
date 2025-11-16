-- Integration tests for retrace flow
-- Tests end-to-end workflows: select session -> navigate -> modify notes -> cleanup

local session_module = require("tabi.session")
local note_module = require("tabi.note")
local display = require("tabi.ui.display")
local retrace = require("tabi.retrace")
local storage = require("tabi.storage")
local config = require("tabi.config")

describe("integration: retrace flow", function()
  local temp_dir
  local original_backend
  local temp_files = {}
  local ns = vim.api.nvim_create_namespace("tabi")

  before_each(function()
    -- Reset config to defaults
    config.options = vim.deepcopy(config.defaults)

    -- Create temporary directory for test storage
    temp_dir = vim.fn.tempname() .. "_retrace_flow_test"
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

    -- Create temporary files for testing
    for i = 1, 3 do
      local path = vim.fn.tempname() .. "_retrace_flow" .. i .. ".lua"
      local file = io.open(path, "w")
      if file then
        file:write("-- File " .. i .. "\n")
        file:write("local x = " .. i .. "\n")
        file:write("return x\n")
        file:close()
      end
      table.insert(temp_files, path)
    end

    -- Ensure retrace is not active
    if retrace.is_active() then
      retrace.stop()
    end
  end)

  after_each(function()
    -- Restore original backend
    storage.backend = original_backend

    -- Clean up retrace state
    if retrace.is_active() then
      retrace.stop()
    end

    -- Clean up temporary files
    for _, path in ipairs(temp_files) do
      if vim.fn.filereadable(path) == 1 then
        os.remove(path)
      end
    end
    temp_files = {}

    -- Close any open location list windows
    pcall(vim.cmd, "lclose")

    -- Clean up temporary directory
    if vim.fn.isdirectory(temp_dir) == 1 then
      vim.fn.delete(temp_dir, "rf")
    end
  end)

  describe("select -> loclist -> navigate -> stop", function()
    it("should complete full retrace workflow", function()
      -- 1. Create session with notes
      local session = {
        id = "retrace-flow-test",
        name = "Retrace Flow Test",
        created_at = "2025-01-01T00:00:00Z",
        updated_at = "2025-01-01T00:00:00Z",
        notes = {
          note_module.create(temp_files[1], 1, "First note"),
          note_module.create(temp_files[2], 2, "Second note"),
          note_module.create(temp_files[3], 3, "Third note"),
        },
      }

      -- 2. Start retrace mode
      local started = retrace.start(session)
      assert.is_true(started)
      assert.is_true(retrace.is_active())

      -- 3. Verify location list is created
      local state = retrace.get_state()
      local loclist = vim.fn.getloclist(state.loclist_win)
      assert.are.equal(3, #loclist)

      -- 4. Navigate through notes
      assert.are.equal(1, state.current_index)

      retrace.next()
      state = retrace.get_state()
      assert.are.equal(2, state.current_index)

      retrace.next()
      state = retrace.get_state()
      assert.are.equal(3, state.current_index)

      retrace.prev()
      state = retrace.get_state()
      assert.are.equal(2, state.current_index)

      -- 5. Stop retrace mode
      retrace.stop()
      assert.is_false(retrace.is_active())

      -- 6. Verify cleanup
      local state_after = retrace.get_state()
      assert.is_nil(state_after)
    end)
  end)

  describe("add note during retrace", function()
    it("should update virtual lines and location list", function()
      -- Setup session
      local session = {
        id = "add-note-flow",
        name = "Add Note Flow",
        created_at = "2025-01-01T00:00:00Z",
        updated_at = "2025-01-01T00:00:00Z",
        notes = {
          note_module.create(temp_files[1], 1, "First note"),
          note_module.create(temp_files[2], 2, "Second note"),
        },
      }

      -- Start retrace
      retrace.start(session)
      local state = retrace.get_state()
      local initial_count = #vim.fn.getloclist(state.loclist_win)
      assert.are.equal(2, initial_count)

      -- Add new note during retrace
      local new_note = note_module.create(temp_files[3], 3, "New note added during retrace")
      session_module.add_note(session, new_note)

      -- Refresh location list (simulating what command would do)
      retrace.refresh_loclist()

      -- Verify location list updated
      local updated_loclist = vim.fn.getloclist(state.loclist_win)
      assert.are.equal(3, #updated_loclist)

      -- Verify new note is in location list
      local found_new_note = false
      for _, entry in ipairs(updated_loclist) do
        if entry.text:find("New note added") then
          found_new_note = true
        end
      end
      assert.is_true(found_new_note)

      retrace.stop()
    end)

    it("should display all notes as virtual lines", function()
      -- Create a buffer to test virtual lines
      local test_bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
        "-- File 1",
        "local x = 1",
        "return x",
      })

      local session = {
        id = "virtual-line-test",
        name = "Virtual Line Test",
        created_at = "2025-01-01T00:00:00Z",
        updated_at = "2025-01-01T00:00:00Z",
        notes = {
          note_module.create(temp_files[1], 2, "Note at line 2"),
        },
      }

      retrace.start(session)

      -- Display note as virtual line
      display.display_note_as_virtual_line(test_bufnr, session.notes[1])

      -- Verify virtual lines are added
      local extmarks = vim.api.nvim_buf_get_extmarks(test_bufnr, ns, 0, -1, { details = true })
      local found_virt_lines = false
      for _, mark in ipairs(extmarks) do
        if mark[4] and mark[4].virt_lines then
          found_virt_lines = true
          assert.is_true(mark[4].virt_lines_above)
        end
      end
      assert.is_true(found_virt_lines)

      -- Add new note
      local new_note = note_module.create(temp_files[1], 3, "New note at line 3")
      table.insert(session.notes, new_note)

      -- Refresh all displays
      display.clear_buffer(test_bufnr)
      for _, note in ipairs(session.notes) do
        display.display_note_as_virtual_line(test_bufnr, note)
      end

      -- Verify both notes are displayed
      local new_extmarks = vim.api.nvim_buf_get_extmarks(test_bufnr, ns, 0, -1, { details = true })
      local virt_line_count = 0
      for _, mark in ipairs(new_extmarks) do
        if mark[4] and mark[4].virt_lines then
          virt_line_count = virt_line_count + 1
        end
      end
      assert.are.equal(2, virt_line_count)

      retrace.stop()
      vim.api.nvim_buf_delete(test_bufnr, { force = true })
    end)
  end)

  describe("edit note during retrace", function()
    it("should update virtual line display", function()
      local test_bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
        "line 1",
        "line 2",
        "line 3",
      })

      local session = {
        id = "edit-note-flow",
        name = "Edit Note Flow",
        created_at = "2025-01-01T00:00:00Z",
        updated_at = "2025-01-01T00:00:00Z",
        notes = {
          note_module.create(temp_files[1], 2, "Original note content"),
        },
      }

      retrace.start(session)

      -- Display initial state
      display.display_note_as_virtual_line(test_bufnr, session.notes[1])

      -- Verify initial content
      local extmarks_before = vim.api.nvim_buf_get_extmarks(test_bufnr, ns, 0, -1, { details = true })
      local original_content = nil
      for _, mark in ipairs(extmarks_before) do
        if mark[4] and mark[4].virt_lines then
          original_content = mark[4].virt_lines[1][1][1]
        end
      end
      assert.is_not_nil(original_content)
      assert.is_true(original_content:find("Original note content") ~= nil)

      -- Edit note
      session_module.update_note(session, session.notes[1].id, "Updated note content")

      -- Refresh display
      display.clear_buffer(test_bufnr)
      display.display_note_as_virtual_line(test_bufnr, session.notes[1])

      -- Verify updated content
      local extmarks_after = vim.api.nvim_buf_get_extmarks(test_bufnr, ns, 0, -1, { details = true })
      local updated_content = nil
      for _, mark in ipairs(extmarks_after) do
        if mark[4] and mark[4].virt_lines then
          updated_content = mark[4].virt_lines[1][1][1]
        end
      end
      assert.is_not_nil(updated_content)
      assert.is_true(updated_content:find("Updated note content") ~= nil)

      retrace.stop()
      vim.api.nvim_buf_delete(test_bufnr, { force = true })
    end)
  end)

  describe("delete note during retrace", function()
    it("should update virtual lines and location list", function()
      local session = {
        id = "delete-note-flow",
        name = "Delete Note Flow",
        created_at = "2025-01-01T00:00:00Z",
        updated_at = "2025-01-01T00:00:00Z",
        notes = {
          note_module.create(temp_files[1], 1, "Note 1"),
          note_module.create(temp_files[2], 2, "Note 2"),
          note_module.create(temp_files[3], 3, "Note 3"),
        },
      }

      retrace.start(session)

      local state = retrace.get_state()
      local initial_count = #vim.fn.getloclist(state.loclist_win)
      assert.are.equal(3, initial_count)

      -- Delete middle note
      local note_to_delete = session.notes[2]
      session_module.remove_note(session, note_to_delete.id)

      -- Refresh location list
      retrace.refresh_loclist()

      -- Verify location list updated
      local updated_loclist = vim.fn.getloclist(state.loclist_win)
      assert.are.equal(2, #updated_loclist)

      -- Verify deleted note is not in location list
      local found_deleted_note = false
      for _, entry in ipairs(updated_loclist) do
        if entry.text:find("Note 2") then
          found_deleted_note = true
        end
      end
      assert.is_false(found_deleted_note)

      retrace.stop()
    end)

    it("should adjust current index when deleting current note", function()
      local session = {
        id = "delete-current-flow",
        name = "Delete Current Flow",
        created_at = "2025-01-01T00:00:00Z",
        updated_at = "2025-01-01T00:00:00Z",
        notes = {
          note_module.create(temp_files[1], 1, "Note 1"),
          note_module.create(temp_files[2], 2, "Note 2"),
          note_module.create(temp_files[3], 3, "Note 3"),
        },
      }

      retrace.start(session)

      -- Move to last note
      retrace.next() -- 2
      retrace.next() -- 3
      assert.are.equal(3, retrace.get_state().current_index)

      -- Delete last note
      table.remove(session.notes, 3)

      -- Refresh location list
      retrace.refresh_loclist()

      -- Index should be adjusted
      assert.are.equal(2, retrace.get_state().current_index)

      retrace.stop()
    end)
  end)

  describe("retrace state consistency", function()
    it("should maintain session reference throughout retrace", function()
      local session = {
        id = "state-consistency",
        name = "State Consistency Test",
        created_at = "2025-01-01T00:00:00Z",
        updated_at = "2025-01-01T00:00:00Z",
        notes = {
          note_module.create(temp_files[1], 1, "Note 1"),
        },
      }

      retrace.start(session)

      local state = retrace.get_state()
      assert.are.equal(session.id, state.session.id)

      -- Add note to session
      local new_note = note_module.create(temp_files[2], 2, "Note 2")
      table.insert(session.notes, new_note)

      -- Refresh and check state still points to same session
      retrace.refresh_loclist()
      local state_after = retrace.get_state()
      assert.are.equal(session.id, state_after.session.id)
      assert.are.equal(2, #state_after.session.notes)

      retrace.stop()
    end)
  end)
end)
