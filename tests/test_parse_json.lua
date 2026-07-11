-- Standalone tests for cue.core.parse_json
-- Run: luajit tests/test_parse_json.lua
--
-- Locks in the nvim 0.12 idiomatic JSON path: parse_json must delegate to
-- vim.json.decode (native Lua), NOT the legacy vim.fn.json_decode wrapper.
--
-- Mocks the minimal `vim` global so the real module can be required without
-- a running Neovim instance.

package.path = package.path .. ";./lua/?.lua"

-- Stub only what parse_json touches. The decode stub mimics vim.json.decode's
-- contract: returns the decoded value, or throws on invalid input.
local decode_calls = {}
vim = { -- luacheck: ignore (global stub)
	json = {
		decode = function(s)
			table.insert(decode_calls, s)
			if s == "INVALID" or s == "" then
				error("bad json")
			end
			return { decoded = s }
		end,
	},
}

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

-- Success path: valid JSON is passed through to vim.json.decode and returned.
check("returns decoded value for valid input", function()
	decode_calls = {}
	local result = core.parse_json('{"a":1}')
	assert(result ~= nil, "expected a table, got nil")
	assert(result.decoded == '{"a":1}', "decoded payload mismatch")
	-- The whole point of the 0.12 migration: vim.json.decode is used, not vim.fn.
	assert(decode_calls[1] == '{"a":1}', "vim.json.decode was not invoked with the input")
end)

-- Error path: a thrown decode becomes (nil, error) without propagating.
check("returns nil + error message on invalid input", function()
	local result, err = core.parse_json("INVALID")
	assert(result == nil, "expected nil result on parse failure")
	assert(err == "Failed to parse JSON", "unexpected error message: " .. tostring(err))
end)

check("returns nil + error message on empty input", function()
	local result, err = core.parse_json("")
	assert(result == nil, "expected nil result on empty input")
	assert(err == "Failed to parse JSON", "unexpected error message: " .. tostring(err))
end)

if failures == 0 then
	print("\nAll tests passed.")
else
	print(string.format("\n%d test(s) FAILED.", failures))
	os.exit(1)
end
