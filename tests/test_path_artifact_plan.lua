-- Standalone tests for cue.core.path_artifact_plan
-- Run: luajit tests/test_path_artifact_plan.lua
--
-- path_artifact_plan is the pure, vim-free helper behind the path-prompt
-- creation flow (spec/trace). Unlike slug_artifact_plan it uses the entered
-- path VERBATIM: no slugification and no forced extension -- trace artifacts
-- are frequently JSON or plain text, not markdown. Root placement follows the
-- type-intrinsic policy (config.PATH_ROOT); frontmatter defaults apply only
-- to markdown (.md) paths because `cue add` prepends YAML frontmatter
-- unconditionally, which would corrupt e.g. a JSON file.
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

-- trace: json path kept verbatim, point-in-time (root=false), no frontmatter
check("trace json path is preserved with no frontmatter", function()
	local plan = core.path_artifact_plan("trace", "crash-log.json", "master")
	assert(plan ~= nil, "expected a plan, got nil")
	assert(plan.filename == "crash-log.json",
		"filename=" .. tostring(plan.filename))
	assert(plan.opts.category == "trace", "category=" .. tostring(plan.opts.category))
	assert(plan.opts.task == "master", "task=" .. tostring(plan.opts.task))
	assert(plan.opts.root == false, "trace should be pinned (root=false), got=" .. tostring(plan.opts.root))
	assert(count_keys(plan.opts.frontmatter) == 0,
		"non-markdown path must carry no frontmatter, got=" .. tostring(count_keys(plan.opts.frontmatter)))
end)

-- trace: extension-less and unusual extensions are equally verbatim
check("trace path with no extension is preserved", function()
	local plan = core.path_artifact_plan("trace", "raw-output", "my-task")
	assert(plan.filename == "raw-output", "filename=" .. tostring(plan.filename))
end)

check("trace txt path is preserved", function()
	local plan = core.path_artifact_plan("trace", "debug.txt", "master")
	assert(plan.filename == "debug.txt", "filename=" .. tostring(plan.filename))
	assert(plan.opts.root == false, "trace should be pinned")
end)

-- nested relative paths stay verbatim (cue add owns path validation)
check("relative directory components are preserved", function()
	local plan = core.path_artifact_plan("trace", "logs/run-42.json", "master")
	assert(plan.filename == "logs/run-42.json", "filename=" .. tostring(plan.filename))
end)

-- markdown paths DO get the type frontmatter defaults (todo used as the
-- only type with defaults that can exercise the .md branch here)
check("markdown path gets TYPE_DEFAULTS frontmatter", function()
	local plan = core.path_artifact_plan("todo", "followups.md", "master")
	assert(plan.opts.frontmatter.status == "open", "frontmatter status")
	assert(plan.opts.frontmatter.priority == "normal", "frontmatter priority")
end)

-- ...while the same type with a non-markdown extension gets none
check("non-markdown path skips TYPE_DEFAULTS frontmatter", function()
	local plan = core.path_artifact_plan("todo", "followups.json", "master")
	assert(count_keys(plan.opts.frontmatter) == 0,
		"json path must carry no frontmatter, got=" .. tostring(count_keys(plan.opts.frontmatter)))
end)

-- spec: root anchor document
check("spec path places artifact at root", function()
	local plan = core.path_artifact_plan("spec", "index.md", "master")
	assert(plan.opts.root == true, "spec should be root")
	assert(plan.filename == "index.md", "filename=" .. tostring(plan.filename))
end)

-- unlisted types default to pinned, mirroring the cue-plugins policy
check("unlisted type defaults to pinned (root=false)", function()
	local plan = core.path_artifact_plan("bin", "blob.bin", "master")
	assert(plan.opts.root == false, "bin should default to pinned")
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

-- PATH_ROOT policy is data-driven and matches the canonical cue-plugins
-- ROOT_DEFAULT_TYPES set (root only for spec/note/doc/plan)
check("PATH_ROOT encodes spec=root, trace=pinned", function()
	assert(config.PATH_ROOT.spec == true, "spec should be root")
	assert(config.PATH_ROOT.trace == false, "trace should be pinned")
end)

if failures == 0 then
	print("\nAll tests passed.")
else
	print(string.format("\n%d test(s) FAILED.", failures))
	os.exit(1)
end
