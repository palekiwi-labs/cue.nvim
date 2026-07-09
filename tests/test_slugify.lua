-- Standalone tests for cue.core.slugify
-- Run: luajit tests/test_slugify.lua
--
-- Mocks the minimal `vim` global so the real module can be required without
-- a running Neovim instance.

package.path = package.path .. ";./lua/?.lua"

vim = {} -- luacheck: ignore (global stub)

local core = require("cue.core")

local failures = 0
local cases = {
  -- { input, expected }
  { "Hello World", "hello-world" },
  { "foo_bar baz", "foo-bar-baz" },
  { "nix/reseach-something", "nix-reseach-something" }, -- the bug from the todo
  { "a/b/c", "a-b-c" }, -- multiple slashes
  { "foo/ bar", "foo-bar" }, -- slash + space collapse to single dash
  { "trailing/", "trailing" }, -- trailing slash trimmed
  { "/leading", "leading" }, -- leading slash trimmed
  { "already-fine", "already-fine" },
  { "UPPER Case", "upper-case" },
  { "multi   spaces", "multi-spaces" },
  { "punct!@#word", "punctword" },
  { "", "" },
}

for _, case in ipairs(cases) do
  local input, expected = case[1], case[2]
  local got = core.slugify(input)
  if got ~= expected then
    failures = failures + 1
    print(string.format("FAIL: slugify(%q) = %q, expected %q", input, got, expected))
  else
    print(string.format("ok:   slugify(%q) = %q", input, got))
  end
end

-- nil passthrough
if core.slugify(nil) ~= nil then
  failures = failures + 1
  print("FAIL: slugify(nil) should return nil")
else
  print("ok:   slugify(nil) = nil")
end

if failures == 0 then
  print("\nAll tests passed.")
else
  print(string.format("\n%d test(s) FAILED.", failures))
  os.exit(1)
end
