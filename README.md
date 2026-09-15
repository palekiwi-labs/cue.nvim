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
(`cue --store`). Aligned columns show the pin marker, title, mode, activity,
kind, and slug, in that order. Kind colors distinguish work (green), coord
(purple), and reference (blue). Modes are uppercase and colored: research
blue, design pink, build green, review orange, and learn cyan. Activity and
slug are muted. The title uses 45 columns. Store-wide rows show `scope/slug`
in the last column.

The marker column is one cell wide and means pinned: the Nerd Font thumb
tack (U+F08D, `nf-fa-thumb_tack`), read from the `pinned` field that `cue
context list --json` puts on every row. It is orange when the row is only
pinned and cyan when the row is also the active context — active contexts
are pinned (see `<C-s>` below), so the active row normally carries a tack.

The active context is marked by color, not by a glyph: its title renders in
cyan. That is unrelated to Telescope's own selection highlight, which
follows the cursor; the cyan title follows the branch, so it stays visible
while browsing other rows.

The active context is matched on the `scope`/`context` pair, not the slug:
under `--scope store` two scopes may hold a context of the same name.

Activity is relative time since `last_logged_at` (`now`, `12m`, `3h`, `6d`,
`1y`), sampled when loading or refreshing rows; `—` means no usable log
timestamp. It does not indicate urgency or context-file modification time.
Title, slug, scope, mode, and kind are searchable.

- `<CR>` opens the selected context file.
- `<C-e>` browses its artifacts.
- `<C-s>` activates the context on the current branch, pinning it first. The
  order matters: activating puts the branch on the context, so the context
  belongs in the working set, and a pin that fails after the switch would
  leave the branch on a context the pinned view cannot show. A failed pin
  therefore aborts the activation and changes nothing. `cue context pin` is
  idempotent, so activating an already-pinned context is a no-op plus the
  switch.
- `<A-s>` pins in the full view, unpins in the pinned view, and refreshes
  without clearing the search. It is view-scoped, not a state-aware toggle:
  the `pinned` field drives the marker and the guard below, never the choice
  of operation.
- The active context cannot be unpinned. `<A-s>` on it notifies and does
  nothing; switch away first. Same-named contexts in other scopes are
  unaffected, because the guard matches on scope identity.
- `<C-h>` copies the selected context's canonical address — `scope/slug`,
  e.g. `palekiwi/palekiwi/cue-nvim-migration` — to the system clipboard
  (register `+`). That is the form cue accepts for `parent:` frontmatter,
  `context pin`/`unpin` and the command line, so it is what to paste when
  parenting a context or handing one to an agent; the bare slug is only
  unique within a scope and the row's absolute path is meaningless to
  anyone whose store lives elsewhere. It is the same address the pin and
  activate actions target the row with.
- Like the artifact picker's yanks, `<C-h>` works in insert and normal
  mode, leaves the picker open, notifies with the copied value, and writes
  register `+` only, so the unnamed register keeps whatever was last yanked
  in the buffer. It runs no CLI call: scope travels on the row, unlike the
  artifact picker's address, which has to query `cue status` for it.
- Without a selection, or on a row carrying no scope, nothing is copied and
  a warning says why: a partial address pastes cleanly and resolves to
  nothing.
- Store-wide rows can always be opened, addressed or pinned/unpinned.
  Artifact browsing and activation require a row in the current repository
  scope; foreign rows (or an unknown current scope) notify without acting.
  Cue does not yet provide cross-scope targeting for those operations.

### `require('cue').pick_context_artifacts(context, opts)`

Browse one context's artifacts as a single searchable Telescope list. The
window takes 95% of the editor width, with the preview below the results in
a 50/50 vertical split and the prompt at the top.

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
  `trace`, `bin`, `tmp`. Within each group, unfinished artifacts precede
  complete/closed artifacts. Each section sorts newest creation time first,
  with undated rows last and alphabetical title ties. The ordering survives
  an empty query and score ties; searching still ranks by match quality.
- Aligned columns show the artifact type, a priority caret, the title and
  the creation age, in that order. Type, title and filename are all
  searchable.
- The title falls back to the filename when the frontmatter has none, and
  uses 72 columns. Every column is a fixed width, so the age sits beside the
  title rather than at the far edge of the near-fullscreen window.
- The priority caret flags `critical` (U+F102 angle-double-up, red) and
  `high` (U+F106 angle-up, orange) only. `normal` is the norm and `low` is
  rare clutter, so both render blank and the column reads as a flag.
- Creation age is the relative time since the artifact was created (`now`,
  `12m`, `3h`, `6d`, `1y`), muted, right-justified in four cells that
  follow the title column. It is the same format, and the same
  formatter, as the context browser's activity column, and is sampled when
  the picker loads rather than per row. `—` means the artifact carries no
  timestamp.
- Artifacts are listed whatever their status. Complete and closed rows are
  grey in every column, without strikethrough.
- `bin` and `tmp` artifacts are listed, appended after the markdown groups.
  Neither carries frontmatter (`cue add` refuses metadata for both), so they
  have no title, status or priority: rows show the filename and a blank
  caret.
- The `tmp` creation stamp, which drives both the age column and the
  ordering, comes from the group directory cue writes them into,
  `<nanosecond timestamp>-<short commit hash>` (e.g.
  `1789366283853051953-d8dc048d49/review-comments-delta.json`). The parser
  is strict — exactly 19 digits, no leading zero, hex hash — so an ordinary
  directory name is never mistaken for a stamp. Pre-grouping flat `tmp`
  files and all `bin` artifacts show `—`; the filesystem mtime is
  deliberately not used as a fallback, because it records the last write
  rather than the creation.
- The preview shows the selected file's contents.
- `<CR>` opens the selected file. It does not change the active context, and
  the picker offers no creation actions.
- `<C-y>` copies the selected artifact's absolute file path to the system
  clipboard (register `+`).
- `<C-h>` copies its canonical address — `scope/context/type/name`, e.g.
  `palekiwi/palekiwi/cue-nvim-migration/spec/index.md` — to the system
  clipboard. That is the form cue accepts in `parent:` and `refs:`
  frontmatter and on the command line, so it is what to paste when linking
  artifacts or handing one to an agent; the absolute store path (`<C-y>`) is
  meaningless to anyone whose store lives elsewhere. A grouped `tmp`
  artifact keeps its group directory in the address.
- Both yanks work in insert and normal mode, leave the picker open, and
  notify with the copied value. Only register `+` is written, so the unnamed
  register keeps whatever was last yanked in the buffer.
- The scope behind the canonical address comes from `cue status --json`,
  queried with the same `opts.dir` and `opts.store` as the artifact list, so
  browsing another repository addresses its artifacts in *its* scope. It is
  read on the first `<C-h>` and then reused for the life of the picker.
  Scope is a property of the repository, not of the branch's context
  association, so this does not depend on (or consult) the active context.
  When the scope cannot be resolved, or the row carries no type/name,
  nothing is copied and the failure is reported: a plausible-looking wrong
  address pastes cleanly and resolves to nothing.

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
