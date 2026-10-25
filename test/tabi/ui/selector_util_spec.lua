local selector_util = require("tabi.ui.selector.util")

describe("tabi.ui.selector.util", function()
  local function make_session(notes)
    return {
      id = "session-id",
      name = "my-session",
      branch = "main",
      created_at = "2024-01-01T00:00:00Z",
      updated_at = "2024-01-02T00:00:00Z",
      notes = notes or {},
    }
  end

  describe("build_preview_lines", function()
    it("should include session details", function()
      local lines = selector_util.build_preview_lines(make_session())

      assert.are.equal("Session: my-session", lines[1])
      assert.are.equal("ID: session-id", lines[2])
      assert.are.equal("Branch: main", lines[3])
      assert.are.equal("Notes: 0", lines[6])
      assert.are.equal("--- Notes ---", lines[8])
    end)

    it("should show N/A when branch is missing", function()
      local session = make_session()
      session.branch = nil

      local lines = selector_util.build_preview_lines(session)

      assert.are.equal("Branch: N/A", lines[3])
    end)

    it("should list notes with location and first line of content", function()
      local lines = selector_util.build_preview_lines(make_session({
        { file = "a.lua", line = 10, content = "first line\nsecond line" },
      }))

      assert.are.equal("1. a.lua:10", lines[9])
      assert.are.equal("   first line", lines[10])
    end)

    it("should use the first non-empty line when content starts with a newline", function()
      local lines = selector_util.build_preview_lines(make_session({
        { file = "a.lua", line = 1, content = "\n\nactual content\nmore" },
      }))

      assert.are.equal("   actual content", lines[10])
      local bufnr = vim.api.nvim_create_buf(false, true)
      assert.has_no.errors(function()
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
      end)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should handle content consisting only of newlines", function()
      local lines = selector_util.build_preview_lines(make_session({
        { file = "a.lua", line = 1, content = "\n\n" },
      }))

      assert.are.equal("   ", lines[10])
    end)

    it("should truncate long note content", function()
      local lines = selector_util.build_preview_lines(make_session({
        { file = "a.lua", line = 1, content = string.rep("a", 100) },
      }))

      assert.are.equal("   " .. string.rep("a", 57) .. "...", lines[10])
    end)

    it("should truncate multibyte note content by characters", function()
      local lines = selector_util.build_preview_lines(make_session({
        { file = "a.lua", line = 1, content = string.rep("あ", 100) },
      }))

      assert.are.equal("   " .. string.rep("あ", 57) .. "...", lines[10])
    end)

    it("should not truncate multibyte note content within the limit", function()
      local content = string.rep("あ", 60)
      local lines = selector_util.build_preview_lines(make_session({
        { file = "a.lua", line = 1, content = content },
      }))

      assert.are.equal("   " .. content, lines[10])
    end)
  end)
end)
