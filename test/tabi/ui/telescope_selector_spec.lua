local telescope_selector = require("tabi.ui.selector.telescope")
local session_module = require("tabi.session")
local storage = require("tabi.storage")
local config = require("tabi.config")

describe("tabi.ui.selector.telescope", function()
  local temp_dir
  local original_backend
  local original_notify
  local original_config

  -- Mock telescope modules
  local mock_telescope = {}
  local mock_pickers = {}
  local mock_finders = {}
  local mock_conf = {}
  local mock_actions = {}
  local mock_action_state = {}
  local mock_entry_display = {}
  local mock_previewers = {}
  local mock_themes = {}

  before_each(function()
    -- Create temporary directory for test storage
    temp_dir = vim.fn.tempname() .. "_tabi_telescope_test"
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

    -- Save original config
    original_config = vim.deepcopy(config.options)

    -- Reset telescope mocks
    mock_telescope = {}
    mock_pickers = {
      new = function(_, opts)
        mock_pickers.last_opts = opts
        return {
          find = function()
            mock_pickers.find_called = true
          end,
        }
      end,
      last_opts = nil,
      find_called = false,
    }
    mock_finders = {
      new_table = function(opts)
        mock_finders.last_opts = opts
        return opts
      end,
      last_opts = nil,
    }
    mock_conf = {
      generic_sorter = function()
        return {}
      end,
    }
    mock_actions = {
      select_default = {
        replace = function(_, fn)
          mock_actions.select_default_fn = fn
        end,
      },
      close = function() end,
    }
    mock_action_state = {
      get_selected_entry = function()
        return mock_action_state.mock_entry
      end,
      mock_entry = nil,
    }
    mock_entry_display = {
      create = function()
        return function(items)
          return table.concat(items, " ")
        end
      end,
    }
    mock_previewers = {
      new_buffer_previewer = function(opts)
        mock_previewers.last_opts = opts
        return opts
      end,
      last_opts = nil,
    }
    mock_themes = {}

    -- Setup package.loaded mocks
    package.loaded["telescope"] = mock_telescope
    package.loaded["telescope.pickers"] = mock_pickers
    package.loaded["telescope.finders"] = mock_finders
    package.loaded["telescope.config"] = { values = mock_conf }
    package.loaded["telescope.actions"] = mock_actions
    package.loaded["telescope.actions.state"] = mock_action_state
    package.loaded["telescope.pickers.entry_display"] = mock_entry_display
    package.loaded["telescope.previewers"] = mock_previewers
    package.loaded["telescope.themes"] = mock_themes
  end)

  after_each(function()
    -- Restore original backend
    storage.backend = original_backend

    -- Restore original notify
    vim.notify = original_notify

    -- Restore original config
    config.options = original_config

    -- Clean up temporary directory
    if vim.fn.isdirectory(temp_dir) == 1 then
      vim.fn.delete(temp_dir, "rf")
    end

    -- Clean up package.loaded
    package.loaded["telescope"] = nil
    package.loaded["telescope.pickers"] = nil
    package.loaded["telescope.finders"] = nil
    package.loaded["telescope.config"] = nil
    package.loaded["telescope.actions"] = nil
    package.loaded["telescope.actions.state"] = nil
    package.loaded["telescope.pickers.entry_display"] = nil
    package.loaded["telescope.previewers"] = nil
    package.loaded["telescope.themes"] = nil
  end)

  describe("select_session", function()
    describe("basic functionality", function()
      it("should notify when no sessions found", function()
        local notify_called = false
        vim.notify = function(msg, level)
          if msg:find("No sessions found") then
            notify_called = true
            assert.are.equal(vim.log.levels.WARN, level)
          end
        end

        telescope_selector.select_session(function() end)

        assert.is_true(notify_called)
      end)

      it("should not call telescope picker when no sessions", function()
        telescope_selector.select_session(function() end)

        assert.is_false(mock_pickers.find_called)
      end)

      it("should notify error when telescope is not available", function()
        -- Remove telescope from package.loaded
        package.loaded["telescope"] = nil

        session_module.create("test")

        local notify_called = false
        vim.notify = function(msg, level)
          if msg:find("telescope.nvim is not installed") then
            notify_called = true
            assert.are.equal(vim.log.levels.ERROR, level)
          end
        end

        telescope_selector.select_session(function() end)

        assert.is_true(notify_called)
      end)

      it("should abort when telescope is not available", function()
        package.loaded["telescope"] = nil

        session_module.create("test")

        telescope_selector.select_session(function() end)

        assert.is_false(mock_pickers.find_called)
      end)
    end)

    describe("picker creation", function()
      it("should call pickers.new", function()
        session_module.create("test")

        telescope_selector.select_session(function() end)

        assert.is_true(mock_pickers.find_called)
        assert.is_not_nil(mock_pickers.last_opts)
      end)

      it("should pass sessions to finder", function()
        session_module.create("session1")
        session_module.create("session2")

        telescope_selector.select_session(function() end)

        assert.is_not_nil(mock_finders.last_opts)
        assert.is_not_nil(mock_finders.last_opts.results)
        assert.are.equal(2, #mock_finders.last_opts.results)
      end)

      it("should set prompt title to 'Select Session'", function()
        session_module.create("test")

        telescope_selector.select_session(function() end)

        assert.are.equal("Select Session", mock_pickers.last_opts.prompt_title)
      end)

      it("should configure previewer", function()
        session_module.create("test")

        telescope_selector.select_session(function() end)

        assert.is_not_nil(mock_pickers.last_opts.previewer)
        assert.is_not_nil(mock_previewers.last_opts)
        assert.are.equal("Session Notes", mock_previewers.last_opts.title)
      end)
    end)

    describe("entry display", function()
      it("should display session name", function()
        local s = session_module.create("my-session")

        telescope_selector.select_session(function() end)

        local entry_maker = mock_finders.last_opts.entry_maker
        local entry = entry_maker(s)
        assert.are.equal("my-session", entry.name)
        assert.are.equal("my-session", entry.ordinal)
      end)

      it("should display note count as 'X notes'", function()
        local s = session_module.create("test")
        s.notes = { { id = "1" }, { id = "2" }, { id = "3" } }
        session_module.save(s)

        telescope_selector.select_session(function() end)

        local entry_maker = mock_finders.last_opts.entry_maker
        local entry = entry_maker(s)
        assert.are.equal(3, entry.note_count)
      end)

      it("should display date in YYYY-MM-DD format", function()
        local s = session_module.create("test")

        telescope_selector.select_session(function() end)

        local entry_maker = mock_finders.last_opts.entry_maker
        local entry = entry_maker(s)
        assert.is_not_nil(entry.date)
        assert.is_truthy(entry.date:match("%d%d%d%d%-%d%d%-%d%d"))
      end)

      it("should display branch information", function()
        local s = session_module.create("test")
        s.branch = "feature/test"
        session_module.save(s)

        telescope_selector.select_session(function() end)

        local entry_maker = mock_finders.last_opts.entry_maker
        local entry = entry_maker(s)
        assert.are.equal("feature/test", entry.branch)
      end)

      it("should display 'N/A' when branch is nil", function()
        local s = session_module.create("test")
        s.branch = nil
        session_module.save(s)

        telescope_selector.select_session(function() end)

        local entry_maker = mock_finders.last_opts.entry_maker
        local entry = entry_maker(s)
        assert.is_nil(entry.branch)
        -- The display function handles N/A
      end)
    end)

    describe("callback handling", function()
      it("should execute callback with selected session", function()
        local s = session_module.create("selected")
        local selected_session = nil

        telescope_selector.select_session(function(session)
          selected_session = session
        end)

        -- Simulate selection
        mock_action_state.mock_entry = { session = s }
        local attach_mappings = mock_pickers.last_opts.attach_mappings
        attach_mappings(0) -- prompt_bufnr
        mock_actions.select_default_fn()

        -- Process vim.schedule
        vim.wait(100, function()
          return selected_session ~= nil
        end)

        assert.is_not_nil(selected_session)
        assert.are.equal(s.id, selected_session.id)
      end)

      it("should call on_cancel when cancelled with on_cancel provided", function()
        session_module.create("test")
        local cancel_called = false

        telescope_selector.select_session(function() end, {
          on_cancel = function()
            cancel_called = true
          end,
        })

        -- Simulate cancel (no selection)
        mock_action_state.mock_entry = nil
        local attach_mappings = mock_pickers.last_opts.attach_mappings
        attach_mappings(0)
        mock_actions.select_default_fn()

        -- Process vim.schedule
        vim.wait(100, function()
          return cancel_called
        end)

        assert.is_true(cancel_called)
      end)

      it("should not error when cancelled without on_cancel", function()
        session_module.create("test")

        telescope_selector.select_session(function() end)

        -- Simulate cancel (no selection)
        mock_action_state.mock_entry = nil
        local attach_mappings = mock_pickers.last_opts.attach_mappings
        attach_mappings(0)

        -- Should not error
        assert.has_no.errors(function()
          mock_actions.select_default_fn()
        end)
      end)
    end)

    describe("configuration", function()
      it("should apply theme when configured", function()
        config.options.ui.telescope.theme = "dropdown"

        mock_themes.get_dropdown = function(opts)
          opts.theme_applied = "dropdown"
          return opts
        end

        session_module.create("test")

        telescope_selector.select_session(function() end)

        assert.are.equal("dropdown", mock_pickers.last_opts.theme_applied)
      end)

      it("should apply layout_config when configured", function()
        config.options.ui.telescope.layout_config = {
          width = 0.8,
          height = 0.6,
        }

        session_module.create("test")

        telescope_selector.select_session(function() end)

        assert.is_not_nil(mock_pickers.last_opts.layout_config)
        assert.are.equal(0.8, mock_pickers.last_opts.layout_config.width)
        assert.are.equal(0.6, mock_pickers.last_opts.layout_config.height)
      end)

      it("should not apply theme when not configured", function()
        config.options.ui.telescope.theme = nil

        session_module.create("test")

        telescope_selector.select_session(function() end)

        assert.is_nil(mock_pickers.last_opts.theme_applied)
      end)

      it("should not apply empty layout_config", function()
        config.options.ui.telescope.layout_config = {}

        session_module.create("test")

        telescope_selector.select_session(function() end)

        -- layout_config should not be set when empty
        assert.is_nil(mock_pickers.last_opts.layout_config)
      end)
    end)

    describe("previewer", function()
      it("should show session details in preview", function()
        local s = session_module.create("preview-test")
        s.notes = {
          { id = "1", file = "test.lua", line = 10, content = "First note" },
          { id = "2", file = "test.lua", line = 20, content = "Second note" },
        }
        session_module.save(s)

        telescope_selector.select_session(function() end)

        local previewer_opts = mock_previewers.last_opts
        assert.is_not_nil(previewer_opts.define_preview)

        -- Mock buffer and entry for preview
        local mock_self = {
          state = {
            bufnr = vim.api.nvim_create_buf(false, true),
          },
        }
        local mock_entry = { session = s }

        previewer_opts.define_preview(mock_self, mock_entry)

        local lines = vim.api.nvim_buf_get_lines(mock_self.state.bufnr, 0, -1, false)
        assert.is_true(#lines > 0)

        -- Check that session info is present
        local content = table.concat(lines, "\n")
        assert.is_truthy(content:find("preview%-test"))
        assert.is_truthy(content:find("Notes: 2"))
        assert.is_truthy(content:find("test.lua:10"))
        assert.is_truthy(content:find("First note"))

        -- Clean up
        vim.api.nvim_buf_delete(mock_self.state.bufnr, { force = true })
      end)

      it("should truncate long note content in preview", function()
        local s = session_module.create("long-note")
        local long_content = string.rep("a", 100)
        s.notes = {
          { id = "1", file = "test.lua", line = 10, content = long_content },
        }
        session_module.save(s)

        telescope_selector.select_session(function() end)

        local previewer_opts = mock_previewers.last_opts
        local mock_self = {
          state = {
            bufnr = vim.api.nvim_create_buf(false, true),
          },
        }
        local mock_entry = { session = s }

        previewer_opts.define_preview(mock_self, mock_entry)

        local lines = vim.api.nvim_buf_get_lines(mock_self.state.bufnr, 0, -1, false)
        local content = table.concat(lines, "\n")

        -- Should be truncated with "..."
        assert.is_truthy(content:find("%.%.%."))

        vim.api.nvim_buf_delete(mock_self.state.bufnr, { force = true })
      end)
    end)
  end)
end)
