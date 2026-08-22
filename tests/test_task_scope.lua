-- Standalone tests for cue.core.task_scope_for
-- Run: luajit tests/test_task_scope.lua
--
-- task_scope_for is the pure decision helper behind
-- picker.pick_active_task_artifacts() (<C-s> binding: artifacts in the
-- scope of the active task). Given the status object returned by
-- get_active_task() (which wraps `cue status --json`), it decides which
-- task context a picker should be scoped to:
--   active task slug -> { action = "pick", task = "<slug>" }
--   global (master)  -> { action = "notify", message = "..." }
--
-- The master/nil checks delegate to resolve_active_task_path so the two
-- helpers can never disagree about what counts as "no active task"
-- (mirrors test_active_task.lua).

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

-- A task slug is active -> pick, scoped to that slug.
check("picks scope for an active task slug", function()
	local d = core.task_scope_for({ context = "cue-nvim-picker-rework", global = false })
	assert(d.action == "pick", "expected action=pick, got " .. tostring(d.action))
	assert(d.task == "cue-nvim-picker-rework", "unexpected task: " .. tostring(d.task))
end)

check("picks scope when global flag is absent", function()
	local d = core.task_scope_for({ context = "auth-login" })
	assert(d.action == "pick", "expected action=pick, got " .. tostring(d.action))
	assert(d.task == "auth-login", "unexpected task: " .. tostring(d.task))
end)

-- Global (master) context -> notify, never pick.
check("notifies when global flag is true", function()
	local d = core.task_scope_for({ context = "master", global = true })
	assert(d.action == "notify", "expected action=notify, got " .. tostring(d.action))
end)

check("notifies when context is master without global flag", function()
	local d = core.task_scope_for({ context = "master" })
	assert(d.action == "notify", "expected action=notify, got " .. tostring(d.action))
end)

-- Missing/empty status -> notify (nil-safe).
check("notifies for nil status", function()
	local d = core.task_scope_for(nil)
	assert(d.action == "notify", "expected action=notify, got " .. tostring(d.action))
end)

check("notifies for empty context", function()
	local d = core.task_scope_for({ context = "" })
	assert(d.action == "notify", "expected action=notify, got " .. tostring(d.action))
end)

-- Notify decisions carry a message for the user.
check("notify decision carries a message", function()
	local d = core.task_scope_for({ context = "master", global = true })
	assert(type(d.message) == "string" and d.message ~= "", "notify decision needs a message")
end)

-- Pick decisions carry the slug; they must not carry a path (that is
-- resolve_active_task_path's contract for opening task cards).
check("pick decision carries task, not path", function()
	local d = core.task_scope_for({ context = "auth-login", global = false })
	assert(d.task ~= nil, "pick decision needs a task slug")
	assert(d.path == nil, "pick decision must not carry a path")
end)

if failures == 0 then
	print("\nAll tests passed.")
else
	print(string.format("\n%d test(s) FAILED.", failures))
	os.exit(1)
end
