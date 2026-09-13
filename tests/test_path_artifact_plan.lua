-- Standalone tests for cue.core.path_artifact_plan
-- Run: luajit tests/test_path_artifact_plan.lua
--
-- path_artifact_plan is the pure, vim-free helper behind the path-prompt
-- creation flow (spec/trace). Unlike slug_artifact_plan it uses the entered
-- path VERBATIM: no slugification and no forced extension, so nested paths
-- (spec/index.md, note/ideas/<slug>.md) and non-markdown types survive.
-- Frontmatter defaults apply only to markdown (.md) paths because `cue add`
-- prepends YAML frontmatter unconditionally, which would corrupt e.g. a
-- JSON file.
--
-- Root placement is gone: every markdown artifact is a named file at
-- <type>/<name>.md, so config.PATH_ROOT no longer exists.
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

local function count_keys(t)
	local n = 0
	for _ in pairs(t) do n = n + 1 end
	return n
end

-- trace: json path kept verbatim, no frontmatter
check("trace json path is preserved with no frontmatter", function()
	local plan = core.path_artifact_plan("trace", "crash-log.json", "master")
	assert(plan ~= nil, "expected a plan, got nil")
	assert(plan.filename == "crash-log.json",
		"filename=" .. tostring(plan.filename))
	assert(plan.opts.category == "trace", "category=" .. tostring(plan.opts.category))
	assert(plan.opts.task == "master", "task=" .. tostring(plan.opts.task))
	assert(count_keys(plan.opts.frontmatter) == 0,
		"non-markdown path must carry no frontmatter, got=" .. tostring(count_keys(plan.opts.frontmatter)))
end)

-- Root placement is deleted, not defaulted: the key must be absent entirely
-- so a stale `opts.root` reader fails loudly rather than reading false.
check("plan emits no root key at all", function()
	local trace = core.path_artifact_plan("trace", "handoff.md", "master")
	assert(trace.opts.root == nil, "root key should be gone, got=" .. tostring(trace.opts.root))
	local spec = core.path_artifact_plan("spec", "index.md", "master")
	assert(spec.opts.root == nil, "root key should be gone, got=" .. tostring(spec.opts.root))
end)

-- trace: extension-less and unusual extensions are equally verbatim
check("trace path with no extension is preserved", function()
	local plan = core.path_artifact_plan("trace", "raw-output", "my-task")
	assert(plan.filename == "raw-output", "filename=" .. tostring(plan.filename))
end)

check("trace txt path is preserved", function()
	local plan = core.path_artifact_plan("trace", "debug.txt", "master")
	assert(plan.filename == "debug.txt", "filename=" .. tostring(plan.filename))
end)

-- nested relative paths stay verbatim (cue add owns path validation)
check("relative directory components are preserved", function()
	local plan = core.path_artifact_plan("trace", "logs/run-42.json", "master")
	assert(plan.filename == "logs/run-42.json", "filename=" .. tostring(plan.filename))
end)

-- markdown paths DO get the type frontmatter defaults (plan used as a type
-- with defaults that can exercise the .md branch here)
check("markdown path gets TYPE_DEFAULTS frontmatter", function()
	local plan = core.path_artifact_plan("plan", "rollout.md", "master")
	assert(plan.opts.frontmatter.status == "open", "frontmatter status")
	assert(plan.opts.frontmatter.priority == "normal", "frontmatter priority")
end)

-- ...while the same type with a non-markdown extension gets none
check("non-markdown path skips TYPE_DEFAULTS frontmatter", function()
	local plan = core.path_artifact_plan("plan", "rollout.json", "master")
	assert(count_keys(plan.opts.frontmatter) == 0,
		"json path must carry no frontmatter, got=" .. tostring(count_keys(plan.opts.frontmatter)))
end)

-- spec: nested path preserved verbatim, which is the whole point of the
-- path flow now that root placement is gone
check("spec path is preserved verbatim", function()
	local plan = core.path_artifact_plan("spec", "index.md", "master")
	assert(plan.filename == "index.md", "filename=" .. tostring(plan.filename))
	assert(plan.opts.category == "spec", "category=" .. tostring(plan.opts.category))
end)

-- a type with no TYPE_DEFAULTS entry simply carries no frontmatter
check("type without defaults carries no frontmatter", function()
	local plan = core.path_artifact_plan("bin", "blob.json", "master")
	assert(count_keys(plan.opts.frontmatter) == 0,
		"bin has no defaults, got=" .. tostring(count_keys(plan.opts.frontmatter)))
end)

-- empty path -> nil
check("empty path returns nil", function()
	assert(core.path_artifact_plan("trace", "", "master") == nil,
		"expected nil for empty path")
end)

-- whitespace-only path -> nil
check("whitespace-only path returns nil", function()
	assert(core.path_artifact_plan("trace", "   ", "master") == nil,
		"expected nil for whitespace path")
end)

-- nil path -> nil
check("nil path returns nil", function()
	assert(core.path_artifact_plan("trace", nil, "master") == nil,
		"expected nil for nil path")
end)

-- Root placement is deleted outright, table included.
check("PATH_ROOT no longer exists", function()
	assert(config.PATH_ROOT == nil, "PATH_ROOT should be deleted")
	assert(config.SLUG_ROOT == nil, "SLUG_ROOT should be deleted")
end)

-- `todo` is removed from the model; it must carry no frontmatter defaults.
check("removed todo type has no TYPE_DEFAULTS entry", function()
	assert(config.TYPE_DEFAULTS.todo == nil, "todo should be gone from TYPE_DEFAULTS")
end)

if failures == 0 then
	print("\nAll tests passed.")
else
	print(string.format("\n%d test(s) FAILED.", failures))
	os.exit(1)
end
