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
--   core.context_list_view(contexts, recency)
--     Turn decoded `cue context list --json` rows into picker rows, ordered
--     by recency (newest first). Recency is supplied by the caller as a
--     slug -> timestamp map: `cue context list --json` does not carry it,
--     and the spec defines it as the latest context log entry, never
--     created_at. Contexts with no log sort last, alphabetically.
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

check("orders by recency, newest first", function()
	local rows = core.context_list_view({
		ctx("older", "Older"),
		ctx("newest", "Newest"),
		ctx("middle", "Middle"),
	}, { older = 1789000000, newest = 1789200000, middle = 1789100000 })
	assert_order(rows, { "newest", "middle", "older" })
end)

check("ignores created_at when ordering", function()
	-- `stale` was created most recently but has the oldest log entry: the
	-- spec defines recency exclusively as the latest context log entry.
	local fresh = ctx("fresh", "Fresh")
	fresh.created_at = 1
	local stale = ctx("stale", "Stale")
	stale.created_at = 1789999999
	assert_order(core.context_list_view({ stale, fresh }, { fresh = 200, stale = 100 }), { "fresh", "stale" })
end)

check("sorts contexts with no log entry last, alphabetically by title", function()
	local rows = core.context_list_view({
		ctx("zeta", "Zeta"),
		ctx("logged", "Logged"),
		ctx("alpha", "alpha context"),
	}, { logged = 1789000000 })
	assert_order(rows, { "logged", "alpha", "zeta" })
end)

check("breaks recency ties on title, then slug", function()
	local rows = core.context_list_view({
		ctx("b-slug", "Same title"),
		ctx("a-slug", "Same title"),
		ctx("c-slug", "Another title"),
	}, { ["a-slug"] = 500, ["b-slug"] = 500, ["c-slug"] = 500 })
	assert_order(rows, { "c-slug", "a-slug", "b-slug" })
end)

check("treats a missing recency map as no logs at all", function()
	local rows = core.context_list_view({ ctx("beta", "Beta"), ctx("alpha", "Alpha") })
	assert_order(rows, { "alpha", "beta" })
end)

check("carries the fields the picker renders", function()
	local rows = core.context_list_view({ ctx("auth", "Auth redesign") }, { auth = 1789123456 })
	local row = rows[1]
	assert(row.context == "auth", "slug not carried")
	assert(row.title == "Auth redesign", "title not carried")
	assert(row.scope == "palekiwi/palekiwi", "scope not carried")
	assert(row.path == "/home/pl/cue/palekiwi/palekiwi/auth/context.md", "path not carried")
	assert(row.recency == 1789123456, "recency not attached to the row")
end)

if failures == 0 then
	print("\nAll tests passed.")
else
	print(string.format("\n%d test(s) FAILED.", failures))
	os.exit(1)
end
