-- Regression guard for the central-store migration.
-- Run: luajit tests/test_legacy_pruned.lua
--
-- The legacy model kept artifacts in a per-repository `.cue/` directory and
-- hung every task off a global `master` board. Both are abolished. The
-- helpers below resolved paths inside `.cue/`, so they cannot work against
-- the central store and were removed rather than repaired.
--
-- This file asserts their ABSENCE. A symbol reappearing here means someone
-- reintroduced a store-layout assumption the plugin is not allowed to make:
-- paths come from the CLI (`cue add`, `cue list --json`, `cue context list
-- --json`), never from string concatenation in Lua.

package.path = package.path .. ";./lua/?.lua"

vim = {} -- luacheck: ignore (global stub)

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

local function assert_absent(tbl, name, label)
	if tbl[name] ~= nil then
		error(string.format("%s.%s must be removed (found a %s)", label, name, type(tbl[name])))
	end
end

-- Resolved `.cue/master/task/<slug>.md` from the active context. The active
-- context is no longer a task card, and there is no master task directory.
check("the active-task card helpers are gone", function()
	assert_absent(core, "resolve_active_task_path", "core")
	assert_absent(core, "task_scope_for", "core")
	assert_absent(core, "open_active_task", "core")
end)

-- Read `.cue/<task>/log.md`. Logs are now per-entry JSON files under
-- `log/<timestamp>.json`, rendered through `cue log list --format md`.
check("the single-file log reader is gone", function()
	assert_absent(core, "open_log", "core")
end)

-- Prompted for a task `kind` (build|design|research|review|coord). `kind`
-- is a context field on context.md, never task frontmatter.
check("the task-kind prompt is gone", function()
	assert_absent(core, "prompt_task_kind", "core")
end)

-- Resolved the active TASK, falling back to `{ context = "master" }`. There
-- is no master and no fallback: cue status returns an unset context, and
-- core.get_active_context reports that honestly as nil.
check("the master-fallback status reader is gone", function()
	assert_absent(core, "get_active_task", "core")
end)

-- The rendering and ordering layer of the deleted master-board task picker.
-- Marker column ("*" active / "!" in-progress), done-dimming highlights, tag
-- column, board status filters and the composite row comparator. All of it
-- described a board that no longer exists; a context-first task view will be
-- specified against the new model rather than ported from this one.
check("the task-board row helpers are gone", function()
	assert_absent(core, "task_marker_for", "core")
	assert_absent(core, "task_less", "core")
	assert_absent(core, "task_tags", "core")
	assert_absent(core, "task_status_excluded", "core")
	assert_absent(core, "type_excluded", "core")
	assert_absent(core, "done_highlight_for", "core")
	assert_absent(core, "is_done", "core")
	assert_absent(core, "is_finished", "core")
end)

if failures == 0 then
	print("\nAll tests passed.")
else
	print(string.format("\n%d test(s) FAILED.", failures))
	os.exit(1)
end
