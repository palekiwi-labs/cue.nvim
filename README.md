# cue.nvim

Neovim plugin for the `cue` artifact tracker. Provides Telescope pickers,
`:Cue*` commands, and a floating log form for working with cue artifacts
from within Neovim.

## Requirements

- Neovim (built with LuaJIT)
- The `cue` CLI, installed and on `$PATH`
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
- [snacks.nvim](https://github.com/folke/snacks.nvim)

## Installation (lazy.nvim)

```lua
{
  "palekiwi-labs/cue.nvim",
  dependencies = {
    "nvim-telescope/telescope.nvim",
    "folke/snacks.nvim",
  },
  config = function()
    require("cue").setup({})
  end,
}
```

## Commands

| Command | Description |
|---|---|
| `:CuePick [type]` | Open the artifact picker (optional type filter) |
| `:CueAdd` | Add a new artifact (prompts for type, filename, root) |
| `:CueAddBin <file>` | Add a `bin` artifact |
| `:CueAddTrace <file>` | Add a `trace` artifact |
| `:CueAddTmp <file>` | Add a `tmp` artifact |
| `:CueAddRef <file>` | Add a `ref` artifact |
| `:CueAddDoc <file>` | Add a `doc` artifact |
| `:CueLog [title]` | Add a log entry (no args opens the form) |
