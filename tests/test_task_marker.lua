-- Standalone tests for cue.core.task_marker_for
-- Run: luajit tests/test_task_marker.lua
--
-- task_marker_for is the pure helper behind the task-picker marker column
-- and the marker-based sort. Given a task slug, its status string, and the
-- active task slug, it returns the width-1 marker character:
--   "*" = active task (overrides any other marker)
--   "!" = in-progress
--   " " = otherwise
--
-- Mocks the minimal `vim` global so the real module can be required without
-- a running Neovim instance (mirrors test_active_task.lua).

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

-- Active task slug wins, regardless of status.
check("active task shows * even when in-progress", function()
	local m = core.task_marker_for("auth", "in-progress", "auth")
	assert(m == "*", "expected *, got " .. tostring(m))
end)

check("active task shows * when complete", function()
	local m = core.task_marker_for("auth", "complete", "auth")
	assert(m == "*", "expected *, got " .. tostring(m))
end)

-- Non-active in-progress task shows "!".
check("non-active in-progress task shows !", function()
	local m = core.task_marker_for("auth", "in-progress", "other")
	assert(m == "!", "expected !, got " .. tostring(m))
end)

-- Status match is case-insensitive (frontmatter may use "In-Progress").
check("in-progress match is case-insensitive", function()
	local m = core.task_marker_for("auth", "In-Progress", "other")
	assert(m == "!", "expected !, got " .. tostring(m))
end)

-- Non-active open/complete/closed tasks show a blank marker.
check("non-active open task shows blank", function()
	local m = core.task_marker_for("auth", "open", "other")
	assert(m == " ", "expected space, got " .. tostring(m))
end)

check("non-active complete task shows blank", function()
	local m = core.task_marker_for("auth", "complete", "other")
	assert(m == " ", "expected space, got " .. tostring(m))
end)

check("non-active closed task shows blank", function()
	local m = core.task_marker_for("auth", "closed", "other")
	assert(m == " ", "expected space, got " .. tostring(m))
end)

-- Missing/nil status shows blank.
check("nil status shows blank", function()
	local m = core.task_marker_for("auth", nil, "other")
	assert(m == " ", "expected space, got " .. tostring(m))
end)

-- No active task at all: in-progress still surfaces as "!".
check("nil active slug still surfaces in-progress as !", function()
	local m = core.task_marker_for("auth", "in-progress", nil)
	assert(m == "!", "expected !, got " .. tostring(m))
end)

check("nil active slug with open status shows blank", function()
	local m = core.task_marker_for("auth", "open", nil)
	assert(m == " ", "expected space, got " .. tostring(m))
end)

if failures == 0 then
	print("\nAll tests passed.")
else
	print(string.format("\n%d test(s) FAILED.", failures))
	os.exit(1)
end
