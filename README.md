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

### `require('cue').pick_contexts(opts)`

Browse contexts in CLI recency order (newest log activity first, unlogged
last), with a file preview of `context.md` below the results in a vertical
50/50 layout, prompt at the top. Browsing does not activate.

```lua
require('cue').pick_contexts()                         -- C-a: repository
require('cue').pick_contexts({ pinned = true })        -- C-t: working set
require('cue').pick_contexts({ pinned = true, scope = "store" })
```

Options: `pinned` (boolean), `scope` (`repo` or `store`), `sort` (`recency`,
the default), `limit` (positive integer), `dir` (`cue -C`), and `store`
(`cue --store`). Aligned columns show active marker, mode, title, activity,
kind, and slug, in that order. Kind colors distinguish work (green), coord
(purple), and reference (blue). Modes are uppercase and colored: research
blue, design pink, build green, review orange, and learn cyan. Activity and
slug are muted. The title uses 70 columns, matching the legacy task picker.
Store-wide rows show `scope/slug` in the last
column. `*` marks the active context, not pin state.

Activity is relative time since `last_logged_at` (`now`, `12m`, `3h`, `6d`,
`1y`), sampled when loading or refreshing rows; `—` means no usable log
timestamp. It does not indicate urgency or context-file modification time.
Title, slug, scope, mode, and kind are searchable.

- `<CR>` opens the selected context file.
- `<C-e>` browses its artifacts; `<C-s>` activates it on the current branch.
- `<A-s>` pins in the full view, unpins in the pinned view, and refreshes
  without clearing the search. This is not a state-aware toggle: rows have
  no pin-state field or pin marker.
- Store-wide rows can always be opened or pinned/unpinned. Artifact browsing
  and activation require a row in the current repository scope; foreign
  rows (or an unknown current scope) notify without acting. Cue does not
  yet provide cross-scope targeting for those operations.

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
  `trace`. Within each group, unfinished artifacts precede complete/closed
  artifacts. Each section sorts newest `created_at` first, with missing or
  invalid dates last and alphabetical title ties. The ordering survives an
  empty query and score ties; searching still ranks by match quality.
- Rows show the artifact type and its title, falling back to the filename
  when the frontmatter has none. Type, title and filename are all searchable.
- Artifacts are listed whatever their status. Complete and closed rows have
  grey badges and titles, without strikethrough.
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
