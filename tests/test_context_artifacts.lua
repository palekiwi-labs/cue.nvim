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
--     one --type flag per approved group (task/spec/plan/note/trace, in that
--     order). bin/tmp are deferred, so they are never requested. Optional
--     repo dir (-C) and store root (--store) are supported.
--
--   core.artifact_display_title(artifact)
--     frontmatter.title when it is a nonempty string, else the filename.
--
--   core.context_artifacts_view(artifacts)
--     Filter to the five approved types, then order by group
--     (task, spec, plan, note, trace) and alphabetically by displayed title
--     within a group.
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

check("argv requests exactly the five approved types, in spec order", function()
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
	})
end)

check("argv never requests the deferred bin/tmp types", function()
	local argv = core.context_artifacts_argv("demo")
	for _, arg in ipairs(argv) do
		assert(arg ~= "bin", "bin is deferred and must not be requested")
		assert(arg ~= "tmp", "tmp is deferred and must not be requested")
	end
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

check("view groups by type in spec order: task, spec, plan, note, trace", function()
	local view = core.context_artifacts_view({
		artifact("trace", "t.md", "Trace one"),
		artifact("note", "n.md", "Note one"),
		artifact("plan", "p.md", "Plan one"),
		artifact("spec", "s.md", "Spec one"),
		artifact("task", "k.md", "Task one"),
	})
	assert_order(view, { "Task one", "Spec one", "Plan one", "Note one", "Trace one" })
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
	assert_order(view, { "Closed task", "Complete task", "Inbox task" })
end)

check("view drops the deferred bin/tmp types", function()
	local view = core.context_artifacts_view({
		artifact("bin", "state.json", "Binary"),
		artifact("tmp", "scratch.md", "Scratch"),
		artifact("task", "k.md", "Task one"),
	})
	assert_order(view, { "Task one" })
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

if failures == 0 then
	print("\nAll tests passed.")
else
	print(string.format("\n%d test(s) FAILED.", failures))
	os.exit(1)
end
