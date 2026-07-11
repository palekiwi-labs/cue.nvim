# cue.nvim

Neovim plugin for the `cue` artifact tracker. Telescope pickers and `:Cue*`
commands for working with cue artifacts.

## Requirements

- Neovim 0.10+ (LuaJIT; targets 0.12)
- `cue` CLI on `$PATH`
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
- [snacks.nvim](https://github.com/folke/snacks.nvim)

## Install (lazy.nvim)

```lua
{
  "palekiwi-labs/cue.nvim",
  dependencies = {
    "nvim-telescope/telescope.nvim",
    "folke/snacks.nvim",
  },
  config = function() require("cue").setup({}) end,
}
```

## Commands

| Command | Description |
|---|---|
| `:CuePick [type] [key=value ...]` | Open artifact picker (`all`, `branch=X`, optional `type` filter) |
| `:CueAdd [type] [file] [key=value ...]` | Add artifact (no args = wizard; `root`, `force`, `branch=X`, etc.) |
| `:CueLog [branch]` | Open branch log file (default: current branch) |
| `:CueContext` | Open current context file |

All commands are thin wrappers over `require('cue').*` functions; bind those
directly for keybinding-driven workflows.
