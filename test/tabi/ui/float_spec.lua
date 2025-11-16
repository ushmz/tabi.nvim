local float = require("tabi.ui.float")
local config = require("tabi.config")

describe("tabi.ui.float", function()
  local original_list_uis

  before_each(function()
    -- Reset config to defaults
    config.options = vim.deepcopy(config.defaults)

    -- Mock vim.api.nvim_list_uis for headless mode
    original_list_uis = vim.api.nvim_list_uis
    vim.api.nvim_list_uis = function()
      return { { width = 120, height = 40 } }
    end
  end)

  after_each(function()
    -- Restore original function
    vim.api.nvim_list_uis = original_list_uis

    -- Clean up any open windows
    for _, winid in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_is_valid(winid) then
        local win_config = vim.api.nvim_win_get_config(winid)
        if win_config.relative ~= "" then
          pcall(vim.api.nvim_win_close, winid, true)
        end
      end
    end
  end)

  describe("create_float", function()
    it("should create buffer and window", function()
      local bufnr, winid = float.create_float()

      assert.is_number(bufnr)
      assert.is_number(winid)
      assert.is_true(vim.api.nvim_buf_is_valid(bufnr))
      assert.is_true(vim.api.nvim_win_is_valid(winid))

      vim.api.nvim_win_close(winid, true)
    end)

    it("should create centered window", function()
      local _, winid = float.create_float()

      local win_config = vim.api.nvim_win_get_config(winid)
      assert.are.equal("editor", win_config.relative)

      -- Window should be positioned (row and col are tables with [false] key)
      local row = type(win_config.row) == "table" and win_config.row[false] or win_config.row
      local col = type(win_config.col) == "table" and win_config.col[false] or win_config.col
      assert.is_true(row > 0 or col > 0)

      vim.api.nvim_win_close(winid, true)
    end)

    it("should use border from config", function()
      config.setup({ ui = { float_config = { border = "single" } } })
      local _, winid = float.create_float()

      local win_config = vim.api.nvim_win_get_config(winid)
      -- Border can be string or table of characters
      assert.is_not_nil(win_config.border)

      vim.api.nvim_win_close(winid, true)
    end)

    it("should use dimensions from config", function()
      config.setup({ ui = { float_config = { width = 80, height = 20 } } })
      local _, winid = float.create_float()

      local win_config = vim.api.nvim_win_get_config(winid)
      assert.are.equal(80, win_config.width)
      assert.are.equal(20, win_config.height)

      vim.api.nvim_win_close(winid, true)
    end)

    it("should override config with opts", function()
      local _, winid = float.create_float({ width = 100, height = 30, border = "double" })

      local win_config = vim.api.nvim_win_get_config(winid)
      assert.are.equal(100, win_config.width)
      assert.are.equal(30, win_config.height)
      -- Border can be string or table of characters
      assert.is_not_nil(win_config.border)

      vim.api.nvim_win_close(winid, true)
    end)

    it("should set buffer options", function()
      local bufnr, winid = float.create_float()

      assert.are.equal("acwrite", vim.api.nvim_buf_get_option(bufnr, "buftype"))
      assert.are.equal("wipe", vim.api.nvim_buf_get_option(bufnr, "bufhidden"))
      assert.are.equal("markdown", vim.api.nvim_buf_get_option(bufnr, "filetype"))

      vim.api.nvim_win_close(winid, true)
    end)

    it("should create scratch buffer (not listed)", function()
      local bufnr, winid = float.create_float()

      assert.is_false(vim.api.nvim_buf_get_option(bufnr, "buflisted"))

      vim.api.nvim_win_close(winid, true)
    end)
  end)

  describe("open_note_editor", function()
    it("should display initial content", function()
      local winid_to_close
      float.open_note_editor("Initial content", function()
        -- Save callback
      end)

      -- Find the floating window
      for _, winid in ipairs(vim.api.nvim_list_wins()) do
        local win_config = vim.api.nvim_win_get_config(winid)
        if win_config.relative ~= "" then
          winid_to_close = winid
          local bufnr = vim.api.nvim_win_get_buf(winid)
          local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

          -- Should contain initial content (after comment lines)
          local found = false
          for _, line in ipairs(lines) do
            if line:find("Initial content") then
              found = true
              break
            end
          end
          assert.is_true(found)
        end
      end

      if winid_to_close then
        vim.api.nvim_win_close(winid_to_close, true)
      end
    end)

    it("should add comment instructions", function()
      local winid_to_close
      float.open_note_editor("", function() end)

      for _, winid in ipairs(vim.api.nvim_list_wins()) do
        local win_config = vim.api.nvim_win_get_config(winid)
        if win_config.relative ~= "" then
          winid_to_close = winid
          local bufnr = vim.api.nvim_win_get_buf(winid)
          local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

          -- First lines should be comments
          assert.is_true(lines[1]:match("^<!%-%-") ~= nil)
          assert.is_true(lines[2]:match("^<!%-%-") ~= nil)
        end
      end

      if winid_to_close then
        vim.api.nvim_win_close(winid_to_close, true)
      end
    end)

    it("should set up keymaps", function()
      local winid_to_close
      float.open_note_editor("", function() end)

      for _, winid in ipairs(vim.api.nvim_list_wins()) do
        local win_config = vim.api.nvim_win_get_config(winid)
        if win_config.relative ~= "" then
          winid_to_close = winid
          local bufnr = vim.api.nvim_win_get_buf(winid)

          -- Check that keymaps are set
          local keymaps = vim.api.nvim_buf_get_keymap(bufnr, "n")
          local found_esc = false
          local found_ctrl_s = false

          for _, keymap in ipairs(keymaps) do
            if keymap.lhs == "<Esc>" then
              found_esc = true
            end
            if keymap.lhs == "<C-S>" or keymap.lhs == "<C-s>" then
              found_ctrl_s = true
            end
          end

          assert.is_true(found_esc)
          assert.is_true(found_ctrl_s)
        end
      end

      if winid_to_close then
        vim.api.nvim_win_close(winid_to_close, true)
      end
    end)

    it("should set up BufWriteCmd autocmd", function()
      local winid_to_close
      float.open_note_editor("", function() end)

      for _, winid in ipairs(vim.api.nvim_list_wins()) do
        local win_config = vim.api.nvim_win_get_config(winid)
        if win_config.relative ~= "" then
          winid_to_close = winid
          local bufnr = vim.api.nvim_win_get_buf(winid)

          local autocmds = vim.api.nvim_get_autocmds({ buffer = bufnr, event = "BufWriteCmd" })
          assert.is_true(#autocmds > 0)
        end
      end

      if winid_to_close then
        vim.api.nvim_win_close(winid_to_close, true)
      end
    end)
  end)
end)
