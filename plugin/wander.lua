-- Wander.nvim - Code Reading Session Manager
-- Plugin initialization and command registration

if vim.g.loaded_wander then
  return
end
vim.g.loaded_wander = 1

-- Create user commands
-- Command implementations will be added in Task 8
vim.api.nvim_create_user_command('Wander', function(opts)
  local args = vim.split(vim.trim(opts.args), '%s+')
  local subcommand = args[1]

  if subcommand == 'start' then
    -- To be implemented in Task 8
    vim.notify('Wander: start command not yet implemented', vim.log.levels.WARN)
  elseif subcommand == 'end' then
    -- To be implemented in Task 8
    vim.notify('Wander: end command not yet implemented', vim.log.levels.WARN)
  elseif subcommand == 'note' or subcommand == 'memo' then
    -- To be implemented in Task 8
    vim.notify('Wander: note command not yet implemented', vim.log.levels.WARN)
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
    end

    return {}
  end,
})
