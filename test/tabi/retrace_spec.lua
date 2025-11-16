local retrace = require("tabi.retrace")
local note_module = require("tabi.note")
local display = require("tabi.ui.display")

describe("tabi.retrace", function()
  local test_session
  local temp_files = {}

  before_each(function()
    -- Initialize display
    display.init()

    -- Create temporary files for testing
    for i = 1, 3 do
      local path = vim.fn.tempname() .. "_test" .. i .. ".lua"
      local file = io.open(path, "w")
      if file then
        file:write("-- Test file " .. i .. "\nlocal x = " .. i .. "\nreturn x\n")
        file:close()
      end
      table.insert(temp_files, path)
    end

    -- Create test session with notes
    test_session = {
      id = "test-retrace",
      name = "Test Retrace",
      created_at = "2025-01-01T00:00:00Z",
      updated_at = "2025-01-01T00:00:00Z",
      notes = {
        note_module.create(temp_files[1], 1, "First note"),
        note_module.create(temp_files[2], 2, "Second note"),
        note_module.create(temp_files[3], 3, "Third note"),
      },
    }

    -- Ensure retrace is not active
    if retrace.is_active() then
      retrace.stop()
    end
  end)

  after_each(function()
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
  end)

  describe("start", function()
    it("should set location list", function()
      retrace.start(test_session)

      local loclist = vim.fn.getloclist(0)
      assert.are.equal(3, #loclist)
      assert.is_true(loclist[1].text:find("First note") ~= nil)
    end)

    it("should initialize state", function()
      retrace.start(test_session)

      assert.is_true(retrace.is_active())
      local state = retrace.get_state()
      assert.is_not_nil(state)
      assert.are.equal(1, state.current_index)
      assert.are.equal(test_session.id, state.session.id)
    end)

    it("should return false when session has no notes", function()
      local empty_session = {
        id = "empty",
        name = "Empty",
        notes = {},
      }

      local result = retrace.start(empty_session)
      assert.is_false(result)
      assert.is_false(retrace.is_active())
    end)

    it("should return true on success", function()
      local result = retrace.start(test_session)
      assert.is_true(result)
    end)
  end)

  describe("stop", function()
    it("should clear location list", function()
      retrace.start(test_session)
      local winid = vim.api.nvim_get_current_win()

      retrace.stop()

      -- Location list should be empty
      local loclist = vim.fn.getloclist(winid)
      assert.are.equal(0, #loclist)
    end)

    it("should reset state", function()
      retrace.start(test_session)
      retrace.stop()

      assert.is_false(retrace.is_active())
      assert.is_nil(retrace.get_state())
    end)

    it("should notify when not in retrace mode", function()
      local notify_called = false
      local original_notify = vim.notify

      vim.notify = function(msg, level)
        if msg:find("Not in retrace mode") then
          notify_called = true
          assert.are.equal(vim.log.levels.WARN, level)
        end
      end

      retrace.stop()

      vim.notify = original_notify
      assert.is_true(notify_called)
    end)
  end)

  describe("next", function()
    it("should move to next note", function()
      retrace.start(test_session)

      retrace.next()

      local state = retrace.get_state()
      assert.are.equal(2, state.current_index)
    end)

    it("should not go past last note", function()
      retrace.start(test_session)

      -- Move to last note
      retrace.next() -- 2
      retrace.next() -- 3

      local notify_called = false
      local original_notify = vim.notify
      vim.notify = function(msg)
        if msg:find("last note") then
          notify_called = true
        end
      end

      retrace.next() -- Should stay at 3

      vim.notify = original_notify

      local state = retrace.get_state()
      assert.are.equal(3, state.current_index)
      assert.is_true(notify_called)
    end)

    it("should notify when not in retrace mode", function()
      local notify_called = false
      local original_notify = vim.notify

      vim.notify = function(msg, _level)
        if msg:find("Not in retrace mode") then
          notify_called = true
        end
      end

      retrace.next()

      vim.notify = original_notify
      assert.is_true(notify_called)
    end)
  end)

  describe("prev", function()
    it("should move to previous note", function()
      retrace.start(test_session)
      retrace.next() -- Move to 2

      retrace.prev()

      local state = retrace.get_state()
      assert.are.equal(1, state.current_index)
    end)

    it("should not go before first note", function()
      retrace.start(test_session)

      local notify_called = false
      local original_notify = vim.notify
      vim.notify = function(msg)
        if msg:find("first note") then
          notify_called = true
        end
      end

      retrace.prev() -- Should stay at 1

      vim.notify = original_notify

      local state = retrace.get_state()
      assert.are.equal(1, state.current_index)
      assert.is_true(notify_called)
    end)

    it("should notify when not in retrace mode", function()
      local notify_called = false
      local original_notify = vim.notify

      vim.notify = function(msg)
        if msg:find("Not in retrace mode") then
          notify_called = true
        end
      end

      retrace.prev()

      vim.notify = original_notify
      assert.is_true(notify_called)
    end)
  end)

  describe("is_active", function()
    it("should return true when active", function()
      retrace.start(test_session)
      assert.is_true(retrace.is_active())
    end)

    it("should return false when not active", function()
      assert.is_false(retrace.is_active())
    end)

    it("should return false after stop", function()
      retrace.start(test_session)
      retrace.stop()
      assert.is_false(retrace.is_active())
    end)
  end)

  describe("get_state", function()
    it("should return current state", function()
      retrace.start(test_session)

      local state = retrace.get_state()
      assert.is_table(state)
      assert.is_not_nil(state.session)
      assert.is_number(state.current_index)
      assert.is_number(state.loclist_win)
    end)

    it("should return nil when not active", function()
      local state = retrace.get_state()
      assert.is_nil(state)
    end)
  end)

  describe("refresh_loclist", function()
    it("should rebuild location list", function()
      retrace.start(test_session)

      -- Add a new note to session
      local new_note = note_module.create(temp_files[1], 10, "New note")
      table.insert(test_session.notes, new_note)

      retrace.refresh_loclist()

      local winid = retrace.get_state().loclist_win
      local loclist = vim.fn.getloclist(winid)
      assert.are.equal(4, #loclist)
    end)

    it("should adjust current index if out of bounds", function()
      retrace.start(test_session)

      -- Move to last note
      retrace.next()
      retrace.next()
      assert.are.equal(3, retrace.get_state().current_index)

      -- Remove last note
      table.remove(test_session.notes, 3)

      retrace.refresh_loclist()

      -- Index should be adjusted
      assert.are.equal(2, retrace.get_state().current_index)
    end)

    it("should do nothing when not active", function()
      -- Should not throw error
      retrace.refresh_loclist()
      assert.is_false(retrace.is_active())
    end)
  end)

  describe("show_current", function()
    it("should notify current position", function()
      retrace.start(test_session)

      local notify_msg = nil
      local original_notify = vim.notify
      vim.notify = function(msg)
        notify_msg = msg
      end

      retrace.show_current()

      vim.notify = original_notify
      assert.is_not_nil(notify_msg)
      assert.is_true(notify_msg:find("Note 1/3") ~= nil)
    end)

    it("should be silent when silent=true", function()
      retrace.start(test_session)

      local notify_called = false
      local original_notify = vim.notify
      vim.notify = function()
        notify_called = true
      end

      retrace.show_current(true)

      vim.notify = original_notify
      assert.is_false(notify_called)
    end)

    it("should notify when not in retrace mode", function()
      local notify_called = false
      local original_notify = vim.notify

      vim.notify = function(msg)
        if msg:find("Not in retrace mode") then
          notify_called = true
        end
      end

      retrace.show_current()

      vim.notify = original_notify
      assert.is_true(notify_called)
    end)
  end)
end)
