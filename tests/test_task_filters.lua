-- Standalone tests for cue.core.task_status_excluded / type_excluded
-- Run: luajit tests/test_task_filters.lua
--
-- Pure filter decisions behind the task picker (see picker.pick_artifacts).
--
-- task_status_excluded(fm, opts):
--   opts.status set (positive filter, e.g. inbox picker) -> keep ONLY
--   entries whose status equals it; everything else (including a
--   missing status) is excluded.
--   opts.board set (<C-t> board) -> hide statuses listed in
--   config.HIDDEN_TASK_STATUSES (complete, closed, inbox). Missing
--   status stays visible.
--   neither opt -> nothing excluded.
--
-- type_excluded(category, opts):
--   opts.exclude_type set -> true only for that category (fixes the
--   dead exclude_type kwarg historically passed by the <A-t> mapping).

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

local function fm(status)
	return { status = status }
end

-- ─── task_status_excluded: board mode (C-t) ───────────────────────────

check("board hides closed", function()
	assert(core.task_status_excluded(fm("closed"), { board = true }), "closed should be hidden")
end)

check("board hides inbox", function()
	assert(core.task_status_excluded(fm("inbox"), { board = true }), "inbox should be hidden")
end)

check("board keeps open", function()
	assert(not core.task_status_excluded(fm("open"), { board = true }), "open should stay visible")
end)

check("board keeps in-progress", function()
	assert(not core.task_status_excluded(fm("in-progress"), { board = true }), "in-progress should stay visible")
end)

check("board hides complete", function()
	assert(core.task_status_excluded(fm("complete"), { board = true }), "complete should be hidden")
end)

check("board status match is case-insensitive", function()
	assert(core.task_status_excluded(fm("Closed"), { board = true }), "Closed should be hidden")
end)

check("board without status stays visible", function()
	assert(not core.task_status_excluded({}, { board = true }), "missing status should stay visible")
end)

-- ─── task_status_excluded: positive filter (inbox picker) ────────────

check("status filter keeps only matching status", function()
	assert(core.task_status_excluded(fm("open"), { status = "inbox" }), "open excluded from inbox picker")
	assert(not core.task_status_excluded(fm("inbox"), { status = "inbox" }), "inbox kept in inbox picker")
end)

check("status filter excludes missing status", function()
	assert(core.task_status_excluded({}, { status = "inbox" }), "missing status excluded from inbox picker")
end)

check("status filter wins over board", function()
	-- A closed card in a picker explicitly filtered to closed would be
	-- nonsense today, but the precedence must be deterministic: the
	-- positive filter is the more specific constraint.
	assert(not core.task_status_excluded(fm("closed"), { board = true, status = "closed" }), "positive filter wins")
end)

-- ─── task_status_excluded: no opts ────────────────────────────────────

check("no opts excludes nothing", function()
	assert(not core.task_status_excluded(fm("closed"), {}), "closed stays visible without board opt")
end)

check("nil opts excludes nothing", function()
	assert(not core.task_status_excluded(fm("inbox"), nil), "inbox stays visible without board opt")
end)

-- ─── task_status_excluded: nil safety ─────────────────────────────────

check("nil frontmatter stays visible", function()
	assert(not core.task_status_excluded(nil, { board = true }), "nil fm should stay visible")
	assert(not core.task_status_excluded(vim.NIL, { board = true }), "vim.NIL fm should stay visible")
end)

check("vim.NIL status treated as missing", function()
	local fm_nil_status = { status = vim.NIL }
	assert(not core.task_status_excluded(fm_nil_status, { board = true }), "NIL status should stay visible")
	assert(core.task_status_excluded(fm_nil_status, { status = "inbox" }), "NIL status excluded from inbox picker")
end)

-- ─── type_excluded ────────────────────────────────────────────────────

check("exclude_type hides only that category", function()
	local opts = { exclude_type = "task" }
	assert(core.type_excluded("task", opts), "task category excluded")
	assert(not core.type_excluded("spec", opts), "spec category kept")
	assert(not core.type_excluded("todo", opts), "todo category kept")
end)

check("no exclude_type excludes nothing", function()
	assert(not core.type_excluded("task", {}), "nothing excluded without opt")
	assert(not core.type_excluded("task", nil), "nil-safe without opt")
end)

if failures == 0 then
	print("\nAll tests passed.")
else
	print(string.format("\n%d test(s) FAILED.", failures))
	os.exit(1)
end
