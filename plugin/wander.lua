-- Wander.nvim - Code Reading Session Manager
-- Plugin initialization and command registration

if vim.g.loaded_wander then
  return
end
vim.g.loaded_wander = 1

-- Load modules
local wander = require('wander')
local session_module = require('wander.session')
local note_module = require('wander.note')
local float = require('wander.ui.float')
local display = require('wander.ui.display')
local retrace = require('wander.retrace')
local selector = require('wander.ui.selector.native')

-- Initialize display
display.init()

-- Command implementations
local commands = {}

--- Start a new session
function commands.start_session(args)
  local session_name = args[2]

  if wander.state.current_session then
    local current = session_module.load(wander.state.current_session)
    if current then
      vim.notify('Wander: Session "' .. current.name .. '" is already active. End it first.', vim.log.levels.WARN)
      return
    end
  end

  local session = session_module.create(session_name)
  if not session then
    return
  end

  wander.state.current_session = session.id
  display.setup_autocmds(session)

  vim.notify('Wander: Session "' .. session.name .. '" started', vim.log.levels.INFO)
end

--- End the current session
function commands.end_session()
  if not wander.state.current_session then
    vim.notify('Wander: No active session', vim.log.levels.WARN)
    return
  end

  local session = session_module.load(wander.state.current_session)
  if session then
    vim.notify('Wander: Session "' .. session.name .. '" ended', vim.log.levels.INFO)
  end

  wander.state.current_session = nil
  display.clear_autocmds()

  -- Clear all displays
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      display.clear_buffer(bufnr)
    end
  end
end

--- Create or edit a note
function commands.note(args)
  local action = args[2]

  if action == 'edit' then
    commands.note_edit()
    return
  elseif action == 'delete' then
    commands.note_delete()
    return
  end

  -- Create new note
  local bufnr = vim.api.nvim_get_current_buf()
  local file_path = vim.api.nvim_buf_get_name(bufnr)

  if file_path == '' then
    vim.notify('Wander: Cannot add note to unnamed buffer', vim.log.levels.ERROR)
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]

  -- Get or create session
  local session
  if wander.state.current_session then
    session = session_module.load(wander.state.current_session)
  end

  if not session then
    session = session_module.get_or_create_default()
    wander.state.current_session = session.id
    display.setup_autocmds(session)
  end

  -- Check if note already exists at this line
  local existing_note = session_module.get_note_at_line(session, file_path, line)

  float.open_note_editor(existing_note and existing_note.content or '', function(content)
    if content == '' then
      vim.notify('Wander: Empty note not saved', vim.log.levels.WARN)
      return
    end

    if existing_note then
      -- Update existing note
      session_module.update_note(session, existing_note.id, content)
      vim.notify('Wander: Note updated', vim.log.levels.INFO)
    else
      -- Create new note
      local note = note_module.create(file_path, line, content)
      session_module.add_note(session, note)
      vim.notify('Wander: Note added', vim.log.levels.INFO)
    end

    -- Refresh display
    display.update_for_session(bufnr, session)
  end)
end

--- Edit note at cursor
function commands.note_edit()
  local bufnr = vim.api.nvim_get_current_buf()
  local file_path = vim.api.nvim_buf_get_name(bufnr)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]

  local session
  if wander.state.current_session then
    session = session_module.load(wander.state.current_session)
  else
    session = session_module.get_or_create_default()
    wander.state.current_session = session.id
  end

  local note = session_module.get_note_at_line(session, file_path, line)
  if not note then
    vim.notify('Wander: No note at current line', vim.log.levels.WARN)
    return
  end

  float.open_note_editor(note.content, function(content)
    if content == '' then
      vim.notify('Wander: Empty note not saved', vim.log.levels.WARN)
      return
    end

    session_module.update_note(session, note.id, content)
    vim.notify('Wander: Note updated', vim.log.levels.INFO)
    display.update_for_session(bufnr, session)
  end)
end

--- Delete note at cursor
function commands.note_delete()
  local bufnr = vim.api.nvim_get_current_buf()
  local file_path = vim.api.nvim_buf_get_name(bufnr)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]

  local session
  if wander.state.current_session then
    session = session_module.load(wander.state.current_session)
  else
    session = session_module.load('default')
  end

  if not session then
    vim.notify('Wander: No session found', vim.log.levels.WARN)
    return
  end

  local note = session_module.get_note_at_line(session, file_path, line)
  if not note then
    vim.notify('Wander: No note at current line', vim.log.levels.WARN)
    return
  end

  session_module.remove_note(session, note.id)
  vim.notify('Wander: Note deleted', vim.log.levels.INFO)
  display.update_for_session(bufnr, session)
end

--- Start retrace mode
function commands.retrace(args)
  local session_name = args[2]

  if session_name then
    -- Try to find session by name
    local sessions = session_module.list()
    local session = nil
    for _, s in ipairs(sessions) do
      if s.name == session_name then
        session = s
        break
      end
    end

    if not session then
      vim.notify('Wander: Session "' .. session_name .. '" not found', vim.log.levels.ERROR)
      return
    end

    retrace.start(session)
  else
    -- Show session selector
    selector.select_session(function(session)
      retrace.start(session)
    end)
  end
end

--- List all sessions
function commands.sessions()
  local sessions = session_module.list()

  if #sessions == 0 then
    vim.notify('Wander: No sessions found', vim.log.levels.INFO)
    return
  end

  local lines = { 'Available sessions:' }
  for i, session in ipairs(sessions) do
    local current_marker = (wander.state.current_session == session.id) and '* ' or '  '
    local line = string.format(
      '%s%d. %s (%d notes, updated: %s, branch: %s)',
      current_marker,
      i,
      session.name,
      #session.notes,
      vim.fn.strftime('%Y-%m-%d %H:%M', vim.fn.strptime('%Y-%m-%dT%H:%M:%SZ', session.updated_at)),
      session.branch or 'N/A'
    )
    table.insert(lines, line)
  end

  vim.notify(table.concat(lines, '\n'), vim.log.levels.INFO)
end

--- Delete a session
function commands.session_delete(args)
  local session_name = args[3]

  if not session_name then
    vim.notify('Wander: Usage: :Wander session delete <name>', vim.log.levels.ERROR)
    return
  end

  -- Find session
  local sessions = session_module.list()
  local session = nil
  for _, s in ipairs(sessions) do
    if s.name == session_name then
      session = s
      break
    end
  end

  if not session then
    vim.notify('Wander: Session "' .. session_name .. '" not found', vim.log.levels.ERROR)
    return
  end

  -- Confirm deletion
  vim.ui.input({
    prompt = 'Delete session "' .. session_name .. '"? (y/N): ',
  }, function(input)
    if input == 'y' or input == 'Y' then
      if session_module.delete(session.id) then
        vim.notify('Wander: Session "' .. session_name .. '" deleted', vim.log.levels.INFO)

        -- Clear current session if it was deleted
        if wander.state.current_session == session.id then
          wander.state.current_session = nil
        end
      end
    else
      vim.notify('Wander: Deletion cancelled', vim.log.levels.INFO)
    end
  end)
end

--- Rename a session
function commands.session_rename(args)
  local old_name = args[3]
  local new_name = args[4]

  if not old_name or not new_name then
    vim.notify('Wander: Usage: :Wander session rename <old-name> <new-name>', vim.log.levels.ERROR)
    return
  end

  -- Find session
  local sessions = session_module.list()
  local session = nil
  for _, s in ipairs(sessions) do
    if s.name == old_name then
      session = s
      break
    end
  end

  if not session then
    vim.notify('Wander: Session "' .. old_name .. '" not found', vim.log.levels.ERROR)
    return
  end

  if session_module.rename(session.id, new_name) then
    vim.notify('Wander: Session renamed from "' .. old_name .. '" to "' .. new_name .. '"', vim.log.levels.INFO)
  end
end

-- Create user commands
vim.api.nvim_create_user_command('Wander', function(opts)
  local args = vim.split(vim.trim(opts.args), '%s+')
  local subcommand = args[1]

  if subcommand == 'start' then
    commands.start_session(args)
  elseif subcommand == 'end' then
    commands.end_session()
  elseif subcommand == 'note' or subcommand == 'memo' then
    commands.note(args)
  elseif subcommand == 'retrace' then
    if args[2] == 'end' then
      retrace.stop()
    else
      commands.retrace(args)
    end
  elseif subcommand == 'next' then
    retrace.next()
  elseif subcommand == 'prev' then
    retrace.prev()
  elseif subcommand == 'sessions' then
    commands.sessions()
  elseif subcommand == 'session' then
    local action = args[2]
    if action == 'delete' then
      commands.session_delete(args)
    elseif action == 'rename' then
      commands.session_rename(args)
    else
      vim.notify('Wander: Unknown session action: ' .. (action or 'nil'), vim.log.levels.ERROR)
    end
  else
    vim.notify('Wander: Unknown subcommand: ' .. (subcommand or 'nil'), vim.log.levels.ERROR)
  end
end, {
  nargs = '+',
  desc = 'Wander code reading session manager',
  complete = function(arg_lead, cmdline, _)
    local subcommands = {
      'start',
      'end',
      'note',
      'memo',
      'retrace',
      'next',
      'prev',
      'sessions',
      'session',
    }

    local args = vim.split(cmdline, '%s+')
    if #args == 2 then
      return vim.tbl_filter(function(cmd)
        return vim.startswith(cmd, arg_lead)
      end, subcommands)
    elseif #args == 3 and (args[2] == 'note' or args[2] == 'memo') then
      return vim.tbl_filter(function(cmd)
        return vim.startswith(cmd, arg_lead)
      end, { 'edit', 'delete' })
    end

    return {}
  end,
})
