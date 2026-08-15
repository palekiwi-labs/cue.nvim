-- Standalone tests for cue.core.done_highlight_for
-- Run: luajit tests/test_done_highlight.lua
--
-- done_highlight_for is the pure helper behind the artifact-picker row
-- highlight for finished artifacts. Given a frontmatter status string it
-- returns the highlight group name:
--   closed   -> "CueStatusDone"     (grey + strikethrough)
--   complete -> "CueStatusComplete" (grey, no strikethrough)
--   other    -> nil (not finished, no highlight override)
--
-- Mocks the minimal `vim` global so the real module can be required without
-- a running Neovim instance (mirrors test_task_marker.lua).

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

check("closed maps to CueStatusDone (strikethrough)", function()
	local hl = core.done_highlight_for("closed")
	assert(hl == "CueStatusDone", "expected CueStatusDone, got " .. tostring(hl))
end)

check("complete maps to CueStatusComplete (no strikethrough)", function()
	local hl = core.done_highlight_for("complete")
	assert(hl == "CueStatusComplete", "expected CueStatusComplete, got " .. tostring(hl))
end)

check("open maps to nil", function()
	local hl = core.done_highlight_for("open")
	assert(hl == nil, "expected nil, got " .. tostring(hl))
end)

check("in-progress maps to nil", function()
	local hl = core.done_highlight_for("in-progress")
	assert(hl == nil, "expected nil, got " .. tostring(hl))
end)

-- Status match is case-insensitive (frontmatter may use "Closed").
check("match is case-insensitive", function()
	local hl = core.done_highlight_for("Closed")
	assert(hl == "CueStatusDone", "expected CueStatusDone, got " .. tostring(hl))
end)

check("Complete (capitalized) maps to CueStatusComplete", function()
	local hl = core.done_highlight_for("Complete")
	assert(hl == "CueStatusComplete", "expected CueStatusComplete, got " .. tostring(hl))
end)

check("nil status maps to nil", function()
	local hl = core.done_highlight_for(nil)
	assert(hl == nil, "expected nil, got " .. tostring(hl))
end)

check("non-string status maps to nil", function()
	local hl = core.done_highlight_for(42)
	assert(hl == nil, "expected nil, got " .. tostring(hl))
end)

check("unknown status maps to nil", function()
	local hl = core.done_highlight_for("archived")
	assert(hl == nil, "expected nil, got " .. tostring(hl))
end)

if failures == 0 then
	print("\nAll tests passed.")
else
	print(string.format("\n%d test(s) FAILED.", failures))
	os.exit(1)
end
