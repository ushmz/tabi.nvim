local note = require("tabi.note")

describe("tabi.note", function()
  describe("create", function()
    it("should create NoteData with correct fields", function()
      local file_path = "/home/user/project/main.lua"
      local line = 42
      local content = "This is a test note"

      local n = note.create(file_path, line, content)

      assert.is_not_nil(n.id)
      assert.are.equal(file_path, n.file)
      assert.are.equal(line, n.line)
      assert.are.equal(content, n.content)
      assert.is_not_nil(n.created_at)
    end)

    it("should generate UUID for id", function()
      local n = note.create("/test.lua", 1, "test")
      -- UUID v4 format: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
      local pattern = "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-4%x%x%x%-[89ab]%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"
      assert.is_true(n.id:match(pattern) ~= nil, "ID should be UUID v4 format: " .. n.id)
    end)

    it("should generate ISO 8601 timestamp for created_at", function()
      local n = note.create("/test.lua", 1, "test")
      -- ISO 8601 format: YYYY-MM-DDTHH:MM:SSZ
      local pattern = "^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%dZ$"
      assert.is_true(n.created_at:match(pattern) ~= nil, "created_at should be ISO 8601: " .. n.created_at)
    end)

    it("should set end_line to line when not specified", function()
      local n = note.create("/test.lua", 10, "test")
      assert.are.equal(10, n.end_line)
    end)

    it("should use specified end_line", function()
      local n = note.create("/test.lua", 10, "test", 20)
      assert.are.equal(10, n.line)
      assert.are.equal(20, n.end_line)
    end)

    it("should handle empty content", function()
      local n = note.create("/test.lua", 1, "")
      assert.are.equal("", n.content)
    end)
  end)

  describe("get_preview", function()
    it("should truncate to specified length", function()
      local n = note.create("/test.lua", 1, "This is a very long note content that should be truncated")
      local preview = note.get_preview(n, 10)
      assert.are.equal("This is a ...", preview)
    end)

    it("should remove newlines", function()
      local n = note.create("/test.lua", 1, "Line 1\nLine 2\nLine 3")
      local preview = note.get_preview(n, 30)
      assert.is_nil(preview:find("\n"), "Preview should not contain newlines")
      assert.is_true(preview:find("Line 1") ~= nil)
      assert.is_true(preview:find("Line 2") ~= nil)
    end)

    it("should add ellipsis when truncated", function()
      local n = note.create("/test.lua", 1, "This is a long note")
      local preview = note.get_preview(n, 10)
      assert.is_true(preview:sub(-3) == "...", "Preview should end with ...")
    end)

    it("should not add ellipsis when content fits", function()
      local n = note.create("/test.lua", 1, "Short")
      local preview = note.get_preview(n, 30)
      assert.are.equal("Short", preview)
    end)

    it("should use default length when not specified", function()
      local n = note.create("/test.lua", 1, string.rep("x", 100))
      local preview = note.get_preview(n)
      -- Default is 30 characters + "..."
      assert.is_true(#preview <= 33)
    end)
  end)

  describe("get_title", function()
    it("should extract first line", function()
      local n = note.create("/test.lua", 1, "First Line\nSecond Line\nThird Line")
      local title = note.get_title(n)
      assert.are.equal("First Line", title)
    end)

    it("should remove markdown heading markers", function()
      local n = note.create("/test.lua", 1, "# Title with hash")
      local title = note.get_title(n)
      assert.are.equal("Title with hash", title)
    end)

    it("should remove multiple heading markers", function()
      local n = note.create("/test.lua", 1, "### Third level heading")
      local title = note.get_title(n)
      assert.are.equal("Third level heading", title)
    end)

    it("should handle empty content", function()
      local n = note.create("/test.lua", 1, "")
      local title = note.get_title(n)
      assert.are.equal("", title)
    end)

    it("should trim whitespace", function()
      local n = note.create("/test.lua", 1, "  Padded Title  \nBody")
      local title = note.get_title(n)
      assert.are.equal("Padded Title", title)
    end)
  end)

  describe("is_empty", function()
    it("should return true for empty string", function()
      local n = note.create("/test.lua", 1, "")
      assert.is_true(note.is_empty(n))
    end)

    it("should return true for whitespace only", function()
      local n = note.create("/test.lua", 1, "   \n\t  ")
      assert.is_true(note.is_empty(n))
    end)

    it("should return false for content", function()
      local n = note.create("/test.lua", 1, "Some content")
      assert.is_false(note.is_empty(n))
    end)

    it("should return false for content with leading/trailing whitespace", function()
      local n = note.create("/test.lua", 1, "  Content  ")
      assert.is_false(note.is_empty(n))
    end)
  end)

  describe("format", function()
    it("should format single line note as file:line - Title", function()
      local n = note.create("/home/user/project/main.lua", 42, "Note Title\nBody content")
      local formatted = note.format(n)
      assert.are.equal("main.lua:42 - Note Title", formatted)
    end)

    it("should format multi-line note with range", function()
      local n = note.create("/home/user/project/main.lua", 10, "Multi-line note", 20)
      local formatted = note.format(n)
      assert.are.equal("main.lua:10-20 - Multi-line note", formatted)
    end)

    it("should use preview when title is empty", function()
      local n = note.create("/test.lua", 1, "")
      local formatted = note.format(n)
      assert.is_true(formatted:find("test.lua:1") ~= nil)
    end)

    it("should extract filename from full path", function()
      local n = note.create("/very/long/path/to/file.lua", 1, "Title")
      local formatted = note.format(n)
      assert.is_true(formatted:find("^file.lua:") ~= nil)
    end)

    it("should handle same start and end line", function()
      local n = note.create("/test.lua", 5, "Single line", 5)
      local formatted = note.format(n)
      assert.are.equal("test.lua:5 - Single line", formatted)
    end)
  end)
end)
