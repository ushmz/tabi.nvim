local selector = require("tabi.ui.selector.native")
local session_module = require("tabi.session")
local storage = require("tabi.storage")

describe("tabi.ui.selector.native", function()
  local temp_dir
  local original_backend
  local original_ui_select

  before_each(function()
    -- Create temporary directory for test storage
    temp_dir = vim.fn.tempname() .. "_tabi_selector_test"
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
        table.sort(sessions, function(a, b)
          return a.updated_at > b.updated_at
        end)
        return sessions
      end,
    }

    -- Save original vim.ui.select
    original_ui_select = vim.ui.select
  end)

  after_each(function()
    -- Restore original backend
    storage.backend = original_backend

    -- Restore original vim.ui.select
    vim.ui.select = original_ui_select

    -- Clean up temporary directory
    if vim.fn.isdirectory(temp_dir) == 1 then
      vim.fn.delete(temp_dir, "rf")
    end
  end)

  describe("select_session", function()
    it("should call vim.ui.select", function()
      -- Create test sessions
      session_module.create("session1")
      session_module.create("session2")

      local ui_select_called = false
      vim.ui.select = function(items, opts, _on_choice)
        ui_select_called = true
        assert.is_table(items)
        assert.are.equal(2, #items)
        assert.is_table(opts)
        assert.are.equal("Select session:", opts.prompt)
      end

      selector.select_session(function() end)

      assert.is_true(ui_select_called)
    end)

    it("should format session as 'name (X notes, YYYY-MM-DD)'", function()
      local s = session_module.create("test-format")
      -- Add some notes
      s.notes = {
        { id = "1" },
        { id = "2" },
        { id = "3" },
      }
      session_module.save(s)

      vim.ui.select = function(items)
        assert.are.equal(1, #items)
        -- Should contain name, note count, and date
        assert.is_true(items[1]:find("test%-format") ~= nil)
        assert.is_true(items[1]:find("3 notes") ~= nil)
        -- Should contain date in YYYY-MM-DD format
        assert.is_true(items[1]:match("%d%d%d%d%-%d%d%-%d%d") ~= nil)
      end

      selector.select_session(function() end)
    end)

    it("should execute callback with selected session", function()
      local s = session_module.create("selected")
      local selected_session = nil

      vim.ui.select = function(_, _, on_choice)
        -- Simulate user selection
        on_choice("selected (0 notes, 2025-01-01)", 1)
      end

      selector.select_session(function(session)
        selected_session = session
      end)

      -- Need to process the vim.schedule
      vim.wait(100, function()
        return selected_session ~= nil
      end)

      assert.is_not_nil(selected_session)
      assert.are.equal(s.id, selected_session.id)
    end)

    it("should call on_cancel when cancelled", function()
      session_module.create("test")
      local cancel_called = false

      vim.ui.select = function(_, _, on_choice)
        -- Simulate cancel (nil choice)
        on_choice(nil, nil)
      end

      selector.select_session(function() end, {
        on_cancel = function()
          cancel_called = true
        end,
      })

      assert.is_true(cancel_called)
    end)

    it("should notify when no sessions found", function()
      -- No sessions created
      local notify_called = false
      local original_notify = vim.notify

      vim.notify = function(msg, level)
        if msg:find("No sessions found") then
          notify_called = true
          assert.are.equal(vim.log.levels.WARN, level)
        end
      end

      selector.select_session(function() end)

      vim.notify = original_notify
      assert.is_true(notify_called)
    end)

    it("should not call vim.ui.select when no sessions", function()
      local ui_select_called = false
      vim.ui.select = function()
        ui_select_called = true
      end

      selector.select_session(function() end)

      assert.is_false(ui_select_called)
    end)
  end)
end)
