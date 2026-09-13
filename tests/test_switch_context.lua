-- Standalone tests for cue.core.switch_context_argv
-- Run: luajit tests/test_switch_context.lua

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
    error(string.format("argv length mismatch: expected %d, got %d (%s)",
      #expected, #actual, table.concat(actual, " ")))
  end
  for i = 1, #expected do
    if actual[i] ~= expected[i] then
      error(string.format("argv mismatch at index %d: expected %q, got %q",
        i, expected[i], tostring(actual[i])))
    end
  end
end

-- The legacy `cue switch <slug>` command is gone: the central-store CLI
-- nests the branch association under `cue context`.
check("emits `cue context switch <slug>`", function()
  assert_list_equal(core.switch_context_argv("auth-login"),
    { "cue", "context", "switch", "auth-login" })
end)

check("never emits the legacy top-level `cue switch`", function()
  local argv = core.switch_context_argv("auth-login")
  assert(argv[2] == "context", "second argument must be `context`, got " .. tostring(argv[2]))
end)

check("trims surrounding whitespace from the slug", function()
  assert_list_equal(core.switch_context_argv("  auth-login  "),
    { "cue", "context", "switch", "auth-login" })
end)

-- -C and --store precede the positional slug, mirroring active_context_argv.
check("forwards dir as -C before the slug", function()
  assert_list_equal(core.switch_context_argv("auth-login", { dir = "/repo" }),
    { "cue", "context", "switch", "-C", "/repo", "auth-login" })
end)

check("forwards store as --store before the slug", function()
  assert_list_equal(core.switch_context_argv("auth-login", { store = "/store" }),
    { "cue", "context", "switch", "--store", "/store", "auth-login" })
end)

check("forwards dir and store together", function()
  assert_list_equal(core.switch_context_argv("auth-login", { dir = "/repo", store = "/store" }),
    { "cue", "context", "switch", "-C", "/repo", "--store", "/store", "auth-login" })
end)

-- A missing slug is a caller error: `cue context switch` requires one, and
-- there is no "master" fallback context to substitute.
check("returns nil for a nil slug", function()
  assert(core.switch_context_argv(nil) == nil, "expected nil for nil slug")
end)

check("returns nil for a blank slug", function()
  assert(core.switch_context_argv("   ") == nil, "expected nil for blank slug")
end)

check("returns nil for a non-string slug", function()
  assert(core.switch_context_argv(42) == nil, "expected nil for non-string slug")
end)

if failures == 0 then
  print("\nAll tests passed.")
else
  print(string.format("\n%d test(s) FAILED.", failures))
  os.exit(1)
end
