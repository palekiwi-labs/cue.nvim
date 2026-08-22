-- Standalone tests for cue.core.kind_badge
-- Run: luajit tests/test_kind_badge.lua
--
-- kind_badge is the pure helper behind the task-picker kind column: it maps
-- a frontmatter kind to a 3-char uppercase badge (config.KIND_ABBREV).
--   known kind   -> mapped badge (RES, DES, BLD, REV, COR, LRN)
--   missing kind -> "TSK"
--   unknown kind -> first 3 chars, uppercased (never overflows the column)
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

-- Known kinds map to their canonical abbreviations.
check("research -> RES", function()
	local b = core.kind_badge("research")
	assert(b == "RES", "expected RES, got " .. tostring(b))
end)

check("design -> DES", function()
	local b = core.kind_badge("design")
	assert(b == "DES", "expected DES, got " .. tostring(b))
end)

check("build -> BLD", function()
	local b = core.kind_badge("build")
	assert(b == "BLD", "expected BLD, got " .. tostring(b))
end)

check("review -> REV", function()
	local b = core.kind_badge("review")
	assert(b == "REV", "expected REV, got " .. tostring(b))
end)

check("coord -> COR", function()
	local b = core.kind_badge("coord")
	assert(b == "COR", "expected COR, got " .. tostring(b))
end)

check("learn -> LRN", function()
	local b = core.kind_badge("learn")
	assert(b == "LRN", "expected LRN, got " .. tostring(b))
end)

-- Match is case-insensitive (frontmatter may use "Research").
check("case-insensitive match", function()
	local b = core.kind_badge("Research")
	assert(b == "RES", "expected RES, got " .. tostring(b))
end)

-- Missing/empty kind falls back to the generic task badge.
check("nil kind -> TSK", function()
	local b = core.kind_badge(nil)
	assert(b == "TSK", "expected TSK, got " .. tostring(b))
end)

check("empty kind -> TSK", function()
	local b = core.kind_badge("")
	assert(b == "TSK", "expected TSK, got " .. tostring(b))
end)

-- Unknown kinds abbreviate to first 3 uppercase chars.
check("unknown kind abbreviates", function()
	local b = core.kind_badge("spike")
	assert(b == "SPI", "expected SPI, got " .. tostring(b))
end)

check("short unknown kind uppercases", function()
	local b = core.kind_badge("qa")
	assert(b == "QA", "expected QA, got " .. tostring(b))
end)

-- Every badge is exactly <= 3 chars so the fixed-width column never overflows.
check("badges never exceed 3 chars", function()
	for _, kind in ipairs({ "research", "design", "build", "review", "coord", nil, "spike" }) do
		local b = core.kind_badge(kind)
		assert(#b <= 3, "badge too wide for " .. tostring(kind) .. ": " .. b)
	end
end)

if failures == 0 then
	print("\nAll tests passed.")
else
	print(string.format("\n%d test(s) FAILED.", failures))
	os.exit(1)
end
