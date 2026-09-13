-- Standalone tests for core.active_context_path
-- Run: luajit tests/test_active_context_path.lua
--
-- Repairs `core.open_context` (<space>mc / A-a), which was broken by the
-- removal of `cue context path` and `cue context init` from the CLI.
--
-- The replacement is derivation, not a query. `cue status --json` emits
-- `store` and `address` but no path:
--
--   {"address":"palekiwi/palekiwi/cue-nvim-migration", ..., "store":"/home/pl/cue"}
--
-- and the cue addressing rule is that an absolute path IS the store root
-- joined to the canonical address:
--
--   <absolute path> = $CUE_STORE .. "/" .. <canonical address>
--
-- So the active context's descriptor is store + address + "/context.md".
-- This keeps the plugin free of store-layout knowledge beyond the one
-- filename, and needs no second CLI call: get_active_context already
-- returns the full decoded status table alongside the slug.
--
-- Mocks the minimal `vim` global so the real module can be required without
-- a running Neovim instance.

package.path = package.path .. ";./lua/?.lua"

vim = {} -- luacheck: ignore (global stub)
vim.NIL = {}

local core = require("cue.core")

local failures = 0

local function check(name, fn)
	local ok, err = pcall(fn)
	if ok then
		print(string.format("ok:   %s", name))
	else
		failures = failures + 1
		print(string.format("FAIL: %s -- %s", name, err))
	end
end

local function status(store, address)
	return {
		address = address,
		store = store,
		context = "cue-nvim-migration",
		scope = "palekiwi/palekiwi",
		kind = "work",
		mode = "design",
	}
end

local WANT = "/home/pl/cue/palekiwi/palekiwi/cue-nvim-migration/context.md"

-- ─── the derivation ──────────────────────────────────────────────────────────

check("joins store, address and context.md", function()
	local got = core.active_context_path(status("/home/pl/cue", "palekiwi/palekiwi/cue-nvim-migration"))
	assert(got == WANT, string.format("got %q, expected %q", tostring(got), WANT))
end)

check("does not double the separator on a trailing slash", function()
	local got = core.active_context_path(status("/home/pl/cue/", "palekiwi/palekiwi/cue-nvim-migration"))
	assert(got == WANT, string.format("got %q, expected %q", tostring(got), WANT))
end)

check("collapses repeated trailing slashes", function()
	local got = core.active_context_path(status("/home/pl/cue///", "palekiwi/palekiwi/cue-nvim-migration"))
	assert(got == WANT, string.format("got %q, expected %q", tostring(got), WANT))
end)

check("trims surrounding whitespace on both fields", function()
	local got = core.active_context_path(status("  /home/pl/cue  ", "  palekiwi/palekiwi/cue-nvim-migration  "))
	assert(got == WANT, string.format("got %q, expected %q", tostring(got), WANT))
end)

-- ─── refusals ────────────────────────────────────────────────────────────────
--
-- Every refusal returns nil rather than a partial path. A path built from a
-- missing store would be relative and a path built from a missing address
-- would point at the store root, and both would be opened as a new empty
-- buffer rather than reported as an error.

check("nil for a nil or non-table status", function()
	assert(core.active_context_path(nil) == nil)
	assert(core.active_context_path(vim.NIL) == nil)
	assert(core.active_context_path("not a table") == nil)
	assert(core.active_context_path(42) == nil)
end)

check("nil when store is absent, blank or not a string", function()
	assert(core.active_context_path(status(nil, "palekiwi/palekiwi/cue-nvim-migration")) == nil)
	assert(core.active_context_path(status("", "palekiwi/palekiwi/cue-nvim-migration")) == nil)
	assert(core.active_context_path(status("   ", "palekiwi/palekiwi/cue-nvim-migration")) == nil)
	assert(core.active_context_path(status(vim.NIL, "palekiwi/palekiwi/cue-nvim-migration")) == nil)
	assert(core.active_context_path(status(42, "palekiwi/palekiwi/cue-nvim-migration")) == nil)
end)

check("nil when address is absent, blank or not a string", function()
	assert(core.active_context_path(status("/home/pl/cue", nil)) == nil)
	assert(core.active_context_path(status("/home/pl/cue", "")) == nil)
	assert(core.active_context_path(status("/home/pl/cue", "   ")) == nil)
	assert(core.active_context_path(status("/home/pl/cue", vim.NIL)) == nil)
	assert(core.active_context_path(status("/home/pl/cue", 42)) == nil)
end)

-- ─── the legacy surface is gone ──────────────────────────────────────────────

check("no helper shells out to the removed subcommands", function()
	assert(core.context_path_argv == nil, "cue context path is not a subcommand any more")
	assert(core.context_init_argv == nil, "cue context init is not a subcommand any more")
end)

os.exit(failures == 0 and 0 or 1)
