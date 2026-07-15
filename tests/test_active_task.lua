-- Standalone tests for cue.core.resolve_active_task_path
-- Run: luajit tests/test_active_task.lua
--
-- resolve_active_task_path is the pure decision helper behind
-- open_active_task(). Given the status object returned by get_active_task()
-- (which wraps `cue status --json`), it decides whether to open the active
-- task card or notify the user that there is no active task (global context).
--
-- Mocks the minimal `vim` global so the real module can be required without
-- a running Neovim instance.

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

-- A task slug is active -> resolve the task-card path under master.
check("opens task card for an active task slug", function()
	local d = core.resolve_active_task_path({ context = "worktrees-and-dirs", global = false })
	assert(d.action == "open", "expected action=open, got " .. tostring(d.action))
	assert(d.path == ".cue/master/task/worktrees-and-dirs.md", "unexpected path: " .. tostring(d.path))
end)

-- Explicit global flag (master context) -> notify, never open.
check("notifies when global flag is true", function()
	local d = core.resolve_active_task_path({ context = "master", global = true })
	assert(d.action == "notify", "expected action=notify, got " .. tostring(d.action))
	assert(d.message ~= nil and d.message ~= "", "notify decision must carry a message")
end)

-- Defensive: context == "master" without the flag is still treated as global.
check("treats context=master as global even without the flag", function()
	local d = core.resolve_active_task_path({ context = "master" })
	assert(d.action == "notify", "expected action=notify for master context")
end)

-- Defensive: a malformed status (no context) -> notify, never open.
check("notifies when status has no context", function()
	local d = core.resolve_active_task_path({ global = false })
	assert(d.action == "notify", "expected action=notify when context is absent")
end)

-- Defensive: nil status -> notify.
check("notifies when status is nil", function()
	local d = core.resolve_active_task_path(nil)
	assert(d.action == "notify", "expected action=notify for nil status")
end)

if failures == 0 then
	print("\nAll tests passed.")
else
	print(string.format("\n%d test(s) FAILED.", failures))
	os.exit(1)
end
