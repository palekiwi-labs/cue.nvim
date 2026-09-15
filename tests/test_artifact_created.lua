-- Standalone tests for the artifact creation-time helpers
-- Run: luajit tests/test_artifact_created.lua
--
-- Covers the creation-time column of the context artifact picker:
--
--   core.artifact_created_at(artifact)
--     Unix seconds for a row, or nil when the row carries no usable stamp.
--     Markdown artifacts get it from `frontmatter.created_at`. `tmp`
--     artifacts have NO frontmatter at all -- `cue add --type tmp` rejects
--     metadata -- so their stamp is parsed out of the group directory cue
--     names them with: `<nanosecond timestamp>-<short commit hash>`. `bin`
--     artifacts have neither, and report nothing.
--
--   core.artifact_created_age(artifact, now)
--     The parsed stamp as a compact relative age (`now`, `12m`, `3h`,
--     `6d`, `1y`), or an em dash when the row has no stamp. `now` is
--     passed in, not read from the clock, so the picker can sample once
--     per refresh and the formatting stays deterministic under test.
--
-- The parser is deliberately strict: the filesystem mtime is NEVER
-- consulted, so a directory that merely looks numeric must fail the check
-- and fall back to the dash rather than invent a plausible date.

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

-- The real wire row for a grouped tmp artifact, copied from
-- `cue list --context ... --json --frontmatter --type tmp`: no frontmatter
-- key, and `name` carries the group directory as a path prefix.
local REAL_TMP_NAME = "1789366283853051953-d8dc048d49/review-comments-delta-1789366283.json"
local REAL_TMP_SECONDS = 1789366283

local function tmp(name)
	return {
		type = "tmp",
		name = name,
		path = "/home/pl/cue/spabreaks/wss/review-sb-10548-consolidate-gcloud-credentials/tmp/" .. name,
		context = "review-sb-10548-consolidate-gcloud-credentials",
	}
end

local function md(cue_type, created_at)
	return {
		type = cue_type,
		name = "index.md",
		path = "/store/scope/demo/" .. cue_type .. "/index.md",
		frontmatter = { created_at = created_at },
	}
end

-- ─── frontmatter stamps ───────────────────────────────────────────────

check("created_at reads the frontmatter stamp", function()
	assert(core.artifact_created_at(md("task", 1789364730)) == 1789364730, "frontmatter created_at should be used")
end)

check("created_at rejects unusable frontmatter stamps", function()
	local cases = {
		{ name = "missing", value = nil },
		{ name = "vim.NIL", value = vim.NIL },
		{ name = "string", value = "1789364730" },
		{ name = "negative", value = -1 },
		{ name = "infinite", value = math.huge },
		{ name = "nan", value = 0 / 0 },
	}
	for _, c in ipairs(cases) do
		assert(core.artifact_created_at(md("spec", c.value)) == nil, c.name .. " created_at must not resolve")
	end
end)

check("created_at survives missing or malformed frontmatter", function()
	local a = md("note", 1789364730)
	a.frontmatter = nil
	assert(core.artifact_created_at(a) == nil, "nil frontmatter yields no stamp")
	a.frontmatter = vim.NIL
	assert(core.artifact_created_at(a) == nil, "vim.NIL frontmatter yields no stamp")
	a.frontmatter = "bad"
	assert(core.artifact_created_at(a) == nil, "non-table frontmatter yields no stamp")
	assert(core.artifact_created_at(nil) == nil, "nil artifact yields no stamp")
	assert(core.artifact_created_at("bad") == nil, "non-table artifact yields no stamp")
end)

-- ─── tmp group directories ────────────────────────────────────────────

check("created_at parses the real grouped tmp row", function()
	local got = core.artifact_created_at(tmp(REAL_TMP_NAME))
	assert(got == REAL_TMP_SECONDS, string.format("expected %d, got %s", REAL_TMP_SECONDS, tostring(got)))
end)

check("created_at drops the nanosecond remainder without float error", function()
	-- 1789366283853051953 is well past 2^53, so tonumber() on the whole
	-- stamp cannot represent it exactly. The seconds must come from the
	-- leading ten digits, not from a division.
	local got = core.artifact_created_at(tmp("1789366283999999999-d8dc048d49/x.json"))
	assert(got == REAL_TMP_SECONDS, "the sub-second digits must be truncated, not rounded")
	assert(math.floor(got) == got, "seconds must be a whole number")
end)

check("created_at accepts any short commit hash length", function()
	assert(core.artifact_created_at(tmp("1789366283853051953-abc123/x.json")) == REAL_TMP_SECONDS)
	assert(core.artifact_created_at(tmp("1789366283853051953-d8dc048d49ff/x.json")) == REAL_TMP_SECONDS)
end)

check("created_at reads a nested file inside a tmp group", function()
	assert(core.artifact_created_at(tmp("1789366283853051953-d8dc048d49/acuity/dump.json")) == REAL_TMP_SECONDS)
end)

check("created_at reports nothing for a legacy flat tmp artifact", function()
	-- Pre-grouping tmp files sit straight in tmp/ and carry no stamp
	-- anywhere. The mtime is NOT a fallback.
	assert(core.artifact_created_at(tmp("sb-10548-consolidate-gcloud-credentials.diff")) == nil)
	assert(core.artifact_created_at(tmp("data-model-spike.diff")) == nil)
end)

check("created_at rejects malformed tmp group directories", function()
	local bad = {
		"images/screenshot.png", -- a plain directory, not a group
		"acuity-phase-6b/acuity/events.json", -- named group, no stamp
		"1789366283853051953/x.json", -- no commit hash
		"1789366283853051953-/x.json", -- empty commit hash
		"-d8dc048d49/x.json", -- no stamp
		"178936628385305195-d8dc048d49/x.json", -- 18 digits: wrong unit
		"17893662838530519533-d8dc048d49/x.json", -- 20 digits: wrong unit
		"1789366283-d8dc048d49/x.json", -- seconds, not nanoseconds
		"0789366283853051953-d8dc048d49/x.json", -- leading zero
		"1789366283853051953-zzzzzz/x.json", -- non-hex commit hash
		"1789366283853051953_d8dc048d49/x.json", -- wrong separator
		"1789366283853051953-d8dc048d49 /x.json", -- trailing space
		" 1789366283853051953-d8dc048d49/x.json", -- leading space
	}
	for _, name in ipairs(bad) do
		assert(core.artifact_created_at(tmp(name)) == nil, "must not parse: " .. name)
	end
end)

check("created_at parses group directories for tmp rows only", function()
	-- Only `tmp` is laid out as <group>/<file>; a markdown artifact nests
	-- under a caller-chosen path, so a numeric-looking directory there is a
	-- real directory name and never a timestamp.
	for _, cue_type in ipairs({ "task", "spec", "plan", "note", "trace", "bin" }) do
		local a = tmp(REAL_TMP_NAME)
		a.type = cue_type
		assert(core.artifact_created_at(a) == nil, cue_type .. " must not parse a group directory")
	end
end)

check("created_at prefers frontmatter over the group directory", function()
	local a = tmp(REAL_TMP_NAME)
	a.frontmatter = { created_at = 1000 }
	assert(core.artifact_created_at(a) == 1000, "an explicit stamp wins over the derived one")
end)

check("created_at handles a tmp row without a name", function()
	local a = tmp(REAL_TMP_NAME)
	a.name = nil
	assert(core.artifact_created_at(a) == nil, "a name-less tmp row yields no stamp")
	a.name = vim.NIL
	assert(core.artifact_created_at(a) == nil, "a vim.NIL name yields no stamp")
	a.name = 42
	assert(core.artifact_created_at(a) == nil, "a non-string name yields no stamp")
end)

-- ─── display formatting ───────────────────────────────────────────────

check("created age renders the compact relative style", function()
	local now = REAL_TMP_SECONDS + 7200
	assert(core.artifact_created_age(md("task", REAL_TMP_SECONDS), now) == "2h", "frontmatter stamp should format")
	assert(core.artifact_created_age(tmp(REAL_TMP_NAME), now) == "2h", "tmp group stamp should format the same")
	assert(core.artifact_created_age(md("task", REAL_TMP_SECONDS), REAL_TMP_SECONDS + 30) == "now")
	assert(core.artifact_created_age(md("task", REAL_TMP_SECONDS), REAL_TMP_SECONDS + 600) == "10m")
	assert(core.artifact_created_age(md("task", REAL_TMP_SECONDS), REAL_TMP_SECONDS + 86400 * 6) == "6d")
	assert(core.artifact_created_age(md("task", REAL_TMP_SECONDS), REAL_TMP_SECONDS + 86400 * 400) == "1y")
	assert(#"364d" == 4, "the widest relative age is four cells, which sizes the column")
end)

check("created age shares the context browser's formatter", function()
	-- One relative-time style across both pickers: the artifact column and
	-- the context browser's activity column call the same helper, so they
	-- cannot drift apart.
	local now = REAL_TMP_SECONDS + 86400 * 3
	assert(core.artifact_created_age(md("task", REAL_TMP_SECONDS), now) == core.relative_age(REAL_TMP_SECONDS, now))
	assert(core.context_activity(REAL_TMP_SECONDS, now) == core.relative_age(REAL_TMP_SECONDS, now))
end)

check("created age is an em dash when there is no stamp", function()
	local now = REAL_TMP_SECONDS + 7200
	assert(core.artifact_created_age(tmp("legacy.diff"), now) == "—", "legacy tmp shows a dash")
	assert(core.artifact_created_age({ type = "bin", name = "run.sh" }, now) == "—", "bin shows a dash")
	assert(core.artifact_created_age(md("note", nil), now) == "—", "a missing stamp shows a dash")
	assert(core.artifact_created_age(nil, now) == "—", "a nil row shows a dash")
end)

if failures == 0 then
	print("\nAll tests passed.")
else
	print(string.format("\n%d test(s) FAILED.", failures))
	os.exit(1)
end
