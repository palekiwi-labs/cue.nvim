-- Standalone tests for cue.core.task_less
-- Run: luajit tests/test_task_sort.lua
--
-- task_less is the pure comparator that orders task cards in the task
-- picker. Order of precedence:
--   1. marker:  "*" (active) < "!" (in-progress) < blank
--   2. finished: complete/closed sink to the bottom (BEFORE priority)
--   3. priority: critical < high < normal < low
--   4. recency (newer first), then name
--
-- The critical invariant under test: a completed task must never outrank
-- an open one, regardless of priority. This is the regression that
-- motivated extracting the comparator into a pure, tested function.

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

-- Build a minimal task artifact shaped like the cue list --json output.
local function task(slug, status, priority, ts)
	return {
		name = slug .. ".md",
		category = "task",
		branch = "master",
		commit_timestamp = ts or 0,
		frontmatter = {
			status = status,
			priority = priority or "normal",
			title = slug,
		},
	}
end

-- Active (*) always ranks first, even over an in-progress task.
check("active task ranks above in-progress", function()
	local a = task("auth", "open", "normal")          -- becomes * (active)
	local b = task("other", "in-progress", "critical")
	assert(core.task_less(a, b, "auth") == true, "active should come first")
end)

-- Active overrides finished: an active+complete task still ranks first.
check("active overrides complete", function()
	local a = task("auth", "complete", "normal")      -- * (active)
	local b = task("other", "open", "low")
	assert(core.task_less(a, b, "auth") == true, "active complete should rank first")
end)

-- In-progress (!) ranks above open (blank).
check("in-progress ranks above open", function()
	local a = task("a", "in-progress", "low")
	local b = task("b", "open", "critical")
	assert(core.task_less(a, b, nil) == true, "in-progress should rank above open")
end)

-- THE REGRESSION: a complete task sinks below an open task regardless of
-- priority. finished must beat priority.
check("complete sinks below open (same priority)", function()
	local complete = task("done", "complete", "normal")
	local open = task("live", "open", "normal")
	assert(core.task_less(complete, open, nil) == false, "complete must not rank above open")
	assert(core.task_less(open, complete, nil) == true, "open must rank above complete")
end)

check("complete+critical sinks below open+low", function()
	local complete = task("done", "complete", "critical")
	local open = task("live", "open", "low")
	assert(core.task_less(complete, open, nil) == false,
		"complete+critical must sink below open+low")
	assert(core.task_less(open, complete, nil) == true,
		"open+low must rank above complete+critical")
end)

check("closed sinks below open", function()
	local closed = task("done", "closed", "high")
	local open = task("live", "open", "low")
	assert(core.task_less(closed, open, nil) == false, "closed must sink below open")
end)

-- Within the same marker + finished group, priority orders the rest.
check("priority orders within open group", function()
	local high = task("h", "open", "high")
	local low = task("l", "open", "low")
	assert(core.task_less(high, low, nil) == true, "high priority should rank above low")
	assert(core.task_less(low, high, nil) == false, "low priority should not rank above high")
end)

check("priority orders within complete group", function()
	local high = task("h", "complete", "high")
	local low = task("l", "complete", "low")
	assert(core.task_less(high, low, nil) == true, "high+complete above low+complete")
end)

-- Recency breaks priority ties (newer first).
check("recency breaks a priority tie", function()
	local old = task("old", "open", "normal", 100)
	local new = task("new", "open", "normal", 200)
	assert(core.task_less(new, old, nil) == true, "newer should rank above older")
end)

-- Identical tasks are stable (neither before the other).
check("identical tasks compare false both ways", function()
	local a = task("x", "open", "normal", 5)
	local b = task("x", "open", "normal", 5)
	assert(core.task_less(a, b, nil) == false, "a before b should be false")
	assert(core.task_less(b, a, nil) == false, "b before a should be false")
end)

if failures == 0 then
	print("\nAll tests passed.")
else
	print(string.format("\n%d test(s) FAILED.", failures))
	os.exit(1)
end
