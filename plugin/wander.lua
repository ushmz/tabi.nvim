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

-- Initialize display
display.init()

-- Command implementations
local commands = {}

--- Start a new session
function commands.start(args)
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
function commands['end']()
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

-- Create user commands
vim.api.nvim_create_user_command('Wander', function(opts)
  local args = vim.split(vim.trim(opts.args), '%s+')
  local subcommand = args[1]

  if subcommand == 'start' then
    commands.start(args)
  elseif subcommand == 'end' then
    commands['end']()
  elseif subcommand == 'note' or subcommand == 'memo' then
    commands.note(args)
  elseif subcommand == 'retrace' then
    -- To be implemented in Task 9
    vim.notify('Wander: retrace command not yet implemented', vim.log.levels.WARN)
  elseif subcommand == 'next' then
    -- To be implemented in Task 9
    vim.notify('Wander: next command not yet implemented', vim.log.levels.WARN)
  elseif subcommand == 'prev' then
    -- To be implemented in Task 9
    vim.notify('Wander: prev command not yet implemented', vim.log.levels.WARN)
  elseif subcommand == 'sessions' then
    -- To be implemented in Task 11
    vim.notify('Wander: sessions command not yet implemented', vim.log.levels.WARN)
  elseif subcommand == 'session' then
    -- To be implemented in Task 11
    vim.notify('Wander: session command not yet implemented', vim.log.levels.WARN)
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
