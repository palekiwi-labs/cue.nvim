-- Standalone tests for cue.core.task_tags
-- Run: luajit tests/test_task_tags.lua
--
-- task_tags is the pure helper behind the task-picker tag column and tag
-- search. It normalizes the optional `tag` frontmatter field into a list
-- of strings, accepting either a scalar or a list (mirroring how the
-- `branch:` field works), and reading `tags` as a lenient alias:
--   fm.tag = "nix"            -> { "nix" }
--   fm.tag = { "nix", "infra" } -> { "nix", "infra" }
--   no tag field              -> {}
--
-- Mocks the minimal `vim` global so the real module can be required without
-- a running Neovim instance (mirrors test_task_marker.lua).

package.path = package.path .. ";./lua/?.lua"

vim = { NIL = {} } -- luacheck: ignore (global stub)

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

-- Scalar tag becomes a single-element list.
check("scalar tag -> { tag }", function()
	local t = core.task_tags({ tag = "nix" })
	assert(#t == 1 and t[1] == "nix", "expected { nix }, got " .. tostring(t[1]))
end)

-- List tag preserves order and all elements.
check("list tag preserves order", function()
	local t = core.task_tags({ tag = { "nix", "infra", "editor" } })
	assert(#t == 3 and t[1] == "nix" and t[2] == "infra" and t[3] == "editor", "expected 3 ordered tags")
end)

-- `tags` alias is accepted when `tag` is absent.
check("tags alias accepted", function()
	local t = core.task_tags({ tags = { "rust", "cli" } })
	assert(#t == 2 and t[1] == "rust" and t[2] == "cli", "expected { rust, cli }")
end)

-- `tag` takes precedence over `tags`.
check("tag wins over tags alias", function()
	local t = core.task_tags({ tag = "primary", tags = { "other" } })
	assert(#t == 1 and t[1] == "primary", "expected tag to win")
end)

-- Missing frontmatter / missing field -> empty list.
check("nil frontmatter -> {}", function()
	local t = core.task_tags(nil)
	assert(type(t) == "table" and #t == 0, "expected empty list")
end)

check("vim.NIL frontmatter -> {}", function()
	local t = core.task_tags(vim.NIL)
	assert(type(t) == "table" and #t == 0, "expected empty list")
end)

check("no tag fields -> {}", function()
	local t = core.task_tags({ title = "Something" })
	assert(#t == 0, "expected empty list")
end)

check("vim.NIL tag value -> {}", function()
	local t = core.task_tags({ tag = vim.NIL })
	assert(#t == 0, "expected empty list")
end)

-- Empty strings are dropped, non-string entries are skipped.
check("empty string tag dropped", function()
	local t = core.task_tags({ tag = "" })
	assert(#t == 0, "expected empty list")
end)

check("empty strings in list dropped", function()
	local t = core.task_tags({ tag = { "nix", "" } })
	assert(#t == 1 and t[1] == "nix", "expected only nix")
end)

check("non-string list entries skipped", function()
	local t = core.task_tags({ tag = { "nix", 42, true } })
	assert(#t == 1 and t[1] == "nix", "expected only nix")
end)

-- Non-string, non-table scalar (e.g. YAML number) -> empty list.
check("number scalar -> {}", function()
	local t = core.task_tags({ tag = 42 })
	assert(#t == 0, "expected empty list")
end)

-- Result is always a fresh table (caller may mutate/sort safely).
check("returns fresh table", function()
	local fm = { tag = { "a" } }
	local t1 = core.task_tags(fm)
	t1[1] = "mutated"
	local t2 = core.task_tags(fm)
	assert(t2[1] == "a", "helper must not share state")
end)

if failures == 0 then
	print("\nAll tests passed.")
else
	print(string.format("\n%d test(s) FAILED.", failures))
	os.exit(1)
end
