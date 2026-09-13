-- Standalone tests for cue.core.list_contexts_argv
-- Run: luajit tests/test_list_contexts.lua

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

local function assert_list_equal(actual, expected)
	if actual == nil then
		error("expected a list, got nil")
	end
	if #actual ~= #expected then
		error(
			string.format(
				"argv length mismatch: expected %d, got %d (%s)",
				#expected,
				#actual,
				table.concat(actual, " ")
			)
		)
	end
	for i = 1, #expected do
		if actual[i] ~= expected[i] then
			error(string.format("argv mismatch at index %d: expected %q, got %q", i, expected[i], tostring(actual[i])))
		end
	end
end

check("emits `cue context list` by default", function()
	assert_list_equal(core.list_contexts_argv(), { "cue", "context", "list" })
end)

check("forwards dir as -C", function()
	assert_list_equal(core.list_contexts_argv({ dir = "/my/repo" }), { "cue", "context", "list", "-C", "/my/repo" })
end)

check("forwards store as --store", function()
	assert_list_equal(
		core.list_contexts_argv({ store = "/my/store" }),
		{ "cue", "context", "list", "--store", "/my/store" }
	)
end)

check("forwards dir and store together", function()
	assert_list_equal(
		core.list_contexts_argv({ dir = "/my/repo", store = "/my/store" }),
		{ "cue", "context", "list", "-C", "/my/repo", "--store", "/my/store" }
	)
end)

if failures == 0 then
	print("\nAll tests passed.")
else
	print(string.format("\n%d test(s) FAILED.", failures))
	os.exit(1)
end
