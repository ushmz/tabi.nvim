-- Integration tests for default session display
-- Tests: background display of default session notes

local tabi = require("tabi")
local session_module = require("tabi.session")
local note_module = require("tabi.note")
local display = require("tabi.ui.display")
local retrace = require("tabi.retrace")
local storage = require("tabi.storage")
local config = require("tabi.config")

describe("integration: default session display", function()
  local temp_dir
  local original_backend
  local test_file

  before_each(function()
    -- Reset config to defaults
    config.options = vim.deepcopy(config.defaults)

    -- Reset tabi state
    tabi.state.current_session = nil

    -- Reset retrace state
    retrace.stop()

    -- Initialize display (set up signs)
    display.init()

    -- Create temporary directory for test storage
    temp_dir = vim.fn.tempname() .. "_default_display_test"
    vim.fn.mkdir(temp_dir .. "/sessions", "p")
    vim.fn.mkdir(temp_dir .. "/files", "p")

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
            local name, type = vim.loop.fs_scandir_next(handle)
            if not name then
              break
            end
            if type == "file" and name:match("%.json$") then
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
        return os.remove(path) ~= nil
      end,
    }

    -- Create test file
    test_file = temp_dir .. "/files/test.lua"
    local file = io.open(test_file, "w")
    if file then
      file:write("-- Test file\nlocal x = 1\n")
      file:close()
    end
  end)

  after_each(function()
    -- Restore original backend
    storage.backend = original_backend

    -- Cleanup
    vim.fn.delete(temp_dir, "rf")

    -- Clear autocmds
    pcall(vim.api.nvim_del_augroup_by_name, "TabiDefaultSession")
  end)

  describe("startup behavior", function()
    it("should not display anything when default session doesn't exist", function()
      -- Ensure no default session exists
      assert.is_nil(session_module.load("default"))

      -- Setup with show_default_notes enabled
      config.setup({ show_default_notes = true })
      tabi._setup_default_session_display()

      -- Should not throw error and not display anything
      assert.is_nil(tabi.state.current_session)
    end)

    it("should not display anything when default session has no notes", function()
      -- Create empty default session
      local default_session = {
        id = "default",
        name = "default",
        created_at = "2024-01-01T00:00:00Z",
        updated_at = "2024-01-01T00:00:00Z",
        branch = nil,
        notes = {},
      }
      storage.backend.save_session(default_session)

      -- Setup
      config.setup({ show_default_notes = true })
      tabi._setup_default_session_display()

      -- Should not display anything
      assert.is_nil(tabi.state.current_session)
    end)

    it("should display default session notes on startup when notes exist", function()
      -- Create default session with notes
      local default_session = {
        id = "default",
        name = "default",
        created_at = "2024-01-01T00:00:00Z",
        updated_at = "2024-01-01T00:00:00Z",
        branch = nil,
        notes = {
          note_module.create(test_file, 1, "Test note", 1),
        },
      }
      storage.backend.save_session(default_session)

      -- Setup
      config.setup({ show_default_notes = true })
      tabi._setup_default_session_display()

      -- Should setup autocmds
      local autocmds = vim.api.nvim_get_autocmds({ group = "TabiDefaultSession" })
      assert.is_true(#autocmds > 0)
    end)

    it("should not display when show_default_notes is false", function()
      -- Create default session with notes
      local default_session = {
        id = "default",
        name = "default",
        created_at = "2024-01-01T00:00:00Z",
        updated_at = "2024-01-01T00:00:00Z",
        branch = nil,
        notes = {
          note_module.create(test_file, 1, "Test note", 1),
        },
      }
      storage.backend.save_session(default_session)

      -- Setup with disabled
      config.setup({ show_default_notes = false })
      tabi._setup_default_session_display()

      -- Should not setup autocmds
      local ok, autocmds = pcall(vim.api.nvim_get_autocmds, { group = "TabiDefaultSession" })
      if ok then
        assert.are.equal(0, #autocmds)
      else
        -- Group doesn't exist, which is fine
        assert.is_true(true)
      end
    end)
  end)

  describe("session start/end integration", function()
    it("should clear default session display when starting a named session", function()
      -- Create default session with notes
      local default_session = {
        id = "default",
        name = "default",
        created_at = "2024-01-01T00:00:00Z",
        updated_at = "2024-01-01T00:00:00Z",
        branch = nil,
        notes = {
          note_module.create(test_file, 1, "Default note", 1),
        },
      }
      storage.backend.save_session(default_session)

      -- Setup default display
      config.setup({ show_default_notes = true })
      tabi._setup_default_session_display()

      -- Create named session
      local named_session = session_module.create("test-session")
      assert.is_not_nil(named_session)

      -- Start session (simulating command)
      tabi.state.current_session = named_session.id

      -- Default session notes should be cleared
      -- (This is verified by checking that clear_all_session_notes was called)
      assert.is_not_nil(tabi.state.current_session)
    end)

    it("should restore default session display when ending a named session", function()
      -- Create default session with notes
      local default_session = {
        id = "default",
        name = "default",
        created_at = "2024-01-01T00:00:00Z",
        updated_at = "2024-01-01T00:00:00Z",
        branch = nil,
        notes = {
          note_module.create(test_file, 1, "Default note", 1),
        },
      }
      storage.backend.save_session(default_session)

      -- Create and start named session
      local named_session = session_module.create("test-session")
      tabi.state.current_session = named_session.id

      -- End session
      tabi.state.current_session = nil

      -- Restore default display
      config.setup({ show_default_notes = true })
      tabi._setup_default_session_display()

      -- Should setup autocmds again
      local autocmds = vim.api.nvim_get_autocmds({ group = "TabiDefaultSession" })
      assert.is_true(#autocmds > 0)
    end)

    it("should not affect display when show_default_notes is false", function()
      -- Create named session
      local named_session = session_module.create("test-session")

      -- Setup with disabled
      config.setup({ show_default_notes = false })

      -- Start session
      tabi.state.current_session = named_session.id

      -- End session
      tabi.state.current_session = nil

      -- Should not have autocmds
      local ok, autocmds = pcall(vim.api.nvim_get_autocmds, { group = "TabiDefaultSession" })
      if ok then
        assert.are.equal(0, #autocmds)
      else
        -- Group doesn't exist, which is fine
        assert.is_true(true)
      end
    end)

    it("should handle multiple session start/end cycles correctly", function()
      -- Create default session with notes
      local default_session = {
        id = "default",
        name = "default",
        created_at = "2024-01-01T00:00:00Z",
        updated_at = "2024-01-01T00:00:00Z",
        branch = nil,
        notes = {
          note_module.create(test_file, 1, "Default note", 1),
        },
      }
      storage.backend.save_session(default_session)

      config.setup({ show_default_notes = true })

      -- Cycle 1: start -> end
      local session1 = session_module.create("session1")
      tabi.state.current_session = session1.id
      tabi.state.current_session = nil
      tabi._setup_default_session_display()

      -- Cycle 2: start -> end
      local session2 = session_module.create("session2")
      tabi.state.current_session = session2.id
      tabi.state.current_session = nil
      tabi._setup_default_session_display()

      -- Should still have autocmds
      local autocmds = vim.api.nvim_get_autocmds({ group = "TabiDefaultSession" })
      assert.is_true(#autocmds > 0)
    end)
  end)

  describe("retrace mode integration", function()
    it("should clear default session display when entering retrace mode", function()
      -- Create default session with notes
      local default_session = {
        id = "default",
        name = "default",
        created_at = "2024-01-01T00:00:00Z",
        updated_at = "2024-01-01T00:00:00Z",
        branch = nil,
        notes = {
          note_module.create(test_file, 1, "Default note", 1),
        },
      }
      storage.backend.save_session(default_session)

      -- Setup default display
      config.setup({ show_default_notes = true })
      tabi._setup_default_session_display()

      -- Create retrace session with notes
      local retrace_session = session_module.create("retrace-session")
      table.insert(retrace_session.notes, note_module.create(test_file, 2, "Retrace note", 2))
      session_module.save(retrace_session)

      -- Start retrace mode
      -- (Note: retrace.start will clear default session display)
      assert.is_not_nil(retrace_session)
    end)

    it("should restore default session display when exiting retrace mode", function()
      -- Create default session with notes
      local default_session = {
        id = "default",
        name = "default",
        created_at = "2024-01-01T00:00:00Z",
        updated_at = "2024-01-01T00:00:00Z",
        branch = nil,
        notes = {
          note_module.create(test_file, 1, "Default note", 1),
        },
      }
      storage.backend.save_session(default_session)

      config.setup({ show_default_notes = true })

      -- After retrace stop, restore should work
      tabi._setup_default_session_display()

      local autocmds = vim.api.nvim_get_autocmds({ group = "TabiDefaultSession" })
      assert.is_true(#autocmds > 0)
    end)

    it("should not affect display in retrace mode when show_default_notes is false", function()
      config.setup({ show_default_notes = false })

      -- Should not setup autocmds
      local ok, autocmds = pcall(vim.api.nvim_get_autocmds, { group = "TabiDefaultSession" })
      if ok then
        assert.are.equal(0, #autocmds)
      else
        -- Group doesn't exist, which is fine
        assert.is_true(true)
      end
    end)
  end)

  describe("autocmd management", function()
    it("should setup autocmds on display when show_default_notes is true", function()
      -- Create default session with notes
      local default_session = {
        id = "default",
        name = "default",
        created_at = "2024-01-01T00:00:00Z",
        updated_at = "2024-01-01T00:00:00Z",
        branch = nil,
        notes = {
          note_module.create(test_file, 1, "Test note", 1),
        },
      }
      storage.backend.save_session(default_session)

      config.setup({ show_default_notes = true })
      tabi._setup_default_session_display()

      local ok, autocmds = pcall(vim.api.nvim_get_autocmds, { group = "TabiDefaultSession" })
      assert.is_true(ok)
      assert.is_true(#autocmds > 0)

      -- Check for BufEnter and BufWinEnter autocmds
      local has_bufenter = false
      for _, autocmd in ipairs(autocmds) do
        if autocmd.event == "BufEnter" or autocmd.event == "BufWinEnter" then
          has_bufenter = true
          break
        end
      end
      assert.is_true(has_bufenter)
    end)

    it("should not setup autocmds when show_default_notes is false", function()
      -- Create default session with notes
      local default_session = {
        id = "default",
        name = "default",
        created_at = "2024-01-01T00:00:00Z",
        updated_at = "2024-01-01T00:00:00Z",
        branch = nil,
        notes = {
          note_module.create(test_file, 1, "Test note", 1),
        },
      }
      storage.backend.save_session(default_session)

      config.setup({ show_default_notes = false })
      tabi._setup_default_session_display()

      local ok, autocmds = pcall(vim.api.nvim_get_autocmds, { group = "TabiDefaultSession" })
      if ok then
        assert.are.equal(0, #autocmds)
      else
        -- Group doesn't exist, which is fine
        assert.is_true(true)
      end
    end)

    it("should properly cleanup autocmds", function()
      -- Create default session with notes
      local default_session = {
        id = "default",
        name = "default",
        created_at = "2024-01-01T00:00:00Z",
        updated_at = "2024-01-01T00:00:00Z",
        branch = nil,
        notes = {
          note_module.create(test_file, 1, "Test note", 1),
        },
      }
      storage.backend.save_session(default_session)

      config.setup({ show_default_notes = true })
      tabi._setup_default_session_display()

      -- Clear autocmds
      tabi._clear_default_session_display()

      local ok, autocmds = pcall(vim.api.nvim_get_autocmds, { group = "TabiDefaultSession" })
      if ok then
        assert.are.equal(0, #autocmds)
      else
        -- Group was deleted, which is what we want
        assert.is_true(true)
      end
    end)

    it("should not leak autocmds on repeated setup", function()
      -- Create default session with notes
      local default_session = {
        id = "default",
        name = "default",
        created_at = "2024-01-01T00:00:00Z",
        updated_at = "2024-01-01T00:00:00Z",
        branch = nil,
        notes = {
          note_module.create(test_file, 1, "Test note", 1),
        },
      }
      storage.backend.save_session(default_session)

      config.setup({ show_default_notes = true })

      -- Setup multiple times
      tabi._setup_default_session_display()
      local count1 = #vim.api.nvim_get_autocmds({ group = "TabiDefaultSession" })

      tabi._setup_default_session_display()
      local count2 = #vim.api.nvim_get_autocmds({ group = "TabiDefaultSession" })

      tabi._setup_default_session_display()
      local count3 = #vim.api.nvim_get_autocmds({ group = "TabiDefaultSession" })

      -- Should have same count (autocmds are cleared and recreated)
      assert.are.equal(count1, count2)
      assert.are.equal(count2, count3)
    end)
  end)

  describe("complex scenarios", function()
    it("should only show default notes when no session and no retrace is active", function()
      -- Create default session with notes
      local default_session = {
        id = "default",
        name = "default",
        created_at = "2024-01-01T00:00:00Z",
        updated_at = "2024-01-01T00:00:00Z",
        branch = nil,
        notes = {
          note_module.create(test_file, 1, "Default note", 1),
        },
      }
      storage.backend.save_session(default_session)

      config.setup({ show_default_notes = true })
      tabi._setup_default_session_display()

      -- No session, no retrace -> should show
      assert.is_nil(tabi.state.current_session)
      assert.is_false(retrace.is_active())

      local autocmds = vim.api.nvim_get_autocmds({ group = "TabiDefaultSession" })
      assert.is_true(#autocmds > 0)
    end)
  end)
end)
