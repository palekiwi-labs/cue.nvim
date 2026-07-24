-- Standalone tests for cue.core.scope_set
-- Run: luajit tests/test_list_scopes.lua

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
  if #actual ~= #expected then
    error(string.format("list length mismatch: expected %d, got %d", #expected, #actual))
  end
  for i = 1, #expected do
    if actual[i] ~= expected[i] then
      error(string.format("list mismatch at index %d: expected %q, got %q", i, expected[i], actual[i]))
    end
  end
end

check("scope_set({}) returns { 'master' }", function()
  assert_list_equal(core.scope_set({}), { "master" })
end)

check("scope_set with slugs returns sorted slugs plus master", function()
  assert_list_equal(core.scope_set({ "fix-scope-selection.md", "auth-login.md" }), { "auth-login", "fix-scope-selection", "master" })
end)

check("scope_set dedups slugs", function()
  assert_list_equal(core.scope_set({ "foo.md", "foo.md" }), { "foo", "master" })
end)

check("master task file does not duplicate", function()
  assert_list_equal(core.scope_set({ "master.md" }), { "master" })
end)

check("nil-safe", function()
  assert_list_equal(core.scope_set(nil), { "master" })
end)

if failures == 0 then
	print("\nAll tests passed.")
else
	print(string.format("\n%d test(s) FAILED.", failures))
	os.exit(1)
end
