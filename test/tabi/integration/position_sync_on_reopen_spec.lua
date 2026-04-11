-- Integration test: note position after file edit → save → close → reopen
--
-- Scenario:
--   1. Note is added at line N
--   2. A line is inserted before line N (extmarks track the note to line N+1)
--   3. File is saved → BufWritePre syncs positions to storage (note stored as N+1)
--   4. Buffer is closed → extmarks are cleared
--   5. File is reopened → BufEnter should display note at N+1, not the stale N

local tabi = require("tabi")
local session_module = require("tabi.session")
local note_module = require("tabi.note")
local display = require("tabi.ui.display")
local extmarks = require("tabi.extmarks")
local storage = require("tabi.storage")

describe("integration: note position sync on file reopen", function()
  local temp_dir
  local original_backend
  local bufnr
  local file_path

  before_each(function()
    temp_dir = vim.fn.tempname() .. "_pos_sync_test"
    vim.fn.mkdir(temp_dir .. "/sessions", "p")

    original_backend = storage.backend
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
        return ok and decoded or nil
      end,
      list_sessions = function()
        return {}
      end,
      delete_session = function(id)
        local path = temp_dir .. "/sessions/" .. id .. ".json"
        return os.remove(path) ~= nil
      end,
      session_exists = function(id)
        local path = temp_dir .. "/sessions/" .. id .. ".json"
        return vim.fn.filereadable(path) == 1
      end,
    }

    -- Register BufWritePre handler that mirrors plugin/tabi.lua.
    -- This is the actual code under test: it must check tabi.state.current_session
    -- and load a fresh session from storage before syncing.
    vim.api.nvim_create_augroup("TabiPositionSyncTest", { clear = true })
    vim.api.nvim_create_autocmd("BufWritePre", {
      group = "TabiPositionSyncTest",
      callback = function(args)
        if not tabi.state.current_session then
          return
        end
        local session = session_module.load(tabi.state.current_session)
        if session then
          session_module.sync_positions_from_extmarks(session, args.buf)
        end
      end,
    })

    display.init()

    -- Create a real temp file
    local temp_path = vim.fn.tempname() .. "_pos_sync.lua"
    local lines = {}
    for i = 1, 20 do
      table.insert(lines, "line " .. i)
    end
    local f = io.open(temp_path, "w")
    if f then
      f:write(table.concat(lines, "\n") .. "\n")
      f:close()
    end

    bufnr = vim.fn.bufadd(temp_path)
    vim.fn.bufload(bufnr)
    vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
    file_path = vim.api.nvim_buf_get_name(bufnr)
  end)

  after_each(function()
    tabi.state.current_session = nil

    storage.backend = original_backend
    display.clear_autocmds()
    pcall(vim.api.nvim_del_augroup_by_name, "TabiPositionSyncTest")

    if vim.api.nvim_buf_is_valid(bufnr) then
      extmarks.clear(bufnr)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end

    if vim.fn.filereadable(file_path) == 1 then
      os.remove(file_path)
    end

    if vim.fn.isdirectory(temp_dir) == 1 then
      vim.fn.delete(temp_dir, "rf")
    end
  end)

  it("should display note at updated position when file is reopened after an edit", function()
    -- Step 1: create session with note at line 5
    local sess = session_module.create("pos-sync-test")
    local note = note_module.create(file_path, 5, "test note")
    session_module.add_note(sess, note)

    -- Step 2: set up autocmds and extmarks
    -- tabi.state.current_session must be set; without it the BufWritePre handler early-returns.
    tabi.state.current_session = sess.id
    display.setup_autocmds(sess)
    extmarks.track(bufnr, note)

    -- Step 3: simulate buffer edit
    --   Insert 3 lines at row index 1 (before line 2), so note shifts from line 5 to line 8.
    vim.api.nvim_buf_set_lines(bufnr, 1, 1, false, { "inserted 1", "inserted 2", "inserted 3" })

    -- Step 4: fire BufWritePre via the autocmd (tests the real handler path).
    --   The handler checks tabi.state.current_session, loads a fresh session from
    --   storage, and calls sync_positions_from_extmarks — same as plugin/tabi.lua.
    vim.api.nvim_exec_autocmds("BufWritePre", { buffer = bufnr })

    -- Verify storage has the updated position
    local stored = session_module.load(sess.id)
    assert.are.equal(8, stored.notes[1].line, "storage must have the synced line")

    -- Step 5: simulate buffer close (extmarks cleared)
    extmarks.clear(bufnr)
    display.clear_buffer(bufnr)

    -- Step 6: simulate BufEnter (file reopened)
    vim.api.nvim_exec_autocmds("BufEnter", { buffer = bufnr })

    -- The BufEnter callback must load the fresh session from storage
    -- and set up extmarks at line 8, not the stale line 5.
    local positions = extmarks.get_positions(bufnr)
    assert.is_not_nil(positions[note.id], "extmark should be registered after BufEnter")
    assert.are.equal(8, positions[note.id].line, "extmark should be at updated line 8, not stale line 5")
  end)

  it("should not sync when tabi.state.current_session is nil", function()
    -- Regression guard: BufWritePre must be a no-op when no session is active.
    local sess = session_module.create("pos-sync-no-state-test")
    local note = note_module.create(file_path, 5, "test note")
    session_module.add_note(sess, note)

    -- Intentionally do NOT set tabi.state.current_session
    extmarks.track(bufnr, note)
    vim.api.nvim_buf_set_lines(bufnr, 1, 1, false, { "inserted 1", "inserted 2", "inserted 3" })

    vim.api.nvim_exec_autocmds("BufWritePre", { buffer = bufnr })

    -- Storage must still have the original line 5 (sync was skipped)
    local stored = session_module.load(sess.id)
    assert.are.equal(5, stored.notes[1].line, "position must not be updated when no session is active")
  end)

  it("should display note at original position when no edits were made before reopen", function()
    -- Regression guard: if nothing changed, position should stay the same
    local sess = session_module.create("pos-sync-no-edit-test")
    local note = note_module.create(file_path, 10, "stable note")
    session_module.add_note(sess, note)

    tabi.state.current_session = sess.id
    display.setup_autocmds(sess)

    -- No edits – simulate buffer close then reopen
    extmarks.clear(bufnr)
    display.clear_buffer(bufnr)

    vim.api.nvim_exec_autocmds("BufEnter", { buffer = bufnr })

    local positions = extmarks.get_positions(bufnr)
    assert.is_not_nil(positions[note.id])
    assert.are.equal(10, positions[note.id].line)
  end)
end)
