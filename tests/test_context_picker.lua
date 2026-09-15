package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua"

local state
local function reset()
	state = {
		commands = {},
		maps = {},
		bindings = {},
		registers = {},
		multi = {}, -- the picker's multi-selection (<Tab> toggles)
		rows = {
			{
				context = "demo",
				scope = "org/repo",
				title = "Demo",
				path = "/store/demo%.md",
				mode = "build",
				kind = "work",
				pinned = true,
			},
			{ context = "demo", scope = "other/repo", path = "/store/other.md", pinned = false },
		},
		status = { context = "demo", scope = "org/repo" },
		notices = {},
	}
end
reset()
vim = { -- luacheck: ignore
	NIL = {},
	log = { levels = { ERROR = 1, WARN = 2, INFO = 3 } },
	trim = function(s)
		return s:match("^%s*(.-)%s*$")
	end,
	notify = function(msg, level)
		table.insert(state.notices, { message = msg, level = level })
	end,
	fn = {
		fnameescape = function(s)
			return "escaped:" .. s
		end,
		setreg = function(name, value)
			table.insert(state.registers, { name = name, value = value })
		end,
	},
	cmd = {
		edit = function(s)
			state.edited = s
		end,
	},
	json = {
		decode = function(s)
			if state.bad_json then
				error("bad json")
			end
			return s == "status" and state.status or state.rows
		end,
	},
	system = function(cmd)
		table.insert(state.commands, cmd)
		return {
			wait = function()
				return {
					code = state.fail and 1 or 0,
					stderr = "failed",
					stdout = cmd[2] == "status" and "status" or "rows",
				}
			end,
		}
	end,
}
package.preload["telescope.pickers"] = function()
	return {
		new = function(_, opts)
			state.picker = opts
			return {
				find = function()
					opts.attach_mappings(1, function(mode, key, fn)
						state.maps[key] = fn
						table.insert(state.bindings, { mode = mode, lhs = key })
					end)
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
			generic_sorter = function()
				return "sorter"
			end,
			file_previewer = function()
				return "preview"
			end,
		},
	}
end
package.preload["telescope.actions"] = function()
	return {
		select_default = {
			replace = function(_, fn)
				state.enter = fn
			end,
		},
		close = function()
			state.closed = true
		end,
	}
end
package.preload["telescope.actions.state"] = function()
	return {
		get_selected_entry = function()
			return state.selected
		end,
		get_current_picker = function()
			return {
				refresh = function(_, finder, opts)
					state.refreshed = finder
					state.refresh_opts = opts
				end,
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
			state.columns = opts.items
			return function(cells)
				return cells
			end
		end,
	}
end
package.preload["telescope.make_entry"] = function()
	return {
		set_default_entry_mt = function(entry)
			return entry
		end,
	}
end

local core = require("cue.core")
local picker = require("cue.picker")
local function argv(cmd)
	return table.concat(cmd, " ")
end
assert(argv(core.list_contexts_argv({ pinned = true })) == "cue context list --pinned")
assert(argv(core.list_contexts_argv({ pinned = false })) == "cue context list")
assert(argv(core.list_contexts_argv({ pinned = "true" })) == "cue context list")
assert(type(require("cue").pick_contexts) == "function")

local TACK = "\239\130\141" -- U+F08D nf-fa-thumb_tack

local function select(i)
	state.selected = state.picker.finder.entry_maker(state.rows[i])
end
picker.pick_contexts({ scope = "store", dir = "/repo", store = "/store", limit = 5 })
assert(
	argv(state.commands[1]) == "cue context list --json --scope store --sort recency --limit 5 -C /repo --store /store"
)
assert(state.picker.previewer == "preview")
assert(state.picker.layout_strategy == "vertical")
assert(state.picker.layout_config.mirror == true)
assert(state.picker.layout_config.preview_height == 0.5)
assert(state.picker.layout_config.prompt_position == "top")
assert(state.picker.finder.results[1] == state.rows[1])
assert(state.picker.tiebreak() == false)
select(1)
assert(state.selected.ordinal:find("org/repo/demo", 1, true))
local cells = state.selected:display()
-- Column order: pin marker, title, mode, activity, kind, slug.
assert(#cells == 6 and #state.columns == 6)
-- The active row is pinned (activation pins), and the marker column takes
-- the active colour there.
assert(cells[1][1] == TACK and cells[1][2] == "CueMarkerActive")
-- Active is signalled by the TITLE colour, not by a `*` glyph.
assert(cells[2][1] == "Demo" and cells[2][2] == "CueMarkerActive")
assert(cells[3][1] == "BUILD" and cells[3][2] == "CueModeBuild")
assert(cells[4][1] == "—")
assert(cells[5][1] == "work" and cells[5][2] == "CueKindWork")
assert(cells[6][1] == "org/repo/demo")
assert(state.selected.ordinal:find("build work", 1, true))
assert(state.columns[1].width == 1, "the marker column holds the pin tack alone")
assert(state.columns[2].width == 45 and state.columns[6].remaining)
state.enter()
assert(state.edited == "escaped:/store/demo%.md")

local browsed
picker.pick_context_artifacts = function(ctx, opts)
	browsed = { ctx, opts }
end
state.maps["<C-e>"]()
assert(browsed[1] == "demo" and browsed[2].dir == "/repo")
-- Activation pins FIRST, so a failed pin cannot leave an unpinned context
-- active on the branch.
local n = #state.commands
state.maps["<C-s>"]()
assert(argv(state.commands[n + 1]) == "cue context pin org/repo/demo -C /repo --store /store")
assert(argv(state.commands[n + 2]) == "cue context switch -C /repo --store /store demo")
assert(#state.commands == n + 2)
select(2)
cells = state.selected:display()
assert(cells[1][1] == " " and cells[1][2] == "TelescopeResultsComment")
assert(cells[2][1] == "demo" and cells[2][2] == "TelescopeResultsNormal")
assert(cells[3][1] == "—" and cells[5][1] == "—")
n = #state.commands
browsed = nil
state.maps["<C-e>"]()
state.maps["<C-s>"]()
assert(not browsed and #state.commands == n and #state.notices >= 2)
state.maps["<A-s>"]()
assert(argv(state.commands[n + 1]) == "cue context pin other/repo/demo -C /repo --store /store")
assert(state.refreshed and state.refresh_opts.reset_prompt == false)

-- ─── <C-h> copies the selected context's canonical address ───────────────
-- The address is <scope>/<context>: what cue accepts on the command line and
-- in parent:/refs: frontmatter, built by the same helper pin and activate
-- already address rows with. Never the store path.
local function bound(lhs, mode)
	for _, b in ipairs(state.bindings) do
		if b.lhs == lhs and b.mode == mode then
			return true
		end
	end
	return false
end
local function copied()
	assert(#state.registers == 1, "a copy writes exactly one register, got " .. #state.registers)
	return state.registers[1]
end
local function last_notice()
	return state.notices[#state.notices]
end
assert(bound("<C-h>", "i") and bound("<C-h>", "n"), "<C-h> must be bound in insert and normal mode")
state.closed = nil -- the activation above closed the picker; watch this block's own closes
select(1)
state.registers = {}
n = #state.commands
state.maps["<C-h>"]()
assert(copied().name == "+", "the system clipboard is register +, got " .. tostring(copied().name))
assert(copied().value == "org/repo/demo", "expected the canonical address, got " .. tostring(copied().value))
assert(copied().value:sub(1, 1) ~= "/", "an address is never an absolute path")
assert(#state.commands == n, "the row already carries its scope; copying runs no CLI call")
assert(not state.closed, "copying keeps the picker open")
-- A foreign row IS addressable: an address names its own scope, so unlike
-- browsing and activation it needs no agreement with the current repository.
select(2)
state.registers = {}
state.maps["<C-h>"]()
assert(copied().value == "other/repo/demo", "a foreign row addresses its own scope, got " .. tostring(copied().value))
-- A scopeless row has no address. A partial one is never copied: it would
-- paste cleanly and resolve to nothing.
state.selected = state.picker.finder.entry_maker({ context = "orphan", path = "/store/orphan.md" })
state.registers = {}
local notices = #state.notices
state.maps["<C-h>"]()
assert(#state.registers == 0, "a scopeless row must not be addressed")
assert(#state.notices == notices + 1 and last_notice().level == vim.log.levels.WARN, "the miss is a warning")
state.selected = nil
notices = #state.notices
state.maps["<C-h>"]()
assert(#state.registers == 0, "no selection, no copy")
assert(#state.notices == notices + 1 and last_notice().level == vim.log.levels.WARN, "the miss is a warning")
assert(not state.closed, "a failed copy keeps the picker open")

-- ─── <C-h> honors <Tab> multi-selection ────────────────────────────────────
-- Every toggled context's address is copied space-joined in ONE register
-- write, the same contract the artifact picker's yanks restored from
-- master. The merely highlighted row does not contribute.
state.selected = state.picker.finder.entry_maker({ context = "highlighted", scope = "some/repo" })
state.multi = {
	state.picker.finder.entry_maker(state.rows[1]),
	state.picker.finder.entry_maker(state.rows[2]),
}
state.registers = {}
n = #state.commands
state.maps["<C-h>"]()
assert(copied().value == "org/repo/demo other/repo/demo", "got " .. tostring(copied().value))
assert(not copied().value:find("highlighted", 1, true), "the merely highlighted row must not contribute")
assert(#state.commands == n, "multi copying still runs no CLI call")
assert(not state.closed, "multi copying keeps the picker open")
assert(last_notice().message:find("2 items", 1, true), "the notification reports the count, not every address")
-- A scopeless row among the toggles is skipped, not fatal.
state.multi = {
	state.picker.finder.entry_maker(state.rows[1]),
	state.picker.finder.entry_maker({ context = "orphan", path = "/store/orphan.md" }),
}
state.registers = {}
state.maps["<C-h>"]()
assert(copied().value == "org/repo/demo", "a scopeless toggle must not sink the addressable one")
-- Every toggle scopeless: nothing copied, the miss reported.
state.multi = { state.picker.finder.entry_maker({ context = "orphan", path = "/store/orphan.md" }) }
state.registers = {}
notices = #state.notices
state.maps["<C-h>"]()
assert(#state.registers == 0, "nothing addressable, nothing copied")
assert(#state.notices == notices + 1 and last_notice().level == vim.log.levels.WARN, "the miss is a warning")

reset()
picker.pick_contexts({ pinned = true })
assert(argv(state.commands[1]) == "cue context list --json --pinned --sort recency")
select(1)
assert(state.selected:display()[6][1] == "demo")
-- The active context stays pinned: unpinning it would drop the branch's own
-- context out of the working set.
n = #state.commands
state.maps["<A-s>"]()
assert(#state.commands == n and #state.notices > 0)
select(2)
state.rows = {}
state.maps["<A-s>"]()
assert(argv(state.commands[n + 1]) == "cue context unpin other/repo/demo")
assert(#state.refreshed.results == 0)
state.selected = nil
n = #state.commands
state.enter()
state.maps["<C-e>"]()
state.maps["<C-s>"]()
state.maps["<A-s>"]()
assert(#state.commands == n)

reset()
state.fail = true
picker.pick_contexts()
assert(not state.picker and #state.notices > 0)
reset()
state.bad_json = true
picker.pick_contexts()
assert(not state.picker and #state.notices > 0)
reset()
state.rows = {}
picker.pick_contexts()
assert(not state.picker and #state.notices > 0)
reset()
state.status = {}
picker.pick_contexts({ scope = "store" })
select(1)
-- No active context: the tack still marks the pinned row, in its own colour,
-- and the title stays a plain result.
cells = state.selected:display()
assert(cells[1][1] == TACK and cells[1][2] == "CueMarkerPinned")
assert(cells[2][2] == "TelescopeResultsNormal")
n = #state.commands
state.maps["<C-s>"]()
state.maps["<C-e>"]()
assert(#state.commands == n)
-- Addressing is unaffected by either: the repo view lists the same rows, and
-- scope is a property of the row rather than of the branch's association.
state.registers = {}
state.maps["<C-h>"]()
assert(copied().value == "org/repo/demo", "got " .. tostring(copied().value))
reset()
picker.pick_contexts()
select(1)
state.registers = {}
state.maps["<C-h>"]()
assert(copied().value == "org/repo/demo", "the repo view copies the same address, got " .. tostring(copied().value))
reset()
picker.pick_contexts()
select(1)
state.fail = true
state.maps["<A-s>"]()
assert(not state.refreshed and #state.notices > 0)
-- A failed pin aborts activation: the switch never runs.
reset()
picker.pick_contexts()
select(1)
state.fail = true
n = #state.commands
state.maps["<C-s>"]()
assert(#state.commands == n + 1 and #state.notices > 0)
print("context picker tests passed")
