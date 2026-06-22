---
status: open
---
# Plan: Multi-select copy in Telescope picker

## Problem

In `lua/cue/picker.lua`, the `<C-y>` (copy path) and `<C-h>` (copy hash) mappings only ever read a single entry via `action_state.get_selected_entry()`. When the user marks multiple entries with `<Tab>` (telescope's built-in `toggle_selection`), the multi-selection is silently ignored and only the highlighted row is copied.

## Verified API facts (telescope master)

From `lua/telescope/actions/state.lua`:
- `action_state.get_selected_entry()` — takes **no** args (this is what triggered the original diagnostic).
- `action_state.get_current_picker(prompt_bufnr)` — **does** take `prompt_bufnr`. Returns the `Picker`.

From `lua/telescope/pickers.lua`:
- `Picker:get_multi_selection()` — returns an integer-indexed table of the entries the user toggled with `<Tab>`. Empty when nothing is multi-selected.
- The canonical fallback pattern (used by `Picker:delete_selection` at `pickers.lua` around the `delete_selections = self._multi:get()` block) is: read `get_multi_selection()`; if empty, fall back to the single current selection.

## Design

Rewrite `copy_to_clipboard` (currently `picker.lua:212-225`) to honor multi-selection with single-select fallback:

1. Re-introduce `prompt_bufnr` as the first parameter (needed for `get_current_picker`). This is **not** the same call that caused the prior diagnostic — `get_current_picker` genuinely accepts a bufnr.
2. Get the picker via `action_state.get_current_picker(prompt_bufnr)`.
3. Read `multi = picker:get_multi_selection()`. If it's a non-empty array, use it; otherwise fall back to `{ get_selected_entry() }` (mirroring telescope's own `delete_selection` pattern).
4. Map each entry through `getter`, drop entries whose value is nil / "" / `vim.NIL`.
5. Join the remaining values with a single space → `vim.fn.setreg("+", joined)`.
6. Notify. Single-item message stays as today (`"Copied <label>: <value>"`); multi-item message becomes `"Copied <label> (<n> items)"` to avoid a giant notification.

### Call site changes (`picker.lua:270-279`)

Pass `prompt_bufnr` back into both invocations:

```lua
-- <C-y>
copy_to_clipboard(prompt_bufnr, function(e)
  return vim.fn.fnamemodify(e.path, ":p")
end, "path")

-- <C-h>
copy_to_clipboard(prompt_bufnr, function(e) return e.hash end, "hash")
```

The `prompt_bufnr` upvalue is already in scope from the `attach_mappings = function(prompt_bufnr, map)` closure at `picker.lua:260`.

### Out of scope

- `select_default` (`<CR>`) — opening multiple files is a larger UX decision; leaving as-is.
- `M.pick_context` (`picker.lua:287`) — user only mentioned the artifacts picker; leaving as-is.

## Open decisions (need your call)

1. **Whitespace in paths.** Your spec joins paths with a single space. Cue artifact paths are usually space-free, but if one ever contains a space, pasting into a shell breaks. Options:
   - (a) Strict spec: always space-join for both bindings. **[default]**
   - (b) Newline-join paths, space-join hashes (paste-safer, deviates from your example).

2. **Partial-hash-missing in multi-select.** If 2 of 3 selected entries lack a hash:
   - (a) Skip the empties, copy the rest, still notify with count. **[default]**
   - (b) Refuse entirely ("Nothing to copy").

3. **Multi-item notification text.**
   - (a) `"Copied path (3 items)"` — terse. **[default]**
   - (b) `"Copied paths: p0 p1 p2"` — full list, can overflow on long selections.

## Verification

No lua test harness exists in this repo and telescope isn't installed in this sandbox, so verification is manual:
- Open picker, mark N entries with `<Tab>`, hit `<C-y>` → clipboard should be space-joined paths, count shown.
- Mark N entries, hit `<C-h>` → space-joined hashes.
- Mark 0 entries, hit `<C-y>` on highlighted row → existing single-value behavior preserved.
- lua-language-server should report no new diagnostics on the file.
