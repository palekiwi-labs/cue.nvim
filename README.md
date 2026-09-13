# cue.nvim

Neovim plugin for the `cue` artifact tracker. Telescope pickers and creation
flows for working with cue artifacts.

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

## Lua API

The plugin registers no `:Cue*` user commands. Every entry point is a
function on the `cue` module; bind the ones you use to keys.

### `require('cue').pick_context_artifacts(context, opts)`

Browse one context's artifacts as a single searchable Telescope list.

```lua
require('cue').pick_context_artifacts("cue-nvim-workflow")

-- Another repository's scope, or another store root:
require('cue').pick_context_artifacts("cue-nvim-workflow", {
  dir   = "/home/me/code/other-repo",  -- cue -C
  store = "/home/me/cue",              -- cue --store
})
```

- `context` (string, required) — the context slug. It is always explicit:
  the picker never falls back to the active context, and browsing never
  activates one. A missing or blank slug notifies and opens nothing.
- `opts.dir` (string, optional) — run `cue` as if started in this directory
  (`cue -C`), which selects the repository scope.
- `opts.store` (string, optional) — cue store root (`cue --store`),
  overriding `$CUE_STORE`.

Behaviour:

- One list, grouped by type in the order `task`, `spec`, `plan`, `note`,
  `trace`; alphabetical by displayed title within each group. The grouping
  survives an empty query and score ties.
- Rows show the artifact type and its title, falling back to the filename
  when the frontmatter has none. Type, title and filename are all searchable.
- Tasks are listed whatever their status.
- `bin` and `tmp` artifacts are not listed yet (deferred).
- The preview shows the selected file's contents.
- `<CR>` opens the selected file. It does not change the active context, and
  the picker offers no creation actions.

### `require('cue').pick_active_context_artifacts(opts)`

Browse the currently active context's artifacts. Primary `<C-s>` binding.

Resolves the active context via `cue status --json` (with optional `opts.dir` and
`opts.store`). If a context is active, delegates to `pick_context_artifacts`.
If no context is active (or on error), notifies the user without opening a
picker.

`require('cue').pick_active_task_artifacts(opts)` is preserved as a legacy alias.

## Development

```sh
nix develop                          # devshell: luajit, luacheck, stylua
for f in tests/*.lua; do luajit "$f"; done
luacheck lua tests
stylua --check <files you touched>   # tests/ only; lua/ is hand-formatted
```

`tests/*.lua` are standalone LuaJIT scripts that stub `vim`. Tests under
`tests/nvim/` need a real Neovim (they cover behaviour a stub cannot, such as
Ex-command argument expansion) and are run one file at a time:

```sh
nvim --clean --headless -l tests/nvim/test_open_path.lua
```
