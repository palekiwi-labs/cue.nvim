-- Standalone tests for cue.picker.pick_context_artifacts
-- Run: luajit tests/test_context_artifact_picker.lua
--
-- Covers spec section 8 (palekiwi/palekiwi/cue-nvim-workflow/spec/index.md):
-- the dedicated explicit-context artifact picker.
--
--   * CLI wiring: `cue list --context <ctx>` with the five approved types
--     and the optional -C / --store passthrough.
--   * No implicit scope: a missing context never falls back to the active
--     context, so no CLI call is made at all.
--   * One searchable list in group order (task, spec, plan, note, trace),
--     alphabetical by displayed title inside a group.
--   * Rows show type + title with a filename fallback.
--   * File-content preview; Enter opens the file and does NOT activate the
--     context (no `cue switch`); no creation actions are mapped.
--   * Empty and error cases notify instead of opening a picker.
--
-- Stubs the minimal `vim` global and the Telescope modules that
-- cue.picker requires, so the real module runs without Neovim.

package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua"

-- ─── State shared by the vim / telescope stubs ────────────────────────

local state = {}

local function reset(opts)
	opts = opts or {}
	state = {
		commands = {}, -- every vim.system() argv, in order
		notifies = {}, -- { message, level }
		edits = {}, -- every vim.cmd.edit() argument
		escaped = {}, -- every vim.fn.fnameescape() argument
		maps = {}, -- every attach_mappings map() binding
		picker_opts = nil,
		found = false,
		closed = 0,
		selected = nil,
		select_default = nil,
		exit_code = opts.exit_code or 0,
		stdout = opts.stdout or "[]",
		decoded = opts.decoded or {},
		decode_error = opts.decode_error or false,
		status_exit_code = opts.status_exit_code or 0,
		status_stdout = opts.status_stdout or '{"context":"demo"}',
		status_stderr = opts.status_stderr or "",
		status_decoded = opts.status_decoded,
	}
end

reset()

-- ─── vim stub ─────────────────────────────────────────────────────────

vim = {} -- luacheck: ignore (global stub)
vim.NIL = {}
vim.log = { levels = { ERROR = 1, WARN = 2, INFO = 3, DEBUG = 4, TRACE = 5 } }

vim.system = function(cmd, _)
	local copy = {}
	for i, v in ipairs(cmd) do
		copy[i] = v
	end
	table.insert(state.commands, copy)
	return {
		wait = function()
			if cmd[2] == "status" then
				return {
					code = state.status_exit_code or 0,
					stdout = state.status_stdout or '{"context":"demo"}',
					stderr = state.status_stderr or "",
				}
			end
			return { code = state.exit_code, stdout = state.stdout, stderr = "" }
		end,
	}
end

vim.json = {
	decode = function(str)
		if state.decode_error then
			error("Expected value but found invalid token")
		end
		if type(str) == "string" and str:find('"context"', 1, true) then
			return state.status_decoded or { context = "demo" }
		end
		return state.decoded
	end,
}

vim.notify = function(msg, level)
	table.insert(state.notifies, { message = msg, level = level })
end

vim.cmd = {
	edit = function(path)
		table.insert(state.edits, path)
	end,
}

-- Marker wrapper: a path that has been through fnameescape is recognisable,
-- so a test can prove the ESCAPED value (not the raw path) reached :edit.
local function escaped_form(path)
	return "<fnameescape>" .. path
end

vim.fn = {
	fnamemodify = function(path, _)
		return path
	end,
	filereadable = function(_)
		return 1
	end,
	setreg = function(_, _) end,
	fnameescape = function(path)
		table.insert(state.escaped, path)
		return escaped_form(path)
	end,
}

vim.trim = function(s)
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

vim.schedule = function(fn)
	fn()
end

-- ─── telescope stubs ──────────────────────────────────────────────────

package.preload["telescope.pickers"] = function()
	return {
		new = function(_, opts)
			state.picker_opts = opts
			return {
				find = function()
					state.found = true
				end,
			}
		end,
	}
end

package.preload["telescope.finders"] = function()
	return {
		new_table = function(opts)
			return opts
		end,
	}
end

package.preload["telescope.config"] = function()
	return {
		values = {
			generic_sorter = function(_)
				return "GENERIC_SORTER"
			end,
			file_sorter = function(_)
				return "FILE_SORTER"
			end,
			file_previewer = function(_)
				return "FILE_PREVIEWER"
			end,
		},
	}
end

package.preload["telescope.actions"] = function()
	return {
		close = function(_)
			state.closed = state.closed + 1
		end,
		select_default = {
			replace = function(_, fn)
				state.select_default = fn
			end,
		},
	}
end

package.preload["telescope.actions.state"] = function()
	return {
		get_selected_entry = function()
			return state.selected
		end,
		get_current_picker = function(_)
			return nil
		end,
	}
end

package.preload["telescope.pickers.entry_display"] = function()
	return {
		create = function(_)
			-- Return the raw column list so tests can inspect the row.
			return function(cols)
				return cols
			end
		end,
	}
end

package.preload["telescope.make_entry"] = function()
	return {
		set_default_entry_mt = function(entry, _)
			return entry
		end,
		gen_from_file = function(_)
			return function(line)
				return { value = line, ordinal = line, display = line }
			end
		end,
	}
end

package.preload["telescope.utils"] = function()
	return {
		transform_path = function(_, path)
			return path
		end,
	}
end

local core = require("cue.core")
local picker = require("cue.picker")

-- ─── harness ──────────────────────────────────────────────────────────

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

local function artifact(cue_type, name, title)
	local fm = nil
	if title ~= nil then
		fm = { title = title }
	end
	return {
		path = "/store/palekiwi/palekiwi/demo/" .. cue_type .. "/" .. name,
		name = name,
		context = "demo",
		type = cue_type,
		frontmatter = fm,
	}
end

-- The wire payload `cue list --context demo --json --frontmatter` returns,
-- in the CLI's own (type-directory alphabetical) order.
local function fixture()
	return {
		artifact("note", "grouped-artifact-browser.md"),
		artifact("plan", "zeta-plan.md", "Zeta plan"),
		artifact("plan", "alpha-plan.md", "Alpha plan"),
		artifact("spec", "index.md", "Context and artifact workflows"),
		artifact("task", "context-artifact-picker.md", "Build the context artifact picker"),
		artifact("task", "archived.md", "Archived task"),
		artifact("trace", "handoff.md", "Session handoff"),
		artifact("bin", "state.json", "Binary state"),
		artifact("tmp", "scratch.md", "Scratch"),
	}
end

local function open_picker(context, opts, fixture_opts)
	fixture_opts = fixture_opts or {}
	reset({
		decoded = fixture_opts.decoded or fixture(),
		stdout = fixture_opts.stdout or "[json]",
		exit_code = fixture_opts.exit_code,
		decode_error = fixture_opts.decode_error,
	})
	picker.pick_context_artifacts(context, opts)
end

local function rows()
	assert(state.picker_opts, "no picker was opened")
	return state.picker_opts.finder.results
end

local function row_titles()
	local out = {}
	for _, a in ipairs(rows()) do
		table.insert(out, core.artifact_display_title(a))
	end
	return out
end

local function assert_order(expected)
	local got = row_titles()
	assert(#got == #expected, string.format("row count %d ~= %d: [%s]", #got, #expected, table.concat(got, ", ")))
	for i, want in ipairs(expected) do
		assert(
			got[i] == want,
			string.format("row %d = %q, expected %q ([%s])", i, tostring(got[i]), want, table.concat(got, ", "))
		)
	end
end

local function last_notify()
	return state.notifies[#state.notifies]
end

check("complete and closed artifacts have grey badges and titles", function()
	for _, status in ipairs({ "complete", "closed" }) do
		local item = artifact("plan", "finished.md", "Finished")
		item.frontmatter.status = status
		open_picker("demo", nil, { decoded = { item } })
		local entry = state.picker_opts.finder.entry_maker(item)
		local cells = entry:display()
		assert(cells[1][2] == "CueStatusComplete")
		assert(cells[2][2] == "CueStatusComplete")
	end
end)

-- Run attach_mappings and return the map() bindings it registered.
local function attach()
	local mappings = state.picker_opts.attach_mappings
	assert(type(mappings) == "function", "attach_mappings must be a function")
	mappings(1, function(mode, lhs, rhs)
		table.insert(state.maps, { mode = mode, lhs = lhs, rhs = rhs })
	end)
	return state.maps
end

-- ─── CLI wiring ───────────────────────────────────────────────────────

check("queries cue list for the explicit context only", function()
	open_picker("demo")
	assert(#state.commands == 1, "expected exactly one CLI call, got " .. #state.commands)
	local argv = state.commands[1]
	assert(
		table.concat(argv, " ") == table.concat(core.context_artifacts_argv("demo"), " "),
		"argv mismatch: " .. table.concat(argv, " ")
	)
	assert(argv[1] == "cue" and argv[2] == "list", "expected `cue list`")
end)

check("passes an explicit repo dir and store root through to the CLI", function()
	open_picker("demo", { dir = "/repo", store = "/store" })
	local argv = table.concat(state.commands[1], " ")
	assert(argv:find("-C /repo", 1, true), "missing -C /repo in: " .. argv)
	assert(argv:find("--store /store", 1, true), "missing --store /store in: " .. argv)
	assert(argv:find("--context demo", 1, true), "missing --context demo in: " .. argv)
end)

check("never falls back to the active context", function()
	open_picker(nil)
	assert(#state.commands == 0, "a missing context must not run any CLI command")
	assert(not state.picker_opts, "a missing context must not open a picker")
	assert(last_notify() ~= nil, "a missing context must notify")
	assert(last_notify().level == vim.log.levels.ERROR, "missing context is an error")

	open_picker("   ")
	assert(#state.commands == 0, "a blank context must not run any CLI command")
	assert(not state.picker_opts, "a blank context must not open a picker")
end)

-- ─── ordering and membership ──────────────────────────────────────────

check("lists one searchable list grouped task/spec/plan/note/trace", function()
	open_picker("demo")
	assert_order({
		"Archived task",
		"Build the context artifact picker",
		"Context and artifact workflows",
		"Alpha plan",
		"Zeta plan",
		"grouped-artifact-browser.md",
		"Session handoff",
	})
end)

check("excludes the deferred bin and tmp types", function()
	open_picker("demo")
	for _, a in ipairs(rows()) do
		assert(a.type ~= "bin", "bin artifacts must not be listed")
		assert(a.type ~= "tmp", "tmp artifacts must not be listed")
	end
end)

check("includes tasks whatever their status", function()
	local payload = {
		artifact("task", "closed.md", "Closed task"),
		artifact("task", "inbox.md", "Inbox task"),
	}
	payload[1].frontmatter = { title = "Closed task", status = "closed" }
	payload[2].frontmatter = { title = "Inbox task", status = "inbox" }
	open_picker("demo", nil, { decoded = payload })
	assert_order({ "Inbox task", "Closed task" })
end)

check("preserves the grouped order for the empty query", function()
	open_picker("demo")
	-- Telescope's fzy sorter scores every entry 1 for an empty prompt, so the
	-- finder's insertion order survives; ties at other prompts are kept in
	-- insertion order by an explicit tiebreak (the default would re-sort them
	-- by ordinal length).
	local tiebreak = state.picker_opts.tiebreak
	assert(type(tiebreak) == "function", "picker must set an explicit tiebreak")
	assert(tiebreak({ ordinal = "a" }, { ordinal = "bbbbbb" }, "") == false, "tiebreak must preserve insertion order")
	assert(state.picker_opts.sorter, "picker must have a sorter")
end)

-- ─── rows ─────────────────────────────────────────────────────────────

check("rows show artifact type and title, with a filename fallback", function()
	open_picker("demo")
	local entry_maker = state.picker_opts.finder.entry_maker
	assert(type(entry_maker) == "function", "finder needs an entry_maker")

	local titled = entry_maker(artifact("task", "context-artifact-picker.md", "Build the context artifact picker"))
	local cols = titled.display(titled)
	assert(cols[1][1] == "TASK", "expected the type badge, got " .. tostring(cols[1][1]))
	assert(cols[2][1] == "Build the context artifact picker", "expected the title, got " .. tostring(cols[2][1]))

	local untitled = entry_maker(artifact("note", "grouped-artifact-browser.md"))
	local fallback_cols = untitled.display(untitled)
	assert(fallback_cols[1][1] == "NOTE", "expected the NOTE badge")
	assert(fallback_cols[2][1] == "grouped-artifact-browser.md", "expected the filename fallback")
end)

check("rows carry the file path and a searchable ordinal", function()
	open_picker("demo")
	local entry_maker = state.picker_opts.finder.entry_maker
	local a = artifact("spec", "index.md", "Context and artifact workflows")
	local entry = entry_maker(a)
	assert(entry.path == a.path, "entry.path must be the artifact file path")
	assert(entry.ordinal:find("spec", 1, true), "ordinal should contain the type: " .. entry.ordinal)
	assert(entry.ordinal:find("Context and artifact workflows", 1, true), "ordinal should contain the title")
	assert(entry.ordinal:find("index.md", 1, true), "ordinal should contain the filename")
end)

check("entry maker skips rows without a path", function()
	open_picker("demo")
	local entry_maker = state.picker_opts.finder.entry_maker
	assert(entry_maker(nil) == nil, "nil artifact yields no entry")
	assert(entry_maker({ type = "task", name = "k.md" }) == nil, "path-less artifact yields no entry")
end)

-- ─── preview and actions ──────────────────────────────────────────────

check("previews the selected file's contents", function()
	open_picker("demo")
	assert(state.picker_opts.previewer == "FILE_PREVIEWER", "expected the Telescope file previewer")
end)

check("enter opens the file without activating the context", function()
	open_picker("demo")
	attach()
	assert(type(state.select_default) == "function", "Enter must be remapped to open the file")

	local before = #state.commands
	state.selected = { path = "/store/palekiwi/palekiwi/demo/task/context-artifact-picker.md" }
	state.select_default()

	assert(#state.edits == 1, "expected exactly one buffer open, got " .. #state.edits)
	assert(state.edits[1] == escaped_form(state.selected.path), "Enter must open the selected artifact")
	assert(state.closed == 1, "Enter must close the picker")
	assert(#state.commands == before, "Enter must not run any cue command (no activation)")
end)

check("enter escapes the path before handing it to :edit", function()
	-- Regression: `:edit` expands `%` to the current file and `#` to the
	-- alternate file, so an unescaped path silently opens the WRONG file
	-- (verified in headless Neovim: /tmp/a%b.md opened /tmp/a/tmp/a b.mdb.md).
	-- Spaces truncate the argument the same way. fnameescape is mandatory.
	local tricky = {
		"/store/palekiwi/palekiwi/demo/note/a%b.md",
		"/store/palekiwi/palekiwi/demo/note/c#d.md",
		"/store/palekiwi/palekiwi/demo/note/with space.md",
		"/store/palekiwi/palekiwi/demo/note/all %#and space.md",
	}

	for _, path in ipairs(tricky) do
		open_picker("demo")
		attach()
		state.selected = { path = path }
		state.select_default()

		assert(#state.escaped == 1, "expected exactly one fnameescape call for " .. path)
		assert(state.escaped[1] == path, "fnameescape must receive the raw artifact path")
		assert(#state.edits == 1, "expected exactly one buffer open for " .. path)
		assert(
			state.edits[1] == escaped_form(path),
			string.format(":edit got %q, expected the escaped path for %q", tostring(state.edits[1]), path)
		)
	end
end)

check("enter is a no-op without a selection", function()
	open_picker("demo")
	attach()
	state.selected = nil
	state.select_default()
	assert(#state.edits == 0, "no selection means nothing to open")
end)

check("maps no creation or activation actions", function()
	open_picker("demo")
	local maps = attach()
	assert(#maps == 0, "the artifact picker must map no extra actions, got " .. #maps)
end)

-- ─── empty and error cases ────────────────────────────────────────────

check("notifies instead of opening an empty picker", function()
	open_picker("demo", nil, { decoded = {} })
	assert(not state.picker_opts, "an empty context must not open a picker")
	assert(last_notify() ~= nil and last_notify().level == vim.log.levels.INFO, "empty result is informational")
	assert(last_notify().message:find("demo", 1, true), "the notification should name the context")
end)

check("notifies when only deferred types are present", function()
	open_picker("demo", nil, {
		decoded = { artifact("bin", "state.json", "Binary state"), artifact("tmp", "scratch.md", "Scratch") },
	})
	assert(not state.picker_opts, "bin/tmp-only contexts must not open a picker")
	assert(last_notify().level == vim.log.levels.INFO, "empty result is informational")
end)

check("notifies when the CLI call fails", function()
	open_picker("demo", nil, { exit_code = 1 })
	assert(not state.picker_opts, "a failed CLI call must not open a picker")
	assert(last_notify() ~= nil and last_notify().level == vim.log.levels.ERROR, "CLI failure is an error")
end)

check("notifies when the CLI payload is not JSON", function()
	open_picker("demo", nil, { decode_error = true })
	assert(not state.picker_opts, "unparseable output must not open a picker")
	assert(last_notify() ~= nil and last_notify().level == vim.log.levels.ERROR, "parse failure is an error")
end)

check("notifies when the CLI returns no output", function()
	open_picker("demo", nil, { stdout = "" })
	assert(not state.picker_opts, "empty output must not open a picker")
	assert(last_notify() ~= nil and last_notify().level == vim.log.levels.ERROR, "empty output is an error")
end)

-- ─── public API ───────────────────────────────────────────────────────

check("is re-exported from the cue module", function()
	local cue = require("cue")
	assert(type(cue.pick_context_artifacts) == "function", "cue.pick_context_artifacts must be public")
	reset({ decoded = fixture(), stdout = "[json]" })
	cue.pick_context_artifacts("demo")
	assert(state.found, "the re-export must open the picker")
end)

-- ─── active context picker (<C-s>) ────────────────────────────────────

check("pick_active_context_artifacts resolves active context and opens picker", function()
	reset({
		status_decoded = { context = "active-feature" },
		decoded = fixture(),
		stdout = "[json]",
	})
	picker.pick_active_context_artifacts()
	assert(#state.commands == 2, "expected 2 commands (status then list), got " .. #state.commands)
	assert(state.commands[1][2] == "status", "command 1 must be `cue status`")
	assert(state.commands[2][2] == "list", "command 2 must be `cue list`")
	local list_cmd = table.concat(state.commands[2], " ")
	assert(list_cmd:find("--context active-feature", 1, true), "expected --context active-feature in: " .. list_cmd)
	assert(state.picker_opts ~= nil, "picker must be opened for active context")
	assert(state.picker_opts.prompt_title == "Cue Artifacts (active-feature)")
end)

check("pick_active_context_artifacts passes dir and store through to status and list", function()
	reset({
		status_decoded = { context = "active-feature" },
		decoded = fixture(),
		stdout = "[json]",
	})
	picker.pick_active_context_artifacts({ dir = "/repo", store = "/store" })
	local status_cmd = table.concat(state.commands[1], " ")
	assert(status_cmd:find("-C /repo", 1, true), "status missing -C /repo")
	assert(status_cmd:find("--store /store", 1, true), "status missing --store /store")
	local list_cmd = table.concat(state.commands[2], " ")
	assert(list_cmd:find("-C /repo", 1, true), "list missing -C /repo")
	assert(list_cmd:find("--store /store", 1, true), "list missing --store /store")
	assert(list_cmd:find("--context active-feature", 1, true), "list missing --context active-feature")
end)

check("pick_active_context_artifacts notifies and does not open when context is unset", function()
	reset({
		status_decoded = { context = nil },
		decoded = fixture(),
	})
	picker.pick_active_context_artifacts()
	assert(state.picker_opts == nil, "no picker when context is unset")
	assert(last_notify() ~= nil, "expected notification")
	assert(last_notify().level == vim.log.levels.WARN, "unset context is a warning")
	assert(#state.commands == 1, "only cue status should run")
end)

check("pick_active_context_artifacts notifies on status command error", function()
	reset({
		status_exit_code = 1,
		status_stderr = "git remote origin error",
	})
	picker.pick_active_context_artifacts()
	assert(state.picker_opts == nil, "no picker on status error")
	assert(last_notify() ~= nil, "expected notification")
	assert(last_notify().level == vim.log.levels.ERROR, "status failure is an error")
end)

check("pick_active_context_artifacts is re-exported from cue module", function()
	local cue = require("cue")
	assert(type(cue.pick_active_context_artifacts) == "function", "cue.pick_active_context_artifacts must be public")
end)

-- The legacy task-scoped surface is gone, not aliased. Keeping
-- pick_active_task_artifacts as a forwarder would preserve the task-scope
-- vocabulary the migration is retiring.
check("the legacy task-scoped picker names are gone", function()
	local cue = require("cue")
	assert(picker.pick_active_task_artifacts == nil, "picker.pick_active_task_artifacts must be removed")
	assert(cue.pick_active_task_artifacts == nil, "cue.pick_active_task_artifacts must be removed")
	assert(picker.pick_inbox_tasks == nil, "picker.pick_inbox_tasks must be removed")
	assert(picker.pick_done_tasks == nil, "picker.pick_done_tasks must be removed")
	assert(picker.pick_task_context_artifacts == nil, "picker.pick_task_context_artifacts must be removed")
	assert(picker.pick_logs == nil, "picker.pick_logs must be removed")
	assert(picker.ui_pick == nil, "picker.ui_pick must be removed")
end)

-- pick_artifacts drove `cue list --task/--all/--include-gitignored`, none of
-- which the CLI accepts any more, and pick_context shelled out to
-- `cue context path --all`, which is not a subcommand. Both were unreachable
-- rather than merely stale, so they were deleted instead of repaired.
check("the master-board and context-path pickers are gone", function()
	local cue = require("cue")
	assert(picker.pick_artifacts == nil, "picker.pick_artifacts must be removed")
	assert(cue.pick_artifacts == nil, "cue.pick_artifacts must be removed")
	assert(picker.pick_context == nil, "picker.pick_context must be removed")
	assert(cue.pick_context == nil, "cue.pick_context must be removed")
end)

if failures == 0 then
	print("\nAll tests passed.")
else
	print(string.format("\n%d test(s) FAILED.", failures))
	os.exit(1)
end
