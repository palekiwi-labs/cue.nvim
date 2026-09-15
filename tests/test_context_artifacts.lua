-- Standalone tests for the pure helpers behind the context artifact picker
-- Run: luajit tests/test_context_artifacts.lua
--
-- Covers spec section 8 (palekiwi/palekiwi/cue-nvim-workflow/spec/index.md):
--
--   core.normalize_context(context)
--     Explicit context only. nil/non-string/blank -> nil. The picker must
--     NEVER fall back to the active context when none is given.
--
--   core.context_artifacts_argv(context, opts)
--     `cue list --context <ctx> --json --frontmatter --type ...` argv, with
--     one --type flag per listed group (task/spec/plan/note/trace, then the
--     non-markdown bin/tmp, in that order). Optional repo dir (-C) and store
--     root (--store) are supported.
--
--   core.artifact_display_title(artifact)
--     frontmatter.title when it is a nonempty string, else the filename.
--
--   core.context_artifacts_view(artifacts)
--     Filter to the seven listed types, then order by group
--     (task, spec, plan, note, trace, bin, tmp) and alphabetically by
--     displayed title within a group.
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

local function artifact(cue_type, name, title)
	local fm = nil
	if title ~= nil then
		fm = { title = title }
	end
	return {
		path = "/store/scope/demo/" .. cue_type .. "/" .. name,
		name = name,
		context = "demo",
		type = cue_type,
		frontmatter = fm,
	}
end

local function titles(list)
	local out = {}
	for _, a in ipairs(list) do
		table.insert(out, core.artifact_display_title(a))
	end
	return out
end

local function assert_order(list, expected)
	local got = titles(list)
	assert(#got == #expected, string.format("row count %d ~= %d: [%s]", #got, #expected, table.concat(got, ", ")))
	for i, want in ipairs(expected) do
		assert(
			got[i] == want,
			string.format("row %d = %q, expected %q ([%s])", i, tostring(got[i]), want, table.concat(got, ", "))
		)
	end
end

-- ─── normalize_context ────────────────────────────────────────────────

check("normalize_context keeps a plain slug", function()
	assert(core.normalize_context("cue-nvim-workflow") == "cue-nvim-workflow", "slug should pass through")
end)

check("normalize_context trims surrounding whitespace", function()
	assert(core.normalize_context("  demo\n") == "demo", "whitespace should be trimmed")
end)

check("normalize_context rejects nil (no active-context fallback)", function()
	assert(core.normalize_context(nil) == nil, "nil context must not resolve")
end)

check("normalize_context rejects blank and non-string input", function()
	assert(core.normalize_context("") == nil, "empty string must not resolve")
	assert(core.normalize_context("   ") == nil, "blank string must not resolve")
	assert(core.normalize_context(42) == nil, "non-string must not resolve")
	assert(core.normalize_context({}) == nil, "table must not resolve")
end)

-- ─── context_artifacts_argv ───────────────────────────────────────────

check("argv requests exactly the seven listed types, in display order", function()
	assert_argv(core.context_artifacts_argv("demo"), {
		"cue",
		"list",
		"--context",
		"demo",
		"--json",
		"--frontmatter",
		"--type",
		"task",
		"--type",
		"spec",
		"--type",
		"plan",
		"--type",
		"note",
		"--type",
		"trace",
		"--type",
		"bin",
		"--type",
		"tmp",
	})
end)

check("argv appends bin and tmp after the markdown groups", function()
	-- The markdown groups keep their spec order; the non-markdown types are
	-- appended rather than interleaved, so the existing rows do not move.
	local argv = core.context_artifacts_argv("demo")
	assert(argv[#argv - 2] == "bin", "bin is the second-to-last type")
	assert(argv[#argv] == "tmp", "tmp is the last type")
end)

check("argv uses current CLI flags only", function()
	local argv = core.context_artifacts_argv("demo")
	for _, arg in ipairs(argv) do
		assert(arg ~= "--task", "legacy --task flag must not be used")
		assert(arg ~= "--all", "legacy --all flag must not be used")
		assert(arg ~= "--include-gitignored", "legacy --include-gitignored flag must not be used")
	end
end)

check("argv carries an explicit repo dir and store root", function()
	local argv = core.context_artifacts_argv("demo", { dir = "/repo", store = "/store" })
	assert_argv(argv, {
		"cue",
		"list",
		"-C",
		"/repo",
		"--store",
		"/store",
		"--context",
		"demo",
		"--json",
		"--frontmatter",
		"--type",
		"task",
		"--type",
		"spec",
		"--type",
		"plan",
		"--type",
		"note",
		"--type",
		"trace",
		"--type",
		"bin",
		"--type",
		"tmp",
	})
end)

check("argv trims the context before passing it to the CLI", function()
	local argv = core.context_artifacts_argv(" demo ")
	assert(argv[3] == "--context" and argv[4] == "demo", "context should be trimmed in argv")
end)

check("argv is nil without an explicit context", function()
	assert(core.context_artifacts_argv(nil) == nil, "nil context yields no command")
	assert(core.context_artifacts_argv("") == nil, "blank context yields no command")
	assert(core.context_artifacts_argv("  ") == nil, "whitespace context yields no command")
end)

-- ─── artifact_display_title ───────────────────────────────────────────

check("display title prefers the frontmatter title", function()
	local a = artifact("task", "context-artifact-picker.md", "Build the context artifact picker")
	assert(core.artifact_display_title(a) == "Build the context artifact picker", "title should win")
end)

check("display title falls back to the filename", function()
	local a = artifact("note", "grouped-artifact-browser.md")
	assert(core.artifact_display_title(a) == "grouped-artifact-browser.md", "filename fallback expected")
end)

check("display title falls back for empty/NIL/non-string titles", function()
	local blank = artifact("spec", "index.md", "")
	assert(core.artifact_display_title(blank) == "index.md", "empty title falls back")

	local whitespace = artifact("spec", "index.md", "   ")
	assert(core.artifact_display_title(whitespace) == "index.md", "blank title falls back")

	local nil_title = artifact("spec", "index.md")
	nil_title.frontmatter = { title = vim.NIL }
	assert(core.artifact_display_title(nil_title) == "index.md", "vim.NIL title falls back")

	local numeric = artifact("spec", "index.md")
	numeric.frontmatter = { title = 2026 }
	assert(core.artifact_display_title(numeric) == "index.md", "non-string title falls back")
end)

check("display title survives missing frontmatter", function()
	local a = artifact("trace", "handoff.md")
	a.frontmatter = nil
	assert(core.artifact_display_title(a) == "handoff.md", "nil frontmatter falls back to filename")
	a.frontmatter = vim.NIL
	assert(core.artifact_display_title(a) == "handoff.md", "vim.NIL frontmatter falls back to filename")
end)

-- ─── context_artifacts_view: grouping and ordering ────────────────────

check("view groups by type: task, spec, plan, note, trace, bin, tmp", function()
	local view = core.context_artifacts_view({
		artifact("tmp", "scratch.diff"),
		artifact("bin", "run.sh"),
		artifact("trace", "t.md", "Trace one"),
		artifact("note", "n.md", "Note one"),
		artifact("plan", "p.md", "Plan one"),
		artifact("spec", "s.md", "Spec one"),
		artifact("task", "k.md", "Task one"),
	})
	assert_order(view, {
		"Task one",
		"Spec one",
		"Plan one",
		"Note one",
		"Trace one",
		"run.sh",
		"scratch.diff",
	})
end)

check("view sorts alphabetically by displayed title inside a group", function()
	local view = core.context_artifacts_view({
		artifact("task", "zulu.md", "Charlie task"),
		artifact("task", "alpha.md", "Alpha task"),
		artifact("task", "mike.md", "Bravo task"),
	})
	assert_order(view, { "Alpha task", "Bravo task", "Charlie task" })
end)

check("view sorts on the DISPLAYED title, not the filename", function()
	-- The filename order (aaa, zzz) is the inverse of the title order.
	local view = core.context_artifacts_view({
		artifact("note", "aaa.md", "Zebra note"),
		artifact("note", "zzz.md", "Apple note"),
	})
	assert_order(view, { "Apple note", "Zebra note" })
end)

check("view sorts filename fallbacks alongside titles", function()
	local view = core.context_artifacts_view({
		artifact("note", "beta.md"),
		artifact("note", "alpha-titled.md", "Alpha note"),
		artifact("note", "gamma.md"),
	})
	assert_order(view, { "Alpha note", "beta.md", "gamma.md" })
end)

check("view orders titles case-insensitively", function()
	local view = core.context_artifacts_view({
		artifact("plan", "b.md", "beta plan"),
		artifact("plan", "a.md", "Alpha plan"),
		artifact("plan", "c.md", "Gamma plan"),
	})
	assert_order(view, { "Alpha plan", "beta plan", "Gamma plan" })
end)

check("view breaks equal-title ties on filename for determinism", function()
	local view = core.context_artifacts_view({
		artifact("spec", "second.md", "Same"),
		artifact("spec", "first.md", "Same"),
	})
	assert(view[1].name == "first.md", "expected first.md first, got " .. tostring(view[1].name))
	assert(view[2].name == "second.md", "expected second.md second, got " .. tostring(view[2].name))
end)

check("view breaks colliding-basename ties on the full path", function()
	-- Artifacts nest (spec/alpha/index.md, spec/beta/index.md), so the
	-- basename is NOT unique and cannot make the order total on its own.
	-- table.sort is unstable, so a genuinely equal pair may come out in
	-- either order; the path is the last discriminator.
	local beta = artifact("spec", "index.md", "Same")
	beta.path = "/store/scope/demo/spec/beta/index.md"
	local alpha = artifact("spec", "index.md", "Same")
	alpha.path = "/store/scope/demo/spec/alpha/index.md"

	local view = core.context_artifacts_view({ beta, alpha })
	assert(view[1].path == alpha.path, "expected the alpha path first, got " .. tostring(view[1].path))
	assert(view[2].path == beta.path, "expected the beta path second, got " .. tostring(view[2].path))

	-- Same input, opposite order in: the result must not change.
	local reversed = core.context_artifacts_view({ alpha, beta })
	assert(reversed[1].path == alpha.path, "ordering must not depend on input order")
	assert(reversed[2].path == beta.path, "ordering must not depend on input order")
end)

check("comparator is asymmetric for colliding basenames", function()
	local beta = artifact("spec", "index.md", "Same")
	beta.path = "/store/scope/demo/spec/beta/index.md"
	local alpha = artifact("spec", "index.md", "Same")
	alpha.path = "/store/scope/demo/spec/alpha/index.md"

	assert(core.context_artifact_less(alpha, beta), "alpha path sorts before beta path")
	assert(not core.context_artifact_less(beta, alpha), "comparator must be asymmetric")
	assert(not core.context_artifact_less(alpha, alpha), "an artifact never sorts before itself")
end)

-- ─── context_artifacts_view: membership ───────────────────────────────

check("view includes tasks regardless of status", function()
	local inbox = artifact("task", "inbox.md", "Inbox task")
	inbox.frontmatter = { title = "Inbox task", status = "inbox" }
	local closed = artifact("task", "closed.md", "Closed task")
	closed.frontmatter = { title = "Closed task", status = "closed" }
	local complete = artifact("task", "complete.md", "Complete task")
	complete.frontmatter = { title = "Complete task", status = "complete" }

	local view = core.context_artifacts_view({ closed, complete, inbox })
	assert_order(view, { "Inbox task", "Closed task", "Complete task" })
end)

check("view keeps bin and tmp, listed after the markdown groups", function()
	local view = core.context_artifacts_view({
		artifact("bin", "state.json", "Binary"),
		artifact("tmp", "scratch.md", "Scratch"),
		artifact("task", "k.md", "Task one"),
	})
	assert_order(view, { "Task one", "Binary", "Scratch" })
end)

check("view orders tmp rows by the stamp parsed from the group directory", function()
	-- tmp rows carry no frontmatter, so the ONLY ordering key is the
	-- nanosecond stamp in the group directory. Newest first, undated last.
	local older = artifact("tmp", "1789300000853051953-d8dc048d49/older.json")
	local newer = artifact("tmp", "1789366283853051953-d8dc048d49/newer.json")
	local undated = artifact("tmp", "legacy.diff")
	local view = core.context_artifacts_view({ undated, older, newer })
	assert_order(view, {
		"1789366283853051953-d8dc048d49/newer.json",
		"1789300000853051953-d8dc048d49/older.json",
		"legacy.diff",
	})
end)

check("view drops unknown types and malformed rows", function()
	local no_path = artifact("note", "n.md", "No path")
	no_path.path = nil
	local view = core.context_artifacts_view({
		artifact("doc", "d.md", "Legacy doc"),
		artifact("todo", "t.md", "Legacy todo"),
		no_path,
		artifact("spec", "index.md", "Spec one"),
	})
	assert_order(view, { "Spec one" })
end)

check("view is empty-safe", function()
	assert(#core.context_artifacts_view({}) == 0, "empty input yields empty view")
	assert(#core.context_artifacts_view(nil) == 0, "nil input yields empty view")
end)

-- ─── active_context_argv ──────────────────────────────────────────────

check("active_context_argv emits cue status --json by default", function()
	assert_argv(core.active_context_argv(), { "cue", "status", "--json" })
	assert_argv(core.active_context_argv({}), { "cue", "status", "--json" })
end)

check("active_context_argv carries dir (-C) and store (--store)", function()
	assert_argv(core.active_context_argv({ dir = "/my/repo" }), { "cue", "status", "-C", "/my/repo", "--json" })
	assert_argv(core.active_context_argv({ store = "/my/cue" }), { "cue", "status", "--store", "/my/cue", "--json" })
	assert_argv(
		core.active_context_argv({ dir = "/my/repo", store = "/my/cue" }),
		{ "cue", "status", "-C", "/my/repo", "--store", "/my/cue", "--json" }
	)
end)

-- ─── active_context_decision ──────────────────────────────────────────

check("active_context_decision picks a valid context slug", function()
	local d = core.active_context_decision({ context = "cue-nvim-workflow" })
	assert(d.action == "pick", "expected action=pick, got " .. tostring(d.action))
	assert(d.context == "cue-nvim-workflow", "unexpected context: " .. tostring(d.context))
end)

check("active_context_decision trims surrounding whitespace", function()
	local d = core.active_context_decision({ context = "  auth-login  " })
	assert(d.action == "pick", "expected action=pick")
	assert(d.context == "auth-login", "context should be trimmed: " .. tostring(d.context))
end)

check("active_context_decision notifies when context is unset or empty", function()
	local cases = {
		{ name = "nil status", status = nil },
		{ name = "empty status", status = {} },
		{ name = "nil context", status = { context = nil } },
		{ name = "vim.NIL context", status = { context = vim.NIL } },
		{ name = "empty string context", status = { context = "" } },
		{ name = "whitespace-only context", status = { context = "   " } },
		{ name = "non-string context", status = { context = 123 } },
	}
	for _, c in ipairs(cases) do
		local d = core.active_context_decision(c.status)
		assert(d.action == "notify", string.format("%s: expected action=notify, got %s", c.name, tostring(d.action)))
		assert(type(d.message) == "string" and d.message ~= "", string.format("%s: notify needs a message", c.name))
	end
end)

-- ─── status_scope ─────────────────────────────────────────────────────
-- The scope half of `cue status --json`, read on its own. The ACTIVE
-- CONTEXT is deliberately not consulted: scope is a property of the
-- repository the query was aimed at (`-C`), so it is valid even when the
-- branch has no context, and the browsed context is whatever the caller
-- asked for.

check("status_scope reads the scope field, never the context", function()
	local status = {
		scope = "palekiwi/palekiwi",
		context = "cue-platform-direction",
		address = "palekiwi/palekiwi/cue-platform-direction",
		store = "/home/pl/cue",
	}
	assert(core.status_scope(status) == "palekiwi/palekiwi", "expected the scope field")
end)

check("status_scope is independent of the active context", function()
	-- A repository with no active context still has a scope: the address of
	-- an artifact browsed there must not depend on the branch association.
	assert(core.status_scope({ scope = "palekiwi-labs/cue" }) == "palekiwi-labs/cue", "scope without a context")
	assert(core.status_scope({ scope = "palekiwi-labs/cue", context = vim.NIL }) == "palekiwi-labs/cue", "null context")
end)

check("status_scope trims and rejects unusable values", function()
	assert(core.status_scope({ scope = "  palekiwi/palekiwi \n" }) == "palekiwi/palekiwi", "scope is trimmed")
	assert(core.status_scope(nil) == nil, "no status, no scope")
	assert(core.status_scope({}) == nil, "no scope field")
	assert(core.status_scope({ scope = "" }) == nil, "empty scope")
	assert(core.status_scope({ scope = "   " }) == nil, "blank scope")
	assert(core.status_scope({ scope = vim.NIL }) == nil, "JSON null scope")
	assert(core.status_scope({ scope = 7 }) == nil, "non-string scope")
	assert(core.status_scope("palekiwi/palekiwi") == nil, "a bare string is not a status table")
end)

-- ─── artifact_address ─────────────────────────────────────────────────
-- The canonical address of an artifact: <scope>/<context>/<type>/<name>,
-- the same form cue writes into `parent:` and `refs:` frontmatter. It is
-- store-relative BY CONSTRUCTION: nothing here ever sees the store root or
-- the absolute path, so a store path cannot leak into the value.

check("artifact_address composes scope, context, type and name", function()
	local a = artifact("spec", "index.md", "Spec")
	assert(
		core.artifact_address("palekiwi/palekiwi", a) == "palekiwi/palekiwi/demo/spec/index.md",
		"expected the canonical address, got " .. tostring(core.artifact_address("palekiwi/palekiwi", a))
	)
end)

check("artifact_address keeps the grouped tmp directory in the name", function()
	-- `cue list --json` reports a tmp row's name WITH its group directory
	-- (`<nanosecond timestamp>-<short commit hash>/<file>`), and the group
	-- is part of the address: without it the address names no file.
	local grouped = artifact("tmp", "1789366283853051953-d8dc048d49/review-comments-delta.json")
	assert(
		core.artifact_address("palekiwi/palekiwi", grouped)
			== "palekiwi/palekiwi/demo/tmp/1789366283853051953-d8dc048d49/review-comments-delta.json",
		"the tmp group directory belongs in the address"
	)
end)

check("artifact_address handles bin rows, which carry no frontmatter", function()
	assert(
		core.artifact_address("palekiwi/palekiwi", artifact("bin", "run.sh")) == "palekiwi/palekiwi/demo/bin/run.sh",
		"bin rows address the same way"
	)
end)

check("artifact_address uses the scope it is given, not the current repo", function()
	-- Browsing another repository's scope (`opts.dir`) must yield THAT
	-- scope's address; the picker resolves the scope from a status query
	-- aimed at the same directory.
	local a = artifact("plan", "index.md", "Plan")
	assert(
		core.artifact_address("palekiwi-labs/cue", a) == "palekiwi-labs/cue/demo/plan/index.md",
		"the supplied scope wins"
	)
end)

check("artifact_address falls back to the queried context slug", function()
	local a = { type = "note", name = "idea.md" }
	assert(
		core.artifact_address("palekiwi/palekiwi", a, "demo") == "palekiwi/palekiwi/demo/note/idea.md",
		"a row without a context uses the context the picker queried"
	)
	local rowed = { type = "note", name = "idea.md", context = "row-context" }
	assert(
		core.artifact_address("palekiwi/palekiwi", rowed, "demo") == "palekiwi/palekiwi/row-context/note/idea.md",
		"the row's own context wins over the fallback"
	)
end)

check("artifact_address yields nil rather than a partial address", function()
	local a = artifact("spec", "index.md", "Spec")
	local cases = {
		{ name = "no scope", scope = nil, artifact = a },
		{ name = "blank scope", scope = "   ", artifact = a },
		{ name = "JSON null scope", scope = vim.NIL, artifact = a },
		{ name = "non-string scope", scope = 7, artifact = a },
		{ name = "no artifact", scope = "s/s", artifact = nil },
		{ name = "non-table artifact", scope = "s/s", artifact = "spec/index.md" },
		{ name = "no context", scope = "s/s", artifact = { type = "spec", name = "index.md" } },
		{ name = "no type", scope = "s/s", artifact = { context = "demo", name = "index.md" } },
		{ name = "no name", scope = "s/s", artifact = { context = "demo", type = "spec" } },
		{ name = "blank name", scope = "s/s", artifact = { context = "demo", type = "spec", name = "  " } },
	}
	for _, c in ipairs(cases) do
		assert(
			core.artifact_address(c.scope, c.artifact) == nil,
			string.format("%s: expected nil, got %s", c.name, tostring(core.artifact_address(c.scope, c.artifact)))
		)
	end
end)

check("artifact_address never emits an absolute path", function()
	-- The row's `path` is the absolute store path. It is not an input here,
	-- and an absolute-looking name is refused rather than concatenated into
	-- an address with a `//` in it.
	local absolute = {
		context = "demo",
		type = "spec",
		name = "/home/pl/cue/palekiwi/palekiwi/demo/spec/index.md",
		path = "/home/pl/cue/palekiwi/palekiwi/demo/spec/index.md",
	}
	assert(core.artifact_address("palekiwi/palekiwi", absolute) == nil, "an absolute name is not an address")

	local address = core.artifact_address("palekiwi/palekiwi", artifact("spec", "index.md", "Spec"))
	assert(address:sub(1, 1) ~= "/", "an address is store-relative")
	assert(not address:find("//", 1, true), "an address has no doubled separator")
end)

check("artifact_address normalises stray separators on the scope", function()
	local a = artifact("spec", "index.md", "Spec")
	assert(
		core.artifact_address("palekiwi/palekiwi/", a) == "palekiwi/palekiwi/demo/spec/index.md",
		"a trailing slash on the scope is dropped"
	)
end)

if failures == 0 then
	print("\nAll tests passed.")
else
	print(string.format("\n%d test(s) FAILED.", failures))
	os.exit(1)
end
