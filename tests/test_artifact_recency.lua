package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua"
vim = { NIL = {} } -- luacheck: ignore
local core = require("cue.core")
local function row(name, status, created, kind)
	return {
		type = kind or "task",
		name = name,
		path = "/" .. name,
		frontmatter = { status = status, created_at = created },
	}
end
local rows = core.context_artifacts_view({
	row("done-old", "complete", 10),
	row("closed-new", "closed", 900),
	row("open-old", "open", 20),
	row("open-new", "in-progress", 100),
	row("unknown", nil, nil),
	row("bad", "open", "bad"),
	row("spec", "open", 1000, "spec"),
	row("done-undated", "complete", nil),
})
local expected = { "open-new", "open-old", "bad", "unknown", "closed-new", "done-old", "done-undated", "spec" }
for i, name in ipairs(expected) do
	assert(rows[i].name == name, rows[i].name .. " ~= " .. name)
end
assert(core.artifact_finished(row("x", "complete")))
assert(core.artifact_finished(row("x", "closed")))
assert(not core.artifact_finished(row("x", "open")))
assert(not core.artifact_finished({ frontmatter = vim.NIL }))
assert(not core.artifact_finished({ frontmatter = "bad" }))
assert(not core.context_artifact_less(rows[1], rows[1]))
print("artifact recency tests passed")
