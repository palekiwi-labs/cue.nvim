# Project Log

## [44bad13-dirty] Commit: fix unused arg in telescope copy action

Resolved a lua-language-server diagnostic in lua/cue/picker.lua: action_state.get_selected_entry was being called with prompt_bufnr, which the telescope API does not accept. Followed up by removing the now-unused prompt_bufnr parameter from copy_to_clipboard and its two call sites (path copy on <C-y> and hash copy on <C-h>). Committed as 44bad13 on master.

- **Decided:** Removed prompt_bufnr from copy_to_clipboard signature and both call sites in picker.lua because action_state.get_selected_entry() takes no arguments; the closure variable in attach_mappings remains in scope and is still used for actions.close().

## [40a6857-dirty] Commits: multi-select copy, core.lua fix, luacheck config, nix flake

Committed four atomic changes related to telescope multi-select copy and dev tooling for cue.nvim:

- 6e1a412 feat: support multi-select in telescope copy action
  Rewrote copy_to_clipboard in lua/cue/picker.lua to read picker:get_multi_selection() (via action_state.get_current_picker(prompt_bufnr)) and join values with single space, falling back to single get_selected_entry() when nothing is toggled. Reintroduced prompt_bufnr as the first parameter (needed for get_current_picker; this is NOT the same call that caused the earlier diagnostic - get_selected_entry takes no args, get_current_picker does). Multi-item notifications are terse: "Copied path (3 items)". Entries whose getter returns nil/""/vim.NIL are silently skipped. Verified clean under luacheck.

- 8d2723a fix: scope err to init block in open_context
  lua/cue/core.lua:93 had `local output, err = ...` but err was never read in any path (if output was good err was unused; if output was bad err was reassigned at L102 before use at L104). Dropped err from the outer local and added `local err` inside the init block instead.

- 5fa6907 chore: add luacheck config
  Added .luacheckrc with std = "luajit" and globals = {"vim"}. Without this, `luacheck lua/` drowned in 150 false "undefined vim" warnings. With it: 0 warnings, 0 errors across all 8 source files.

- 40a6857 feat: add nix flake devshell
  flake.nix provides luajit, lua-language-server, stylua, and luajitPackages.luacheck (NOT pkgs.luacheck - that attribute does not exist; luacheck is only in the luarocks-generated Lua package scopes, verified via generated-packages.nix:2831). Pinned to luajitPackages rather than lua51Packages so the devshell ships exactly one Lua interpreter. flake.lock committed alongside.

Side effect: 6e1a412 also deleted an empty flake.lock that had been committed in af623d1 (user). The real populated flake.lock was re-added in 40a6857.

Verification: luacheck lua/ plugin/ reports 0 warnings / 0 errors. nix could not be run in sandbox (permission denied) - user generated flake.lock locally.

- **Decided:** Use luajitPackages.luacheck (not lua51Packages.luacheck) for single-interpreter devshell cleanliness - both paths work functionally.
- **Decided:** Use space as the join separator for multi-select copy output per user spec; cue paths should never contain whitespace.
- **Decided:** Terse multi-item notification: 'Copied <label> (<n> items)' rather than full value list to avoid overflow.
- **Decided:** Entries with missing values (nil/""/vim.NIL) are silently skipped rather than aborting the whole multi-select copy.
- **Decided:** Std 'luajit' chosen for .luacheckrc over 'lua51' to match Neovim's actual runtime.
- **Decided:** Excluded .agents/ and opencode.json from all commits - user is actively editing opencode.json; .agents/ is out of scope.

## [ec7c0ec-dirty] Commit: add basic README

Committed ec7c0ec on master. README covers requirements (neovim+LuaJIT, cue CLI, telescope, snacks), the lazy.nvim install spec (verbatim from user), and a table of the 8 :Cue* user commands sourced from lua/cue/commands.lua:66-171. Deliberately kept minimal per user request - no picker keybindings, no programmatic API docs, no setup() options (config.lua:31 has empty defaults so nothing to document). .agents/ left untracked as previously agreed.

