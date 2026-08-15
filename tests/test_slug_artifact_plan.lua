-- Standalone tests for cue.core.slug_artifact_plan
-- Run: luajit tests/test_slug_artifact_plan.lua
--
-- slug_artifact_plan is the pure, vim-free helper behind the unified
-- slug-prompt creation flow (task/note/todo). It encodes the type-intrinsic
-- root policy (task/note = root/flat, todo = pinned) and the frontmatter
-- defaults, returning a { filename, opts } plan or nil when the slug
-- normalises to empty.
--
-- Mocks the minimal `vim` global so the real module can be required without
-- a running Neovim instance.

package.path = package.path .. ";./lua/?.lua"

vim = {} -- luacheck: ignore (global stub)

local core = require("cue.core")
local config = require("cue.config")

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

-- task -> root=true, scope=master, task frontmatter defaults
check("task plan places artifact at root with master scope", function()
	local plan = core.slug_artifact_plan("task", "auth-login", "master")
	assert(plan ~= nil, "expected a plan, got nil")
	assert(plan.filename == "auth-login.md", "filename=" .. tostring(plan.filename))
	assert(plan.opts.category == "task", "category=" .. tostring(plan.opts.category))
	assert(plan.opts.task == "master", "task=" .. tostring(plan.opts.task))
	assert(plan.opts.root == true, "root should be true for task")
	assert(plan.opts.frontmatter.status == "open", "frontmatter status")
	assert(plan.opts.frontmatter.priority == "normal", "frontmatter priority")
	assert(plan.opts.frontmatter.kind == "build", "frontmatter default kind should be build")
	assert(plan.opts.frontmatter.title == "Auth Login",
		"title derived from slug=" .. tostring(plan.opts.frontmatter.title))
end)

check("task plan accepts extra_fm for kind and parent", function()
	local plan = core.slug_artifact_plan("task", "auth-login", "master", {
		kind = "design",
		parent = "refine-cue-skills",
	})
	assert(plan ~= nil, "expected a plan, got nil")
	assert(plan.opts.frontmatter.kind == "design", "kind=" .. tostring(plan.opts.frontmatter.kind))
	assert(plan.opts.frontmatter.parent == "refine-cue-skills", "parent=" .. tostring(plan.opts.frontmatter.parent))
end)

-- note -> root=true, note has no priority default
check("note plan places artifact at root", function()
	local plan = core.slug_artifact_plan("note", "my-idea", "master")
	assert(plan.opts.root == true, "note should be root")
	assert(plan.filename == "my-idea.md", "filename=" .. tostring(plan.filename))
	assert(plan.opts.frontmatter.status == "open", "frontmatter status")
	assert(plan.opts.frontmatter.priority == nil, "note has no priority default")
	assert(plan.opts.frontmatter.title == "My Idea", "title derived from slug=" .. tostring(plan.opts.frontmatter.title))
end)

-- todo -> root=false (pinned / point-in-time)
check("todo plan is pinned (root=false)", function()
	local plan = core.slug_artifact_plan("todo", "refactor", "master")
	assert(plan.opts.root == false, "todo should NOT be root")
	assert(plan.filename == "refactor.md", "filename=" .. tostring(plan.filename))
	assert(plan.opts.frontmatter.title == "Refactor", "title derived from slug=" .. tostring(plan.opts.frontmatter.title))
end)

-- slug normalisation: lowercase, spaces/punct stripped, hyphenated
check("slug is normalised (lowercase, hyphenated)", function()
	local plan = core.slug_artifact_plan("task", "Hello World!", "master")
	assert(plan.filename == "hello-world.md", "filename=" .. tostring(plan.filename))
end)

-- title is derived from the RAW slug (pre-slugify) so acronyms survive
check("title preserves uppercase acronyms typed in the raw slug", function()
	local plan = core.slug_artifact_plan("note", "WSS-migration", "master")
	assert(plan.filename == "wss-migration.md", "filename slugified=" .. tostring(plan.filename))
	assert(plan.opts.frontmatter.title == "WSS Migration", "title=" .. tostring(plan.opts.frontmatter.title))
end)

-- Regression guard for the add_with_slug -> slug_artifact_plan hand-off
-- (core.lua:567). The caller MUST forward the RAW slug; passing an already
-- slugified value loses acronym casing. This pins that contract so a future
-- refactor cannot silently re-break the production flow.
check("normalised slug does NOT preserve acronyms (caller must pass raw)", function()
	local plan = core.slug_artifact_plan("note", core.slugify("WSS-migration"), "master")
	assert(plan.opts.frontmatter.title == "Wss Migration",
		"normalised slug should lose acronym, got=" .. tostring(plan.opts.frontmatter.title))
end)

-- filename always ends with exactly one .md suffix
check("filename always ends with exactly one .md", function()
	local plan = core.slug_artifact_plan("note", "clean", "master")
	assert(plan.filename == "clean.md", "filename=" .. tostring(plan.filename))
	assert(not plan.filename:match("%.md%.md$"), "double .md suffix")
end)

-- digit-only slug: title is OMITTED (would round-trip as a YAML number and
-- crash the picker, which expects a string display_name). See core.lua guard.
check("digit-only slug omits the title frontmatter", function()
	local plan = core.slug_artifact_plan("note", "2026", "master")
	assert(plan.filename == "2026.md", "filename=" .. tostring(plan.filename))
	assert(plan.opts.frontmatter.title == nil,
		"digit-only title should be omitted, got=" .. tostring(plan.opts.frontmatter.title))
end)

-- empty slug -> nil
check("empty slug returns nil", function()
	assert(core.slug_artifact_plan("task", "", "master") == nil, "expected nil for empty slug")
end)

-- whitespace-only slug -> nil
check("whitespace-only slug returns nil", function()
	assert(core.slug_artifact_plan("task", "   ", "master") == nil, "expected nil for whitespace slug")
end)

-- slug that normalises to empty (punctuation only) -> nil
check("slug that normalises empty returns nil", function()
	assert(core.slug_artifact_plan("task", "!@#$", "master") == nil, "expected nil for punct-only slug")
end)

-- SLUG_ROOT policy is data-driven and matches the cue skill spec
check("SLUG_ROOT encodes task/note=root, todo=pinned", function()
	assert(config.SLUG_ROOT.task == true, "task should be root")
	assert(config.SLUG_ROOT.note == true, "note should be root")
	assert(config.SLUG_ROOT.todo == false, "todo should be pinned")
end)

if failures == 0 then
	print("\nAll tests passed.")
else
	print(string.format("\n%d test(s) FAILED.", failures))
	os.exit(1)
end
