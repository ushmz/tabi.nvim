local mini_selector = require("tabi.ui.selector.mini")
local session_module = require("tabi.session")
local storage = require("tabi.storage")
local config = require("tabi.config")

describe("tabi.ui.selector.mini", function()
  local temp_dir
  local original_backend
  local original_notify
  local original_minipick
  local original_config

  before_each(function()
    -- Create temporary directory for test storage
    temp_dir = vim.fn.tempname() .. "_tabi_mini_test"
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

    -- Save original notify
    original_notify = vim.notify

    -- Save original global MiniPick
    original_minipick = _G.MiniPick
    _G.MiniPick = nil

    -- Save original config
    original_config = vim.deepcopy(config.options)
  end)

  after_each(function()
    -- Restore original backend
    storage.backend = original_backend

    -- Restore original notify
    vim.notify = original_notify

    -- Restore original global MiniPick
    _G.MiniPick = original_minipick

    -- Restore original config
    config.options = original_config

    -- Clean up temporary directory
    if vim.fn.isdirectory(temp_dir) == 1 then
      vim.fn.delete(temp_dir, "rf")
    end
  end)

  describe("select_session", function()
    it("should notify when no sessions found", function()
      local notify_called = false
      vim.notify = function(msg, level)
        if msg:find("No sessions found") then
          notify_called = true
          assert.are.equal(vim.log.levels.WARN, level)
        end
      end

      mini_selector.select_session(function() end)

      assert.is_true(notify_called)
    end)

    it("should notify error when mini.pick is not available", function()
      session_module.create("test")

      local notify_called = false
      vim.notify = function(msg, level)
        if msg:find("mini.pick is not installed") then
          notify_called = true
          assert.are.equal(vim.log.levels.ERROR, level)
        end
      end

      mini_selector.select_session(function() end)

      assert.is_true(notify_called)
    end)

    describe("with mini.pick available", function()
      local mock_start

      before_each(function()
        mock_start = {
          called = false,
          last_opts = nil,
          return_value = nil,
        }
        _G.MiniPick = {
          start = function(start_opts)
            mock_start.called = true
            mock_start.last_opts = start_opts
            return mock_start.return_value
          end,
        }
      end)

      it("should pass session items to the picker source", function()
        session_module.create("session1")
        session_module.create("session2")

        mini_selector.select_session(function() end)

        assert.is_true(mock_start.called)
        assert.is_not_nil(mock_start.last_opts.source)
        assert.are.equal(2, #mock_start.last_opts.source.items)
        assert.are.equal("Sessions", mock_start.last_opts.source.name)
      end)

      it("should format item text with name, note count, date and branch", function()
        local s = session_module.create("my-session")
        s.notes = { { id = "1" }, { id = "2" }, { id = "3" } }
        s.branch = "feature/test"
        session_module.save(s)

        mini_selector.select_session(function() end)

        local item = mock_start.last_opts.source.items[1]
        assert.is_truthy(item.text:find("my%-session"))
        assert.is_truthy(item.text:find("3 notes"))
        assert.is_truthy(item.text:find("%d%d%d%d%-%d%d%-%d%d"))
        assert.is_truthy(item.text:find("feature/test"))
        assert.are.equal(s.id, item.session.id)
      end)

      it("should show session details and notes in preview", function()
        local s = session_module.create("preview-test")
        s.notes = {
          { id = "1", file = "test.lua", line = 10, content = "First note" },
          { id = "2", file = "test.lua", line = 20, content = "Second note" },
        }
        session_module.save(s)

        mini_selector.select_session(function() end)

        local item = mock_start.last_opts.source.items[1]
        local bufnr = vim.api.nvim_create_buf(false, true)
        mock_start.last_opts.source.preview(bufnr, item)

        local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        local content = table.concat(lines, "\n")
        assert.is_truthy(content:find("preview%-test"))
        assert.is_truthy(content:find("Notes: 2"))
        assert.is_truthy(content:find("test.lua:10"))
        assert.is_truthy(content:find("First note"))

        vim.api.nvim_buf_delete(bufnr, { force = true })
      end)

      it("should call on_select with the chosen session", function()
        local s = session_module.create("selected")
        local selected_session = nil

        mock_start.return_value = { session = s }

        mini_selector.select_session(function(session)
          selected_session = session
        end)

        vim.wait(100, function()
          return selected_session ~= nil
        end)

        assert.is_not_nil(selected_session)
        assert.are.equal(s.id, selected_session.id)
      end)

      it("should call on_cancel when the picker returns nil", function()
        session_module.create("test")
        local cancel_called = false

        mock_start.return_value = nil

        mini_selector.select_session(function() end, {
          on_cancel = function()
            cancel_called = true
          end,
        })

        vim.wait(100, function()
          return cancel_called
        end)

        assert.is_true(cancel_called)
      end)

      it("should not error when cancelled without on_cancel", function()
        session_module.create("test")

        mock_start.return_value = nil

        assert.has_no.errors(function()
          mini_selector.select_session(function() end)
        end)
      end)

      it("should instruct the picker to stop on choose", function()
        session_module.create("test")

        mini_selector.select_session(function() end)

        local choose = mock_start.last_opts.source.choose
        assert.is_false(choose({}))
      end)

      it("should pass through ui.mini.opts to MiniPick.start", function()
        session_module.create("test")
        config.options.ui.mini.opts = {
          window = { config = { width = 80 } },
          mappings = { choose = "<CR>" },
        }

        mini_selector.select_session(function() end)

        assert.are.equal(80, mock_start.last_opts.window.config.width)
        assert.are.equal("<CR>", mock_start.last_opts.mappings.choose)
      end)

      it("should not allow ui.mini.opts to override the source", function()
        session_module.create("test")
        config.options.ui.mini.opts = {
          source = { name = "Hijacked" },
        }

        mini_selector.select_session(function() end)

        assert.are.equal("Sessions", mock_start.last_opts.source.name)
      end)
    end)
  end)
end)
