local display = require("tabi.ui.display")
local note_module = require("tabi.note")
local config = require("tabi.config")

describe("tabi.ui.display", function()
  local bufnr
  local ns = vim.api.nvim_create_namespace("tabi")

  before_each(function()
    -- Create a test buffer with some content
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "line 1",
      "line 2",
      "line 3",
      "line 4",
      "line 5",
    })
    -- Reset config to defaults
    config.options = vim.deepcopy(config.defaults)
  end)

  after_each(function()
    -- Clean up buffer
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  describe("init", function()
    it("should define sign", function()
      display.init()
      -- Check that sign is defined
      local signs = vim.fn.sign_getdefined("TabiNote")
      assert.are.equal(1, #signs)
      assert.are.equal("TabiNote", signs[1].name)
    end)

    it("should set sign text highlight", function()
      display.init()
      local signs = vim.fn.sign_getdefined("TabiNote")
      -- Sign should have text highlight defined
      assert.are.equal("TabiNoteSign", signs[1].texthl)
    end)
  end)

  describe("display_note", function()
    before_each(function()
      display.init()
    end)

    it("should place sign at note line", function()
      local note = note_module.create("/test.lua", 2, "Test note")

      display.display_note(bufnr, note)

      local signs = vim.fn.sign_getplaced(bufnr, { group = "tabi" })
      assert.are.equal(1, #signs)
      assert.is_true(#signs[1].signs > 0)
      assert.are.equal(2, signs[1].signs[1].lnum)
    end)

    it("should add virtual text with preview", function()
      local note = note_module.create("/test.lua", 3, "This is a test note")

      display.display_note(bufnr, note)

      -- Get extmarks
      local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
      assert.is_true(#extmarks > 0)

      -- Check virtual text exists
      local found_virt_text = false
      for _, mark in ipairs(extmarks) do
        if mark[4] and mark[4].virt_text then
          found_virt_text = true
          -- Check that virtual text contains note preview
          local virt_text = mark[4].virt_text[1][1]
          assert.is_true(virt_text:find("This is a test note") ~= nil)
        end
      end
      assert.is_true(found_virt_text)
    end)

    it("should respect preview length from config", function()
      config.setup({ ui = { note_preview_length = 10 } })
      local note = note_module.create("/test.lua", 1, "This is a very long note content")

      display.display_note(bufnr, note)

      local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
      for _, mark in ipairs(extmarks) do
        if mark[4] and mark[4].virt_text then
          local virt_text = mark[4].virt_text[1][1]
          -- Should be truncated (10 chars + "...")
          assert.is_true(#virt_text <= 20) -- space + 10 chars + "..."
        end
      end
    end)

    it("should not display for invalid buffer", function()
      local invalid_bufnr = 99999
      local note = note_module.create("/test.lua", 1, "Test")

      -- Should not throw error
      display.display_note(invalid_bufnr, note)
    end)
  end)

  describe("display_note_as_virtual_line", function()
    before_each(function()
      display.init()
    end)

    it("should add virtual lines above target line", function()
      local note = note_module.create("/test.lua", 3, "Virtual line note")

      display.display_note_as_virtual_line(bufnr, note)

      local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
      local found_virt_lines = false
      for _, mark in ipairs(extmarks) do
        if mark[4] and mark[4].virt_lines then
          found_virt_lines = true
          assert.is_true(mark[4].virt_lines_above)
        end
      end
      assert.is_true(found_virt_lines)
    end)

    it("should support multi-line note content", function()
      local note = note_module.create("/test.lua", 2, "Line 1\nLine 2\nLine 3")

      display.display_note_as_virtual_line(bufnr, note)

      local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
      for _, mark in ipairs(extmarks) do
        if mark[4] and mark[4].virt_lines then
          -- Should have 3 virtual lines
          assert.are.equal(3, #mark[4].virt_lines)
        end
      end
    end)

    it("should place sign at note line", function()
      local note = note_module.create("/test.lua", 4, "Test")

      display.display_note_as_virtual_line(bufnr, note)

      local signs = vim.fn.sign_getplaced(bufnr, { group = "tabi" })
      assert.is_true(#signs[1].signs > 0)
      assert.are.equal(4, signs[1].signs[1].lnum)
    end)
  end)

  describe("clear_buffer", function()
    before_each(function()
      display.init()
    end)

    it("should remove all extmarks", function()
      local note = note_module.create("/test.lua", 1, "Test")
      display.display_note(bufnr, note)

      -- Verify extmarks exist
      local before = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
      assert.is_true(#before > 0)

      display.clear_buffer(bufnr)

      local after = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
      assert.are.equal(0, #after)
    end)

    it("should remove all signs", function()
      local note = note_module.create("/test.lua", 2, "Test")
      display.display_note(bufnr, note)

      display.clear_buffer(bufnr)

      local signs = vim.fn.sign_getplaced(bufnr, { group = "tabi" })
      assert.are.equal(0, #signs[1].signs)
    end)
  end)

  describe("refresh_buffer", function()
    before_each(function()
      display.init()
    end)

    it("should clear and re-display notes", function()
      local notes = {
        note_module.create("/test.lua", 1, "Note 1"),
        note_module.create("/test.lua", 3, "Note 2"),
      }

      display.refresh_buffer(bufnr, notes)

      local signs = vim.fn.sign_getplaced(bufnr, { group = "tabi" })
      assert.are.equal(2, #signs[1].signs)
    end)

    it("should handle empty notes array", function()
      display.refresh_buffer(bufnr, {})

      local signs = vim.fn.sign_getplaced(bufnr, { group = "tabi" })
      assert.are.equal(0, #signs[1].signs)
    end)
  end)

  describe("setup_autocmds", function()
    it("should create TabiDisplay augroup", function()
      local session = {
        id = "test",
        name = "Test",
        notes = {},
      }

      display.setup_autocmds(session)

      -- Check that augroup exists
      local groups = vim.api.nvim_get_autocmds({ group = "TabiDisplay" })
      assert.is_true(#groups > 0)

      -- Clean up
      display.clear_autocmds()
    end)

    it("should register BufEnter autocmd", function()
      local session = {
        id = "test",
        name = "Test",
        notes = {},
      }

      display.setup_autocmds(session)

      local autocmds = vim.api.nvim_get_autocmds({ group = "TabiDisplay", event = "BufEnter" })
      assert.is_true(#autocmds > 0)

      display.clear_autocmds()
    end)

    it("should register BufWinEnter autocmd", function()
      local session = {
        id = "test",
        name = "Test",
        notes = {},
      }

      display.setup_autocmds(session)

      local autocmds = vim.api.nvim_get_autocmds({ group = "TabiDisplay", event = "BufWinEnter" })
      assert.is_true(#autocmds > 0)

      display.clear_autocmds()
    end)
  end)

  describe("clear_autocmds", function()
    it("should remove TabiDisplay group", function()
      local session = {
        id = "test",
        name = "Test",
        notes = {},
      }

      display.setup_autocmds(session)
      display.clear_autocmds()

      local autocmds = vim.api.nvim_get_autocmds({ group = "TabiDisplay" })
      assert.are.equal(0, #autocmds)
    end)
  end)
end)
