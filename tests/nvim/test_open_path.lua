-- End-to-end test for the context artifact picker's Enter action, run in a
-- REAL headless Neovim (the pure-Lua tests stub `vim`, so they cannot catch
-- Ex-command argument expansion).
--
-- Run: nvim --clean --headless -l tests/nvim/test_open_path.lua
--
-- Regression under test: `:edit {file}` expands `%` to the current file name
-- and `#` to the alternate file name, and splits on unescaped spaces. Passing
-- a raw artifact path therefore opens the WRONG file:
--
--   :edit /tmp/a b.md          -- sets % and #
--   :edit /tmp/a%b.md          -- actually opens /tmp/a/tmp/a b.mdb.md
--
-- vim.fn.fnameescape() is the fix. This test drives the real picker action
-- over real files whose names contain `%`, `#` and spaces, and asserts the
-- buffer that ends up loaded is the intended one, by name AND by content.
--
-- Telescope is stubbed (it is not a dependency of the test environment); the
-- `vim` API, the `:edit` call and the filesystem are real.

local repo = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")
package.path = package.path .. ";" .. repo .. "/lua/?.lua;" .. repo .. "/lua/?/init.lua"

-- ─── telescope stubs ──────────────────────────────────────────────────

local captured = { picker_opts = nil, closed = 0, selected = nil, select_default = nil }

package.preload["telescope.pickers"] = function()
	return {
		new = function(_, opts)
			captured.picker_opts = opts
			return {
				find = function() end,
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
			captured.closed = captured.closed + 1
		end,
		select_default = {
			replace = function(_, fn)
				captured.select_default = fn
			end,
		},
	}
end

package.preload["telescope.actions.state"] = function()
	return {
		get_selected_entry = function()
			return captured.selected
		end,
		get_current_picker = function(_)
			return nil
		end,
	}
end

package.preload["telescope.pickers.entry_display"] = function()
	return {
		create = function(_)
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

local picker = require("cue.picker")

-- ─── fixture: real files with hostile names ───────────────────────────

local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp .. "/note", "p")

-- name -> file content (the content proves WHICH file got loaded)
local files = {
	["plain.md"] = "plain-content",
	["a%b.md"] = "percent-content",
	["c#d.md"] = "hash-content",
	["with space.md"] = "space-content",
	["all %#and space.md"] = "everything-content",
}

local artifacts = {}
for name, content in pairs(files) do
	local path = tmp .. "/note/" .. name
	vim.fn.writefile({ content }, path)
	table.insert(artifacts, {
		path = path,
		name = name,
		context = "demo",
		type = "note",
		frontmatter = vim.NIL,
	})
end
table.sort(artifacts, function(a, b)
	return a.name < b.name
end)

-- Stub only the CLI boundary: `cue list` returns the fixture as real JSON,
-- decoded by the real vim.json. `cue status` returns the active context "demo".
local payload = vim.json.encode(artifacts)
local status_payload = vim.json.encode({ context = "demo", scope = "palekiwi/palekiwi" })
vim.system = function(cmd, _)
	return {
		wait = function()
			if cmd[2] == "status" then
				return { code = 0, stdout = status_payload, stderr = "" }
			end
			return { code = 0, stdout = payload, stderr = "" }
		end,
	}
end

local notifications = {}
vim.notify = function(msg, level)
	table.insert(notifications, { message = msg, level = level })
end

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

--- Open the picker and install its Enter action.
local function open_picker()
	captured.picker_opts = nil
	captured.select_default = nil
	captured.closed = 0
	picker.pick_context_artifacts("demo", { dir = repo })
	assert(captured.picker_opts, "the picker did not open")
	captured.picker_opts.attach_mappings(1, function() end)
	assert(type(captured.select_default) == "function", "Enter was not remapped")
end

--- Press Enter on the row whose artifact filename is `name`.
local function press_enter_on(name)
	local entry
	for _, row in ipairs(captured.picker_opts.finder.results) do
		if row.name == name then
			entry = captured.picker_opts.finder.entry_maker(row)
			break
		end
	end
	assert(entry, "no row for " .. name)
	captured.selected = entry
	captured.select_default()
	return entry
end

local function current_buffer_name()
	return vim.api.nvim_buf_get_name(0)
end

local function current_buffer_first_line()
	local lines = vim.api.nvim_buf_get_lines(0, 0, 1, false)
	return lines[1] or ""
end

-- ─── tests ────────────────────────────────────────────────────────────

check("all fixture rows reach the picker", function()
	open_picker()
	local count = #captured.picker_opts.finder.results
	assert(count == 5, "expected 5 rows, got " .. count)
end)

check("pick_active_context_artifacts opens picker for the active context", function()
	captured.picker_opts = nil
	picker.pick_active_context_artifacts({ dir = repo })
	assert(captured.picker_opts, "the picker did not open via pick_active_context_artifacts")
	assert(captured.picker_opts.prompt_title:find("demo", 1, true), "prompt title must name demo")
end)

for _, name in ipairs({ "a%b.md", "c#d.md", "with space.md", "all %#and space.md" }) do
	check(string.format("enter opens %q, not a %%/#-expanded path", name), function()
		open_picker()

		-- Load a DIFFERENT file first so `%` (current) and `#` (alternate)
		-- both have values: this is what turns the bug into a wrong buffer
		-- rather than a harmless no-op.
		press_enter_on("plain.md")
		assert(current_buffer_first_line() == "plain-content", "fixture setup failed")

		local entry = press_enter_on(name)

		assert(
			current_buffer_name() == entry.path,
			string.format("opened %q, expected %q", current_buffer_name(), entry.path)
		)
		assert(
			current_buffer_first_line() == files[name],
			string.format("buffer content %q, expected %q", current_buffer_first_line(), files[name])
		)
		assert(vim.fn.filereadable(current_buffer_name()) == 1, "the opened buffer must be an existing file")
	end)
end

check("enter never creates a stray buffer for an expanded path", function()
	-- The bug manifested as a NEW, empty, unwritten buffer whose name was the
	-- expanded nonsense path. Nothing outside the fixture may be loaded.
	local allowed = {}
	for name in pairs(files) do
		allowed[tmp .. "/note/" .. name] = true
	end

	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		local bufname = vim.api.nvim_buf_get_name(buf)
		if bufname ~= "" then
			assert(allowed[bufname], "unexpected buffer was opened: " .. bufname)
		end
	end
end)

vim.fn.delete(tmp, "rf")

if failures == 0 then
	print("\nAll tests passed.")
else
	print(string.format("\n%d test(s) FAILED.", failures))
	vim.cmd("cquit 1")
end
