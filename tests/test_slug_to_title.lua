-- Standalone tests for cue.core.slug_to_title
-- Run: luajit tests/test_slug_to_title.lua
--
-- slug_to_title converts a slug (or raw slug-ish input) into a human-readable
-- title: words are capitalised, separators/punctuation dropped, and short
-- all-caps tokens (2-4 uppercase letters, no digits) preserved as acronyms.
--
-- Kept free of vim.* calls so it runs under luajit with a `vim = {}` stub.

package.path = package.path .. ";./lua/?.lua"

vim = {} -- luacheck: ignore (global stub)

local core = require("cue.core")

local failures = 0
local cases = {
  -- { input, expected }
  { "auth-login",            "Auth Login" },      -- basic kebab-case
  { "Auth-Login",            "Auth Login" },      -- mixed case normalised
  { "add_slug_to_title",     "Add Slug To Title" }, -- underscores
  { "fix-issue-123",         "Fix Issue 123" },   -- digits kept, not acronym
  { "api-v2-refactor",       "Api V2 Refactor" }, -- alphanumeric token
  { "already-fine",          "Already Fine" },
  { "multi   spaces",        "Multi Spaces" },    -- whitespace collapse
  { "Hello World!",          "Hello World" },     -- punctuation dropped
  { "a/b/c",                 "A B C" },           -- slashes as separators
  -- acronym preservation (only when typed uppercase, 2-4 letters, no digits)
  { "WSS-migration",         "WSS Migration" },   -- 3-letter acronym kept
  { "PR-review",             "PR Review" },       -- 2-letter acronym kept
  { "HTML-parser",           "HTML Parser" },     -- 4-letter acronym kept
  { "UPPER-case",            "Upper Case" },      -- 5 caps -> NOT acronym
  { "don't-break-things",    "Don't Break Things" }, -- apostrophe preserved
  -- punct/whitespace-only inputs collapse to empty
  { "!@#$",                  "" },
  { "   ",                   "" },
  { "",                      "" },
}

for _, case in ipairs(cases) do
  local input, expected = case[1], case[2]
  local got = core.slug_to_title(input)
  if got ~= expected then
    failures = failures + 1
    print(string.format("FAIL: slug_to_title(%q) = %q, expected %q", input, got, expected))
  else
    print(string.format("ok:   slug_to_title(%q) = %q", input, got))
  end
end

-- nil passthrough -> empty string
if core.slug_to_title(nil) ~= "" then
  failures = failures + 1
  print(string.format("FAIL: slug_to_title(nil) = %q, expected %q", tostring(core.slug_to_title(nil)), ""))
else
  print("ok:   slug_to_title(nil) = \"\"")
end

if failures == 0 then
  print("\nAll tests passed.")
else
  print(string.format("\n%d test(s) FAILED.", failures))
  os.exit(1)
end
