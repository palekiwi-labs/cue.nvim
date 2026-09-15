-- Standalone tests for the pure helpers behind the context browser
-- Run: luajit tests/test_context_list.lua
--
-- Covers spec section 4 (palekiwi/palekiwi/cue-nvim-workflow/spec/index.md):
--
--   core.list_contexts_argv(opts)
--     Gains `--json` so the browser can read structured rows, while the
--     plain-slug callers (confirm_scope) keep their existing argv.
--
--   core.context_display_title(ctx)
--     The row label: `title` when it is a nonempty string, else the slug.
--     Mirrors artifact_display_title's filename fallback.
--
--   core.context_list_view(contexts)
--     Turn decoded `cue context list --json` rows into picker rows by
--     dropping malformed entries. Ordering is NOT done here: `cue context
--     list --sort recency` owns it, and its documented rule ("newest log
--     entry first; contexts with no log entry last") is precisely what this
--     module used to reimplement. The CLI also now emits `last_logged_at`
--     on every row, so the old slug -> timestamp parameter has no source
--     left to come from.
--
--   core.context_is_active(status, ctx)
--     Identity comparison against `cue status --json`, on the
--     (scope, context) PAIR. A bare slug does not identify a context once
--     the store holds more than one scope.
--
--   core.context_pin_marker(ctx)
--     The browser's leading width-1 column: the pin marker alone. Active
--     is signalled by the title colour, not by a second glyph, so the
--     column takes no status argument. `pinned` is a field on every
--     `cue context list --json` row, so the marker is read, never joined
--     client-side.
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

local function assert_argv(actual, expected)
	assert(type(actual) == "table", "expected an argv table, got " .. type(actual))
	assert(
		#actual == #expected,
		string.format("argv length %d ~= %d: %s", #actual, #expected, table.concat(actual, " "))
	)
	for i, want in ipairs(expected) do
		assert(
			actual[i] == want,
			string.format("argv[%d] = %q, expected %q (%s)", i, tostring(actual[i]), want, table.concat(actual, " "))
		)
	end
end

local function ctx(slug, title)
	return {
		context = slug,
		scope = "palekiwi/palekiwi",
		title = title,
		kind = "work",
		mode = "design",
		created_at = 1789000000,
		path = "/home/pl/cue/palekiwi/palekiwi/" .. tostring(slug) .. "/context.md",
	}
end

local function slugs(rows)
	local out = {}
	for i, row in ipairs(rows) do
		out[i] = row.context
	end
	return out
end

local function assert_order(rows, expected)
	local actual = slugs(rows)
	assert(
		#actual == #expected,
		string.format("row count %d ~= %d: %s", #actual, #expected, table.concat(actual, ", "))
	)
	for i, want in ipairs(expected) do
		assert(
			actual[i] == want,
			string.format("row[%d] = %q, expected %q (%s)", i, tostring(actual[i]), want, table.concat(actual, ", "))
		)
	end
end

-- ─── list_contexts_argv ──────────────────────────────────────────────────────

check("omits --json unless asked", function()
	assert_argv(core.list_contexts_argv(), { "cue", "context", "list" })
end)

check("appends --json when opts.json is set", function()
	assert_argv(core.list_contexts_argv({ json = true }), { "cue", "context", "list", "--json" })
end)

check("emits --json before -C and --store", function()
	assert_argv(
		core.list_contexts_argv({ json = true, dir = "/my/repo", store = "/my/store" }),
		{ "cue", "context", "list", "--json", "-C", "/my/repo", "--store", "/my/store" }
	)
end)

check("appends --sort recency", function()
	assert_argv(core.list_contexts_argv({ sort = "recency" }), { "cue", "context", "list", "--sort", "recency" })
end)

check("refuses a sort the CLI does not define", function()
	-- `--sort` has exactly one possible value; passing anything else would
	-- make cue exit non-zero and the picker come up empty.
	assert_argv(core.list_contexts_argv({ sort = "title" }), { "cue", "context", "list" })
	assert_argv(core.list_contexts_argv({ sort = true }), { "cue", "context", "list" })
end)

check("appends --scope for either breadth", function()
	assert_argv(core.list_contexts_argv({ scope = "repo" }), { "cue", "context", "list", "--scope", "repo" })
	assert_argv(core.list_contexts_argv({ scope = "store" }), { "cue", "context", "list", "--scope", "store" })
end)

check("refuses a scope the CLI does not define", function()
	assert_argv(core.list_contexts_argv({ scope = "global" }), { "cue", "context", "list" })
end)

check("appends --limit for a positive integer", function()
	assert_argv(core.list_contexts_argv({ limit = 5 }), { "cue", "context", "list", "--limit", "5" })
end)

check("refuses a limit that is not a positive integer", function()
	assert_argv(core.list_contexts_argv({ limit = 0 }), { "cue", "context", "list" })
	assert_argv(core.list_contexts_argv({ limit = -1 }), { "cue", "context", "list" })
	assert_argv(core.list_contexts_argv({ limit = 2.5 }), { "cue", "context", "list" })
	assert_argv(core.list_contexts_argv({ limit = "5" }), { "cue", "context", "list" })
end)

check("orders every flag ahead of -C and --store", function()
	-- Flag and value stay on one line: the expected argv reads as the
	-- command line it asserts, which a value-per-line expansion loses.
	-- stylua: ignore
	assert_argv(
		core.list_contexts_argv({
			json = true,
			scope = "store",
			sort = "recency",
			limit = 5,
			dir = "/my/repo",
			store = "/my/store",
		}),
		{
			"cue", "context", "list",
			"--json",
			"--scope", "store",
			"--sort", "recency",
			"--limit", "5",
			"-C", "/my/repo",
			"--store", "/my/store",
		}
	)
end)

check("keeps the plain-slug argv untouched for confirm_scope", function()
	-- list_contexts (and through it confirm_scope) parses bare slug lines.
	assert_argv(core.list_contexts_argv(), { "cue", "context", "list" })
end)

-- ─── context_display_title ───────────────────────────────────────────────────

check("displays the title when it is a nonempty string", function()
	assert(core.context_display_title(ctx("auth", "Auth redesign")) == "Auth redesign")
end)

check("falls back to the slug when the title is missing", function()
	assert(core.context_display_title(ctx("auth", nil)) == "auth")
	assert(core.context_display_title(ctx("auth", vim.NIL)) == "auth")
end)

check("falls back to the slug when the title is blank or non-string", function()
	assert(core.context_display_title(ctx("auth", "   ")) == "auth")
	assert(core.context_display_title(ctx("auth", 42)) == "auth")
end)

check("returns an empty string for a missing context", function()
	assert(core.context_display_title(nil) == "")
	assert(core.context_display_title("not a table") == "")
end)

-- ─── context_list_view ───────────────────────────────────────────────────────

check("returns an empty list for non-table input", function()
	assert_order(core.context_list_view(nil), {})
	assert_order(core.context_list_view("nope"), {})
end)

check("returns an empty list for an empty payload", function()
	assert_order(core.context_list_view({}), {})
end)

check("drops rows without a slug or a path", function()
	local rows = core.context_list_view({
		ctx("keeper", "Keeper"),
		{ context = "no-path", title = "No path" },
		{ path = "/somewhere/context.md", title = "No slug" },
		"not a table",
	})
	assert_order(rows, { "keeper" })
end)

check("preserves CLI order verbatim", function()
	-- cue owns the recency axis, so it owns the sort. Re-deriving an order
	-- here would mean keeping a second implementation of `--sort recency`
	-- in step with the first.
	local rows = core.context_list_view({
		ctx("zeta", "Zeta"),
		ctx("alpha", "Alpha"),
		ctx("middle", "Middle"),
	})
	assert_order(rows, { "zeta", "alpha", "middle" })
end)

check("does not reorder on created_at or title", function()
	local older = ctx("older", "zzz")
	older.created_at = 1
	local newer = ctx("newer", "aaa")
	newer.created_at = 1789999999
	assert_order(core.context_list_view({ older, newer }), { "older", "newer" })
end)

check("keeps unlogged contexts where the CLI put them", function()
	-- `--sort recency` already places contexts with no log entry last.
	local logged = ctx("logged", "Logged")
	logged.last_logged_at = 1789000000
	local unlogged = ctx("unlogged", "Unlogged")
	assert_order(core.context_list_view({ logged, unlogged }), { "logged", "unlogged" })
end)

check("carries the fields the picker renders", function()
	local row = ctx("auth", "Auth redesign")
	row.last_logged_at = 1789123456
	row.pinned = true
	local rows = core.context_list_view({ row })
	local got = rows[1]
	assert(got.context == "auth", "slug not carried")
	assert(got.title == "Auth redesign", "title not carried")
	assert(got.scope == "palekiwi/palekiwi", "scope not carried")
	assert(got.path == "/home/pl/cue/palekiwi/palekiwi/auth/context.md", "path not carried")
	assert(got.last_logged_at == 1789123456, "last_logged_at not carried")
	assert(got.pinned == true, "pinned not carried")
end)

check("no longer exposes a client-side comparator", function()
	assert(core.context_less == nil, "cue context list --sort owns the ordering")
end)

-- ─── context_is_active ───────────────────────────────────────────────────────
--
-- Identity is the (scope, context) pair, never the slug alone. Two scopes
-- may hold a context of the same name, and the store-wide listing shows both
-- rows at once; matching on the slug would mark the wrong one active and,
-- worse, let the unpin guard refuse the wrong row.

check("matches the active context on the scope/context pair", function()
	assert(core.context_is_active({ scope = "palekiwi/palekiwi", context = "auth" }, ctx("auth", "Auth")))
end)

check("does not match the same slug in another scope", function()
	assert(not core.context_is_active({ scope = "other/repo", context = "auth" }, ctx("auth", "Auth")))
end)

check("does not match another slug in the same scope", function()
	assert(not core.context_is_active({ scope = "palekiwi/palekiwi", context = "billing" }, ctx("auth", "Auth")))
end)

check("reports no active context for an unusable status", function()
	local row = ctx("auth", "Auth")
	assert(not core.context_is_active(nil, row))
	assert(not core.context_is_active("not a table", row))
	assert(not core.context_is_active({}, row))
	assert(not core.context_is_active({ scope = "", context = "auth" }, row))
	assert(not core.context_is_active({ scope = "palekiwi/palekiwi" }, row))
	assert(not core.context_is_active({ scope = "palekiwi/palekiwi", context = vim.NIL }, row))
end)

check("reports no active context for a scopeless row", function()
	local row = ctx("auth", "Auth")
	row.scope = nil
	assert(not core.context_is_active({ scope = "palekiwi/palekiwi", context = "auth" }, row))
	assert(not core.context_is_active({ scope = "palekiwi/palekiwi", context = "auth" }, nil))
end)

-- ─── context_pin_marker ──────────────────────────────────────────────────────

local TACK = "\239\130\141" -- U+F08D nf-fa-thumb_tack (EF 82 8D)

check("uses the Nerd Font thumb tack, not an emoji", function()
	local row = ctx("auth", "Auth")
	row.pinned = true
	local cell = core.context_pin_marker(row)
	assert(cell == TACK, "expected U+F08D, got " .. cell)
	assert(#TACK == 3, "a Nerd Font private-use glyph is 3 UTF-8 bytes; an emoji would be 4")
end)

check("the marker is exactly one cell and says nothing about activation", function()
	-- The retired `*` is gone: an active context is signalled by the title
	-- colour, which frees the glyph column to mean pinned and nothing else.
	local row = ctx("auth", "Auth")
	row.pinned = true
	assert(core.context_pin_marker(row) == TACK, "a pinned row shows the tack")
	row.pinned = false
	assert(core.context_pin_marker(row) == " ", "an unpinned row shows one blank cell")
end)

check("renders a blank when the row is not pinned", function()
	local row = ctx("auth", "Auth")
	assert(core.context_pin_marker(row) == " ", "missing pinned field")
	row.pinned = false
	assert(core.context_pin_marker(row) == " ")
	row.pinned = vim.NIL
	assert(core.context_pin_marker(row) == " ", "a JSON null is not a pin")
	row.pinned = "true"
	assert(core.context_pin_marker(row) == " ", "only boolean true is a pin")
	assert(core.context_pin_marker(nil) == " ")
end)

if failures == 0 then
	print("\nAll tests passed.")
else
	print(string.format("\n%d test(s) FAILED.", failures))
	os.exit(1)
end
