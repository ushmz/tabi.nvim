local extmarks = require("tabi.extmarks")
local note_module = require("tabi.note")

describe("tabi.extmarks", function()
  local bufnr

  before_each(function()
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "line 1", -- 1
      "line 2", -- 2
      "line 3", -- 3
      "line 4", -- 4
      "line 5", -- 5
      "line 6", -- 6
      "line 7", -- 7
      "line 8", -- 8
      "line 9", -- 9
      "line 10", -- 10
    })
  end)

  after_each(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      extmarks.clear(bufnr)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  describe("track / get_positions", function()
    it("should return the note's initial position", function()
      local note = note_module.create("/test.lua", 3, "test note", 5)
      extmarks.track(bufnr, note)

      local positions = extmarks.get_positions(bufnr)
      assert.are.equal(3, positions[note.id].line)
      assert.are.equal(5, positions[note.id].end_line)
    end)

    it("should return empty table when no notes are tracked", function()
      local positions = extmarks.get_positions(bufnr)
      assert.are.equal(0, vim.tbl_count(positions))
    end)

    it("should track multiple notes independently", function()
      local n1 = note_module.create("/test.lua", 2, "note 1", 3)
      local n2 = note_module.create("/test.lua", 7, "note 2", 9)
      extmarks.track(bufnr, n1)
      extmarks.track(bufnr, n2)

      local positions = extmarks.get_positions(bufnr)
      assert.are.equal(2, positions[n1.id].line)
      assert.are.equal(3, positions[n1.id].end_line)
      assert.are.equal(7, positions[n2.id].line)
      assert.are.equal(9, positions[n2.id].end_line)
    end)

    it("should re-track existing note without duplicating marks", function()
      local note = note_module.create("/test.lua", 4, "note")
      extmarks.track(bufnr, note)
      extmarks.track(bufnr, note) -- re-track same note

      local positions = extmarks.get_positions(bufnr)
      assert.are.equal(1, vim.tbl_count(positions))
      assert.are.equal(4, positions[note.id].line)
    end)
  end)

  describe("position tracking after buffer edits", function()
    it("should move note down when lines are inserted before it", function()
      local note = note_module.create("/test.lua", 5, "test note", 7)
      extmarks.track(bufnr, note)

      -- Insert 2 lines before line 5 (0-indexed row 2 = before line 3)
      vim.api.nvim_buf_set_lines(bufnr, 2, 2, false, { "inserted 1", "inserted 2" })

      local positions = extmarks.get_positions(bufnr)
      assert.are.equal(7, positions[note.id].line)
      assert.are.equal(9, positions[note.id].end_line)
    end)

    it("should move note up when lines are deleted before it", function()
      local note = note_module.create("/test.lua", 6, "test note", 8)
      extmarks.track(bufnr, note)

      -- Delete 2 lines before the note (0-indexed rows 1-2 = lines 2-3)
      vim.api.nvim_buf_set_lines(bufnr, 1, 3, false, {})

      local positions = extmarks.get_positions(bufnr)
      assert.are.equal(4, positions[note.id].line)
      assert.are.equal(6, positions[note.id].end_line)
    end)

    it("should not change note position when lines are inserted after it", function()
      local note = note_module.create("/test.lua", 2, "test note", 4)
      extmarks.track(bufnr, note)

      -- Insert lines well after the note
      vim.api.nvim_buf_set_lines(bufnr, 7, 7, false, { "inserted after" })

      local positions = extmarks.get_positions(bufnr)
      assert.are.equal(2, positions[note.id].line)
      assert.are.equal(4, positions[note.id].end_line)
    end)

    it("should track multiple notes after independent edits", function()
      local n1 = note_module.create("/test.lua", 2, "early note", 3)
      local n2 = note_module.create("/test.lua", 7, "late note", 9)
      extmarks.track(bufnr, n1)
      extmarks.track(bufnr, n2)

      -- Insert 2 lines between the two notes
      vim.api.nvim_buf_set_lines(bufnr, 4, 4, false, { "new line a", "new line b" })

      local positions = extmarks.get_positions(bufnr)
      -- n1 is before the insertion point, should not move
      assert.are.equal(2, positions[n1.id].line)
      assert.are.equal(3, positions[n1.id].end_line)
      -- n2 is after the insertion point, should shift down by 2
      assert.are.equal(9, positions[n2.id].line)
      assert.are.equal(11, positions[n2.id].end_line)
    end)
  end)

  describe("untrack", function()
    it("should remove position tracking for a specific note", function()
      local note = note_module.create("/test.lua", 3, "test note")
      extmarks.track(bufnr, note)

      extmarks.untrack(bufnr, note.id)

      local positions = extmarks.get_positions(bufnr)
      assert.is_nil(positions[note.id])
    end)

    it("should not affect other tracked notes", function()
      local n1 = note_module.create("/test.lua", 2, "note 1")
      local n2 = note_module.create("/test.lua", 5, "note 2")
      extmarks.track(bufnr, n1)
      extmarks.track(bufnr, n2)

      extmarks.untrack(bufnr, n1.id)

      local positions = extmarks.get_positions(bufnr)
      assert.is_nil(positions[n1.id])
      assert.is_not_nil(positions[n2.id])
    end)

    it("should be safe to call for a note that is not tracked", function()
      assert.has_no.errors(function()
        extmarks.untrack(bufnr, "non-existent-id")
      end)
    end)
  end)

  describe("clear", function()
    it("should remove all tracked notes for a buffer", function()
      local n1 = note_module.create("/test.lua", 2, "note 1")
      local n2 = note_module.create("/test.lua", 5, "note 2")
      extmarks.track(bufnr, n1)
      extmarks.track(bufnr, n2)

      extmarks.clear(bufnr)

      local positions = extmarks.get_positions(bufnr)
      assert.are.equal(0, vim.tbl_count(positions))
    end)

    it("should be safe to call on a buffer with no tracked notes", function()
      assert.has_no.errors(function()
        extmarks.clear(bufnr)
      end)
    end)
  end)
end)
