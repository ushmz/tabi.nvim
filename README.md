# wander.nvim

A Neovim plugin for managing code reading sessions with notes and replay functionality.

## Features

- **Session Management**: Organize your code reading sessions with named sessions
- **Markdown Notes**: Take notes while reading code with a floating window editor
- **Visual Indicators**: See your notes inline with virtual text and signs
- **Session Replay**: Retrace your steps through code with the retrace mode
- **Persistent Storage**: Notes are saved locally (`.git/wander/`) or globally
- **Branch Awareness**: Sessions are automatically associated with git branches

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  'ushmz/wander.nvim',
  config = function()
    require('wander').setup()
  end,
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  'ushmz/wander.nvim',
  config = function()
    require('wander').setup()
  end,
}
```

## Configuration

```lua
require('wander').setup({
  storage = {
    backend = 'local', -- 'local' (.git/wander/) or 'global' (XDG_DATA_HOME/wander/)
  },
  ui = {
    selector = 'native', -- 'native', 'telescope', or 'float'
    note_preview_length = 30, -- Characters to show in virtual text
    use_icons = true, -- Show icons in sign column
    float_config = {
      width = 60,
      height = 10,
      border = 'rounded',
    },
  },
})
```

## Usage

### Basic Workflow

1. **Start a session**
   ```vim
   :Wander start my-reading-session
   ```

2. **Take notes while reading code**
   - Navigate to a line you want to annotate
   - Run `:Wander note` to open the note editor
   - Write your notes in Markdown
   - Save with `<C-s>` or `:w`

3. **View your notes**
   - Notes appear as virtual text at the end of each line
   - Icons/signs appear in the sign column
   - Line numbers are highlighted

4. **End your session**
   ```vim
   :Wander end
   ```

5. **Replay your session later**
   ```vim
   :Wander retrace my-reading-session
   ```
   - Navigate through notes with `:Wander next` and `:Wander prev`
   - Exit retrace mode with `:Wander retrace end`

### Commands

#### Session Management

| Command | Description |
|---------|-------------|
| `:Wander start [name]` | Start a new session (optional name) |
| `:Wander end` | End the current session |
| `:Wander sessions` | List all sessions |
| `:Wander session delete <name>` | Delete a session |
| `:Wander session rename <old> <new>` | Rename a session |

#### Note Management

| Command | Description |
|---------|-------------|
| `:Wander note` | Create/edit note at current line |
| `:Wander note edit` | Edit existing note at current line |
| `:Wander note delete` | Delete note at current line |

#### Retrace Mode

| Command | Description |
|---------|-------------|
| `:Wander retrace [name]` | Start replaying a session |
| `:Wander next` | Go to next note in replay |
| `:Wander prev` | Go to previous note in replay |
| `:Wander retrace end` | Exit retrace mode |

### Anonymous Sessions

If you don't start a named session, notes are automatically saved to a `default` session. This is useful for quick, temporary notes.

## Storage

### Local Storage (Default)

Notes are stored in `.git/wander/sessions/` within your project. This keeps notes project-specific and allows sharing with your team by committing the `.git/wander` directory.

```
.git/wander/
└── sessions/
    ├── default.json
    └── my-reading-session.json
```

### Global Storage

Set `storage.backend = 'global'` to store all notes in:
- `${XDG_DATA_HOME}/wander/sessions/` (usually `~/.local/share/wander/sessions/`)

This is useful for personal notes across multiple projects.

## Tips

- **Keyboard Shortcuts in Note Editor**:
  - `<C-s>` - Save and close
  - `<Esc>` or `q` - Cancel
  - `:w` - Save and close

- **Integrations**:
  - Works with [dressing.nvim](https://github.com/stevearc/dressing.nvim) for better UI
  - Session selector integrates with [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) if configured

## Development

```bash
# Clone the repository
git clone https://github.com/ushmz/wander.nvim.git
cd wander.nvim

# Run tests (if available)
# TBD
```

## License

MIT

## Credits

Created by [@ushmz](https://github.com/ushmz)

Built with the assistance of Claude Code.
