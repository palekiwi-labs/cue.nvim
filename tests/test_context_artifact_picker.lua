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
--   * One searchable list in group order (task, spec, plan, note, trace,
--     bin, tmp), alphabetical by displayed title inside a group.
--   * Rows show type, a priority caret, the title (filename fallback) and
--     the creation age, every column a fixed width: the title is 72 cells
--     and the age follows it, so the age stays beside the title instead of
--     drifting to the far edge of a near-fullscreen window.
--   * File-content preview; Enter opens the file and does NOT activate the
--     context (no `cue switch`); no creation actions are mapped.
--   * The copy actions honor <Tab> multi-selection, as master's pickers
--     did: every toggled row contributes, space-joined in ONE register
--     write; the highlighted row alone is copied when nothing is toggled.
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
		registers = {}, -- every vim.fn.setreg() call: { name, value }
		multi = {}, -- the picker's multi-selection (<Tab> toggles)
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

-- Route the decode by the STDOUT the stub handed back, not by sniffing the
-- payload's shape: a status payload need not mention a context (a branch
-- with no association still has a scope), and the picker's whole point is
-- to read the scope out of one.
vim.json = {
	decode = function(str)
		if state.decode_error then
			error("Expected value but found invalid token")
		end
		if str == state.status_stdout or (type(str) == "string" and str:find('"scope"', 1, true)) then
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
	setreg = function(name, value)
		table.insert(state.registers, { name = name, value = value })
	end,
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
			return {
				get_multi_selection = function()
					return state.multi or {}
				end,
			}
		end,
	}
end

package.preload["telescope.pickers.entry_display"] = function()
	return {
		create = function(opts)
			-- Record the declared column layout, and return the raw column
			-- list so tests can inspect the row.
			state.columns = opts.items
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

-- A real grouped tmp row name: `<nanosecond timestamp>-<short commit hash>`
-- as the directory, then the file. Copied from a live `cue list` payload.
local GROUPED_TMP_NAME = "1789366283853051953-d8dc048d49/review-comments-delta-1789366283.json"
local GROUPED_TMP_SECONDS = 1789366283

-- The task picker's Jira-style priority carets, restored here unchanged:
-- U+F102 angle-double-up (critical) and U+F106 angle-up (high). normal and
-- low render blank.
local CARET_CRITICAL = "\239\132\130"
local CARET_HIGH = "\239\132\134"

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
		-- bin and tmp arrive WITHOUT a frontmatter key: `cue add` refuses
		-- metadata for both, so the picker only ever sees path/name/type.
		artifact("bin", "run.sh"),
		artifact("tmp", GROUPED_TMP_NAME),
		artifact("tmp", "legacy.diff"),
	}
end

local function open_picker(context, opts, fixture_opts)
	fixture_opts = fixture_opts or {}
	reset({
		decoded = fixture_opts.decoded or fixture(),
		stdout = fixture_opts.stdout or "[json]",
		exit_code = fixture_opts.exit_code,
		decode_error = fixture_opts.decode_error,
		status_exit_code = fixture_opts.status_exit_code,
		status_stdout = fixture_opts.status_stdout or '{"scope":"palekiwi/palekiwi"}',
		status_stderr = fixture_opts.status_stderr,
		status_decoded = fixture_opts.status_decoded or { scope = "palekiwi/palekiwi" },
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

check("complete and closed artifacts grey out every column", function()
	for _, status in ipairs({ "complete", "closed" }) do
		local item = artifact("plan", "finished.md", "Finished")
		item.frontmatter.status = status
		item.frontmatter.priority = "critical"
		item.frontmatter.created_at = GROUPED_TMP_SECONDS
		open_picker("demo", nil, { decoded = { item } })
		local entry = state.picker_opts.finder.entry_maker(item)
		local cells = entry:display()
		assert(#cells == 4, status .. ": expected four columns, got " .. #cells)
		for i = 1, 4 do
			assert(
				cells[i][2] == "CueStatusComplete",
				string.format("%s: column %d = %q, expected CueStatusComplete", status, i, tostring(cells[i][2]))
			)
		end
		-- The caret still renders; only its colour is overridden.
		assert(cells[2][1] == CARET_CRITICAL, status .. ": the priority caret must survive dimming")
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

check("lists one searchable list grouped task/spec/plan/note/trace/bin/tmp", function()
	open_picker("demo")
	assert_order({
		"Archived task",
		"Build the context artifact picker",
		"Context and artifact workflows",
		"Alpha plan",
		"Zeta plan",
		"grouped-artifact-browser.md",
		"Session handoff",
		"run.sh",
		GROUPED_TMP_NAME,
		"legacy.diff",
	})
end)

check("includes bin and tmp artifacts", function()
	open_picker("demo")
	local seen = {}
	for _, a in ipairs(rows()) do
		seen[a.type] = true
	end
	assert(seen.bin, "bin artifacts must be listed")
	assert(seen.tmp, "tmp artifacts must be listed")
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
	assert(cols[3][1] == "Build the context artifact picker", "expected the title, got " .. tostring(cols[3][1]))

	local untitled = entry_maker(artifact("note", "grouped-artifact-browser.md"))
	local fallback_cols = untitled.display(untitled)
	assert(fallback_cols[1][1] == "NOTE", "expected the NOTE badge")
	assert(fallback_cols[3][1] == "grouped-artifact-browser.md", "expected the filename fallback")
end)

check("columns are type, priority caret, title, creation age", function()
	open_picker("demo")
	local cols = state.columns
	assert(type(cols) == "table", "the picker must declare a column layout")
	assert(#cols == 4, "expected four columns, got " .. #cols)
	assert(cols[1].width == 5, "the type badge is five cells (the longest badge is TRACE)")
	assert(cols[2].width == 1, "the priority caret is a single cell")
	assert(cols[4].width == 4, "the age column is four cells (the widest value is 364d)")
	assert(cols[4].right_justify, "the age column is right justified against the results edge")
	assert(not cols[4].remaining, "a remaining age column would drift with the title")
end)

check("the title is a fixed 72 cells", function()
	open_picker("demo")
	local width = state.columns[3].width
	-- A fixed count, not a function: a flexible title on a 95% window
	-- would push the age column to the far edge of a wide terminal. The
	-- age therefore follows the title at a fixed offset instead.
	assert(width == 72, "expected 72, got " .. tostring(width))
end)

check("the priority caret flags critical and high only", function()
	open_picker("demo")
	local entry_maker = state.picker_opts.finder.entry_maker
	local function caret(priority)
		local item = artifact("task", "k.md", "Task")
		item.frontmatter.priority = priority
		local entry = entry_maker(item)
		return entry:display()[2]
	end

	local critical = caret("critical")
	assert(critical[1] == CARET_CRITICAL, "critical must render the double caret")
	assert(critical[2] == "CuePriorityCritical", "critical caret is red")

	local high = caret("high")
	assert(high[1] == CARET_HIGH, "high must render the single caret")
	assert(high[2] == "CuePriorityHigh", "high caret is orange")

	-- normal is the norm and low is rare clutter: both stay blank, so the
	-- caret column reads as a flag rather than a fourth colour.
	for _, priority in ipairs({ "normal", "low", "bogus", "" }) do
		assert(caret(priority)[1] == "", priority .. " must render blank")
	end
	assert(caret(nil)[1] == "", "a missing priority renders blank")
	assert(caret(vim.NIL)[1] == "", "a vim.NIL priority renders blank")
	assert(caret(3)[1] == "", "a non-string priority renders blank")
end)

check("the priority caret is case-insensitive", function()
	open_picker("demo")
	local item = artifact("task", "k.md", "Task")
	item.frontmatter.priority = "CRITICAL"
	local entry = state.picker_opts.finder.entry_maker(item)
	assert(entry:display()[2][1] == CARET_CRITICAL, "priority matching ignores case")
end)

check("bin and tmp rows render a blank caret", function()
	open_picker("demo")
	local entry_maker = state.picker_opts.finder.entry_maker
	for _, a in ipairs({ artifact("bin", "run.sh"), artifact("tmp", "legacy.diff") }) do
		local entry = entry_maker(a)
		local cells = entry:display()
		assert(cells[2][1] == "", a.type .. " carries no frontmatter, so no caret")
		assert(cells[1][1] == a.type:upper(), "expected the " .. a.type .. " badge")
	end
end)

check("the creation column shows a compact relative age, dash when absent", function()
	-- Sampled BEFORE the picker opens, so the picker's own clock sample is
	-- never earlier than this one and an offset can only round upwards.
	local before = os.time()
	open_picker("demo")
	local entry_maker = state.picker_opts.finder.entry_maker

	local function age(seconds_ago)
		local dated = artifact("task", "k.md", "Task")
		dated.frontmatter.created_at = before - seconds_ago
		return entry_maker(dated):display()[4][1]
	end

	assert(age(30) == "now", "under a minute reads now, got " .. age(30))
	assert(age(600) == "10m", "ten minutes reads 10m, got " .. age(600))
	assert(age(7200) == "2h", "two hours reads 2h, got " .. age(7200))
	assert(age(86400 * 3) == "3d", "three days reads 3d, got " .. age(86400 * 3))
	assert(age(86400 * 400) == "1y", "past a year reads 1y, got " .. age(86400 * 400))

	-- tmp has no frontmatter at all: the stamp is parsed out of the group
	-- directory cue names `<nanosecond timestamp>-<short commit hash>`, and
	-- that extraction still feeds the column.
	local grouped = artifact("tmp", GROUPED_TMP_NAME)
	assert(entry_maker(grouped):display()[4][1] ~= "—", "the tmp group directory drives the column")

	-- A legacy flat tmp file and a bin script have no stamp anywhere, and
	-- the filesystem mtime is NOT a fallback.
	assert(entry_maker(artifact("tmp", "legacy.diff")):display()[4][1] == "—", "undated tmp shows a dash")
	assert(entry_maker(artifact("bin", "run.sh")):display()[4][1] == "—", "bin shows a dash")

	local undated = artifact("note", "n.md", "Note")
	assert(entry_maker(undated):display()[4][1] == "—", "a missing created_at shows a dash")
end)

check("the age column is sampled once per picker, not once per row", function()
	local real_time = os.time
	local calls = 0
	os.time = function(...) -- luacheck: ignore
		calls = calls + 1
		return real_time(...)
	end
	local ok, err = pcall(function()
		open_picker("demo")
		local sampled = calls
		assert(sampled == 1, "opening the picker must sample the clock once, got " .. sampled)
		local entry_maker = state.picker_opts.finder.entry_maker
		for _, a in ipairs(fixture()) do
			entry_maker(a):display()
		end
		assert(calls == sampled, "rendering rows must reuse the sampled clock, got " .. calls)
	end)
	os.time = real_time -- luacheck: ignore
	assert(ok, err)
end)

check("the creation column is muted", function()
	open_picker("demo")
	local dated = artifact("task", "k.md", "Task")
	dated.frontmatter.created_at = GROUPED_TMP_SECONDS
	local cells = state.picker_opts.finder.entry_maker(dated):display()
	assert(cells[4][2] == "TelescopeResultsComment", "creation age is metadata, not content")
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

check("keeps the preview below the results, prompt on top", function()
	open_picker("demo")
	assert(state.picker_opts.layout_strategy == "vertical", "the preview sits below the results")
	local layout = state.picker_opts.layout_config
	assert(layout.mirror == true, "mirror puts the preview below rather than above")
	assert(layout.prompt_position == "top")
	assert(layout.preview_height == 0.5, "the preview takes half the height")
end)

check("takes 95% of the editor width", function()
	open_picker("demo")
	local width = state.picker_opts.layout_config.width
	-- Telescope resolves a layout width below 1 as a share of the editor
	-- (telescope.config.resolve.resolve_width), so the plain number is the
	-- percentage: a near-fullscreen window, as before the columns changed.
	assert(width == 0.95, "expected 0.95, got " .. tostring(width))
end)

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
	-- Copying is a read: the only extra bindings are the two yank actions,
	-- in insert and normal mode. Nothing creates, switches or pins.
	for _, m in ipairs(maps) do
		assert(m.lhs == "<C-y>" or m.lhs == "<C-h>", "unexpected binding " .. m.lhs)
	end
	assert(#maps == 4, "expected only the two copy bindings in two modes, got " .. #maps)
end)

-- ─── copying the path and the canonical address ───────────────────────

-- Find the handler registered for `lhs` in `mode` (default insert).
local function binding(lhs, mode)
	for _, m in ipairs(state.maps) do
		if m.lhs == lhs and m.mode == (mode or "i") then
			return m.rhs
		end
	end
	return nil
end

local function copied()
	assert(#state.registers <= 1, "a copy writes exactly one register, got " .. #state.registers)
	return state.registers[1]
end

local function status_calls()
	local n = 0
	for _, argv in ipairs(state.commands) do
		if argv[2] == "status" then
			n = n + 1
		end
	end
	return n
end

check("binds the copy actions in insert and normal mode", function()
	open_picker("demo")
	attach()
	for _, mode in ipairs({ "i", "n" }) do
		assert(binding("<C-y>", mode), "<C-y> must be bound in " .. mode .. " mode")
		assert(binding("<C-h>", mode), "<C-h> must be bound in " .. mode .. " mode")
	end
end)

check("C-y copies the absolute file path to the system clipboard", function()
	open_picker("demo")
	attach()
	local path = "/home/pl/cue/palekiwi/palekiwi/demo/spec/index.md"
	state.selected = { path = path, value = artifact("spec", "index.md", "Spec") }
	binding("<C-y>")()

	local reg = copied()
	assert(reg, "<C-y> must write a register")
	assert(reg.name == "+", "the system clipboard is register +, got " .. tostring(reg.name))
	assert(reg.value == path, "expected the absolute path, got " .. tostring(reg.value))
	assert(last_notify() and last_notify().message:find(path, 1, true), "the notification names the copied value")
	assert(state.closed == 0, "copying keeps the picker open")
	assert(#state.edits == 0, "copying opens nothing")
end)

check("C-y needs no scope query", function()
	open_picker("demo")
	attach()
	state.selected = { path = "/home/pl/cue/palekiwi/palekiwi/demo/spec/index.md" }
	local before = #state.commands
	binding("<C-y>")()
	assert(#state.commands == before, "the path is already on the entry; no CLI call")
end)

check("C-h copies the canonical address, not the store path", function()
	open_picker("demo")
	attach()
	local a = artifact("spec", "index.md", "Spec")
	state.selected = { path = a.path, value = a }
	binding("<C-h>")()

	local reg = copied()
	assert(reg, "<C-h> must write a register")
	assert(reg.name == "+", "the system clipboard is register +")
	assert(
		reg.value == "palekiwi/palekiwi/demo/spec/index.md",
		"expected the canonical address, got " .. tostring(reg.value)
	)
	assert(reg.value:sub(1, 1) ~= "/", "an address is never an absolute path")
	assert(not reg.value:find("/home/pl/cue", 1, true), "the store root must not leak into the address")
	assert(state.closed == 0, "copying keeps the picker open")
end)

check("C-h resolves the scope with a status query aimed at the same repo", function()
	open_picker("demo", { dir = "/repo", store = "/store" })
	attach()
	state.selected = { value = artifact("note", "idea.md") }
	binding("<C-h>")()

	local status = nil
	for _, argv in ipairs(state.commands) do
		if argv[2] == "status" then
			status = table.concat(argv, " ")
		end
	end
	assert(status, "<C-h> must resolve the scope from cue status")
	assert(status:find("-C /repo", 1, true), "status must be aimed at the queried dir: " .. status)
	assert(status:find("--store /store", 1, true), "status must use the queried store: " .. status)
	assert(status:find("--json", 1, true), "status must be asked for JSON")
end)

check("C-h uses the queried repository's scope, not the current one", function()
	-- Browsing another repository (`opts.dir`) must address its artifacts in
	-- THAT repository's scope. The scope comes from the status query the
	-- picker aimed at the same directory, never from the cwd or from
	-- splitting the artifact path.
	open_picker("demo", { dir = "/other" }, {
		status_stdout = '{"scope":"palekiwi-labs/cue","context":null}',
		status_decoded = { scope = "palekiwi-labs/cue", context = vim.NIL },
	})
	attach()
	state.selected = { value = artifact("plan", "index.md", "Plan") }
	binding("<C-h>")()
	assert(copied().value == "palekiwi-labs/cue/demo/plan/index.md", "got " .. tostring(copied().value))
end)

check("C-h is unaffected by which context is active", function()
	-- The active context is a different context entirely (the picker browses
	-- an explicit one), and the address must name the BROWSED context.
	open_picker("demo", nil, {
		status_stdout = '{"scope":"palekiwi/palekiwi","context":"cue-platform-direction"}',
		status_decoded = { scope = "palekiwi/palekiwi", context = "cue-platform-direction" },
	})
	attach()
	state.selected = { value = artifact("task", "widen-picker.md", "Widen the picker") }
	binding("<C-h>")()
	assert(copied().value == "palekiwi/palekiwi/demo/task/widen-picker.md", "got " .. tostring(copied().value))
end)

check("C-h addresses a grouped tmp artifact through its group directory", function()
	open_picker("demo")
	attach()
	state.selected = { value = artifact("tmp", GROUPED_TMP_NAME) }
	binding("<C-h>")()
	assert(
		copied().value == "palekiwi/palekiwi/demo/tmp/" .. GROUPED_TMP_NAME,
		"the tmp group directory belongs in the address, got " .. tostring(copied().value)
	)
end)

check("C-h addresses a bin artifact", function()
	open_picker("demo")
	attach()
	state.selected = { value = artifact("bin", "run.sh") }
	binding("<C-h>")()
	assert(copied().value == "palekiwi/palekiwi/demo/bin/run.sh", "got " .. tostring(copied().value))
end)

check("C-h resolves the scope once per picker", function()
	open_picker("demo")
	attach()
	state.selected = { value = artifact("spec", "index.md", "Spec") }
	binding("<C-h>")()
	local after_first = status_calls()
	assert(after_first == 1, "the first copy resolves the scope, got " .. after_first)
	state.registers = {}
	binding("<C-h>", "n")()
	assert(status_calls() == after_first, "a second copy must reuse the resolved scope")
	assert(copied().value == "palekiwi/palekiwi/demo/spec/index.md", "the memoised scope still addresses")
end)

check("C-h copies nothing when the scope cannot be resolved", function()
	local cases = {
		{
			name = "status without a scope",
			opts = { status_stdout = '{"context":"demo"}', status_decoded = { context = "demo" } },
		},
		{
			name = "null scope",
			opts = { status_stdout = '{"scope":null}', status_decoded = { scope = vim.NIL } },
		},
		{
			name = "status command failure",
			opts = { status_exit_code = 1, status_stderr = "not a git repository" },
		},
	}
	for _, c in ipairs(cases) do
		open_picker("demo", nil, c.opts)
		attach()
		state.selected = { path = "/home/pl/cue/x/demo/spec/index.md", value = artifact("spec", "index.md", "Spec") }
		binding("<C-h>")()
		assert(#state.registers == 0, c.name .. ": a bogus address must never be copied")
		assert(last_notify() ~= nil, c.name .. ": the failure must be reported")
		assert(last_notify().level == vim.log.levels.ERROR, c.name .. ": an unresolvable scope is an error")
		assert(state.closed == 0, c.name .. ": a failed copy keeps the picker open")
	end
end)

check("C-h copies nothing when the row lacks the fields an address needs", function()
	open_picker("demo")
	attach()
	-- A row that somehow reached the picker without a type or name has no
	-- address; the absolute path is NOT substituted for one.
	state.selected = { path = "/home/pl/cue/palekiwi/palekiwi/demo/spec/index.md", value = { context = "demo" } }
	binding("<C-h>")()
	assert(#state.registers == 0, "an incomplete row must not be addressed")
	assert(last_notify() ~= nil and last_notify().level == vim.log.levels.ERROR, "missing metadata is an error")
end)

check("both copy actions are no-ops without a selection", function()
	for _, lhs in ipairs({ "<C-y>", "<C-h>" }) do
		open_picker("demo")
		attach()
		state.selected = nil
		binding(lhs)()
		assert(#state.registers == 0, lhs .. " must copy nothing without a selection")
		assert(state.closed == 0, lhs .. " must keep the picker open")
		assert(last_notify() ~= nil, lhs .. " must say why nothing was copied")
	end
end)

check("C-y copies nothing when the selection carries no path", function()
	open_picker("demo")
	attach()
	state.selected = { value = { context = "demo", type = "spec", name = "index.md" } }
	binding("<C-y>")()
	assert(#state.registers == 0, "no path, no copy")
	assert(last_notify() ~= nil, "the miss must be reported")
end)

-- ─── multi-selection copies ────────────────────────────────────────────

-- The single-selection tests above all run with an EMPTY multi-selection,
-- so together they already pin the fallback: nothing toggled means the
-- highlighted row alone is copied. The tests here pin the toggled case.

check("C-y copies every multi-selected path in one register write", function()
	open_picker("demo")
	attach()
	local first = "/home/pl/cue/palekiwi/palekiwi/demo/spec/index.md"
	local second = "/home/pl/cue/palekiwi/palekiwi/demo/task/multi.md"
	-- The highlighted row must NOT contribute: a toggle selection replaces
	-- it, exactly as master's copy did.
	state.selected = { path = "/home/pl/cue/palekiwi/palekiwi/demo/note/highlighted.md" }
	state.multi = {
		{ path = first, value = artifact("spec", "index.md", "Spec") },
		{ path = second, value = artifact("task", "multi.md") },
	}
	binding("<C-y>")()

	local reg = copied()
	assert(reg, "C-y must write a register")
	assert(reg.name == "+", "the system clipboard is register +")
	assert(reg.value == first .. " " .. second, "paths join space-separated, got " .. tostring(reg.value))
	assert(not reg.value:find("highlighted", 1, true), "the merely highlighted row must not contribute")
	assert(last_notify().message:find("2 items", 1, true), "the notification reports the count, not every value")
	assert(state.closed == 0, "copying keeps the picker open")
	assert(#state.edits == 0, "copying opens nothing")
end)

check("C-h copies every multi-selected address in one register write", function()
	open_picker("demo")
	attach()
	state.selected = { value = artifact("note", "highlighted.md") }
	state.multi = {
		{ value = artifact("spec", "index.md", "Spec") },
		{ value = artifact("task", "multi.md") },
	}
	binding("<C-h>")()

	local reg = copied()
	assert(reg, "C-h must write a register")
	assert(
		reg.value == "palekiwi/palekiwi/demo/spec/index.md palekiwi/palekiwi/demo/task/multi.md",
		"addresses join space-separated, got " .. tostring(reg.value)
	)
	assert(not reg.value:find("highlighted", 1, true), "the merely highlighted row must not contribute")
	assert(status_calls() == 1, "the scope resolves once for the whole batch, got " .. status_calls())
	assert(state.closed == 0, "copying keeps the picker open")
end)

check("C-h skips multi entries that cannot be addressed", function()
	open_picker("demo")
	attach()
	state.multi = {
		{ value = artifact("spec", "index.md", "Spec") },
		{ value = { context = "demo" } }, -- no type/name: no address
	}
	binding("<C-h>")()
	assert(
		copied().value == "palekiwi/palekiwi/demo/spec/index.md",
		"one unaddressable row must not sink the addressable one"
	)
end)

check("C-y skips multi entries without a path", function()
	open_picker("demo")
	attach()
	state.multi = {
		{ path = "/home/pl/cue/palekiwi/palekiwi/demo/spec/index.md" },
		{ value = { context = "demo", type = "spec", name = "index.md" } },
	}
	binding("<C-y>")()
	assert(
		copied().value == "/home/pl/cue/palekiwi/palekiwi/demo/spec/index.md",
		"one pathless row must not sink the pathed one"
	)
end)

check("a multi copy where every entry is skipped reports and copies nothing", function()
	open_picker("demo")
	attach()
	state.multi = { { value = { context = "demo" } } }
	binding("<C-h>")()
	assert(#state.registers == 0, "nothing addressable, nothing copied")
	assert(last_notify() ~= nil and last_notify().level == vim.log.levels.WARN, "the miss is reported")
	assert(state.closed == 0, "a failed copy keeps the picker open")
end)

check("multi C-h copies still resolve the scope once per picker", function()
	open_picker("demo")
	attach()
	state.multi = { { value = artifact("spec", "index.md", "Spec") } }
	binding("<C-h>")()
	assert(status_calls() == 1, "the first copy resolves the scope")
	state.registers = {}
	state.multi = {
		{ value = artifact("spec", "index.md", "Spec") },
		{ value = artifact("task", "multi.md") },
	}
	binding("<C-h>", "n")()
	assert(status_calls() == 1, "a second multi copy must reuse the resolved scope")
	assert(#state.registers == 1, "one register write for the batch")
end)

-- ─── empty and error cases ────────────────────────────────────────────

check("notifies instead of opening an empty picker", function()
	open_picker("demo", nil, { decoded = {} })
	assert(not state.picker_opts, "an empty context must not open a picker")
	assert(last_notify() ~= nil and last_notify().level == vim.log.levels.INFO, "empty result is informational")
	assert(last_notify().message:find("demo", 1, true), "the notification should name the context")
end)

check("opens for a context holding only bin and tmp artifacts", function()
	open_picker("demo", nil, {
		decoded = { artifact("bin", "run.sh"), artifact("tmp", "legacy.diff") },
	})
	assert(state.picker_opts, "bin/tmp-only contexts must still open a picker")
	assert(#rows() == 2, "both rows must be listed")
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
