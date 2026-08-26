-- Standalone tests for cue.core.done_highlight_for
-- Run: luajit tests/test_done_highlight.lua
--
-- done_highlight_for is the pure helper behind the artifact-picker row
-- highlight for finished artifacts. Given a frontmatter status string it
-- returns the highlight group name, gated by the dim_done flag:
--
--   dim_done = true (default; mixed pickers like <C-s>):
--     closed   -> "CueStatusDone"     (grey + strikethrough)
--     complete -> "CueStatusComplete" (grey, no strikethrough)
--
--   dim_done = false (pickers listing ONLY done cards, e.g. <space>ec):
--     closed   -> "CueStatusClosed"   (strikethrough, normal colors)
--     complete -> nil                 (normal colors, no override)
--
--   other statuses -> nil (no override) regardless of the flag.
--
-- Grey is a scanning aid for MIXED lists; a picker where every card is
-- done does not need it (operator 2026-08-26).
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

-- dim_done defaults to true (mixed pickers keep the grey scanning aid)

check("closed (dim, default) maps to CueStatusDone", function()
	local hl = core.done_highlight_for("closed")
	assert(hl == "CueStatusDone", "expected CueStatusDone, got " .. tostring(hl))
end)

check("complete (dim, default) maps to CueStatusComplete", function()
	local hl = core.done_highlight_for("complete")
	assert(hl == "CueStatusComplete", "expected CueStatusComplete, got " .. tostring(hl))
end)

check("closed (dim, explicit) maps to CueStatusDone", function()
	local hl = core.done_highlight_for("closed", true)
	assert(hl == "CueStatusDone", "expected CueStatusDone, got " .. tostring(hl))
end)

check("complete (dim, explicit) maps to CueStatusComplete", function()
	local hl = core.done_highlight_for("complete", true)
	assert(hl == "CueStatusComplete", "expected CueStatusComplete, got " .. tostring(hl))
end)

-- dim_done = false: done-only pickers render normal colors

check("closed (no dim) maps to CueStatusClosed (strike only)", function()
	local hl = core.done_highlight_for("closed", false)
	assert(hl == "CueStatusClosed", "expected CueStatusClosed, got " .. tostring(hl))
end)

check("complete (no dim) maps to nil (normal colors)", function()
	local hl = core.done_highlight_for("complete", false)
	assert(hl == nil, "expected nil, got " .. tostring(hl))
end)

-- non-done statuses never override, regardless of the flag

check("open maps to nil", function()
	assert(core.done_highlight_for("open") == nil, "expected nil")
	assert(core.done_highlight_for("open", false) == nil, "expected nil (no dim)")
end)

check("in-progress maps to nil", function()
	assert(core.done_highlight_for("in-progress") == nil, "expected nil")
	assert(core.done_highlight_for("in-progress", false) == nil, "expected nil (no dim)")
end)

-- Status match is case-insensitive (frontmatter may use "Closed").
check("match is case-insensitive", function()
	local hl = core.done_highlight_for("Closed")
	assert(hl == "CueStatusDone", "expected CueStatusDone, got " .. tostring(hl))
	local hl2 = core.done_highlight_for("Closed", false)
	assert(hl2 == "CueStatusClosed", "expected CueStatusClosed, got " .. tostring(hl2))
end)

check("Complete (capitalized, no dim) maps to nil", function()
	local hl = core.done_highlight_for("Complete", false)
	assert(hl == nil, "expected nil, got " .. tostring(hl))
end)

check("nil status maps to nil", function()
	assert(core.done_highlight_for(nil) == nil, "expected nil")
	assert(core.done_highlight_for(nil, false) == nil, "expected nil (no dim)")
end)

check("non-string status maps to nil", function()
	assert(core.done_highlight_for(42) == nil, "expected nil")
	assert(core.done_highlight_for(42, false) == nil, "expected nil (no dim)")
end)

check("unknown status maps to nil", function()
	assert(core.done_highlight_for("archived") == nil, "expected nil")
	assert(core.done_highlight_for("archived", false) == nil, "expected nil (no dim)")
end)

if failures == 0 then
	print("\nAll tests passed.")
else
	print(string.format("\n%d test(s) FAILED.", failures))
	os.exit(1)
end
