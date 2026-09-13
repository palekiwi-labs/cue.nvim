package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua"
vim = { NIL = {} } -- luacheck: ignore
local activity = require("cue.core").context_activity
local now = 1800000000
assert(activity(nil, now) == "—")
assert(activity(vim.NIL, now) == "—")
assert(activity("yesterday", now) == "—")
assert(activity(0 / 0, now) == "—")
assert(activity(math.huge, now) == "—")
assert(activity(-1, now) == "—")
assert(activity(now + 60, now) == "now")
assert(activity(now, now) == "now")
assert(activity(now - 59, now) == "now")
assert(activity(now - 60, now) == "1m")
assert(activity(now - 3599, now) == "59m")
assert(activity(now - 3600, now) == "1h")
assert(activity(now - 86399, now) == "23h")
assert(activity(now - 86400, now) == "1d")
assert(activity(now - 86400 * 364, now) == "364d")
assert(activity(now - 86400 * 365, now) == "1y")
print("context activity tests passed")
