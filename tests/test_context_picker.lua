package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua"

local state
local function reset()
	state = {
		commands = {},
		maps = {},
		rows = {
			{
				context = "demo",
				scope = "org/repo",
				title = "Demo",
				path = "/store/demo%.md",
				mode = "build",
				kind = "work",
			},
			{ context = "demo", scope = "other/repo", path = "/store/other.md" },
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
	notify = function(msg)
		table.insert(state.notices, msg)
	end,
	fn = {
		fnameescape = function(s)
			return "escaped:" .. s
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
					opts.attach_mappings(1, function(_, key, fn)
						state.maps[key] = fn
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
assert(#cells == 6 and #state.columns == 6)
assert(cells[1][1] == "*" and cells[1][2] == "CueMarkerActive")
assert(cells[2][1] == "BUILD" and cells[2][2] == "CueModeBuild")
assert(cells[3][1] == "Demo")
assert(cells[4][1] == "—")
assert(cells[5][1] == "work" and cells[5][2] == "CueKindWork")
assert(cells[6][1] == "org/repo/demo")
assert(state.selected.ordinal:find("build work", 1, true))
assert(state.columns[3].width == 70 and state.columns[6].remaining)
state.enter()
assert(state.edited == "escaped:/store/demo%.md")

local browsed
picker.pick_context_artifacts = function(ctx, opts)
	browsed = { ctx, opts }
end
state.maps["<C-e>"]()
assert(browsed[1] == "demo" and browsed[2].dir == "/repo")
state.maps["<C-s>"]()
assert(argv(state.commands[#state.commands]) == "cue context switch -C /repo --store /store demo")
select(2)
cells = state.selected:display()
assert(cells[1][1] == " ")
assert(cells[2][1] == "—" and cells[5][1] == "—")
assert(cells[3][1] == "demo")
local n = #state.commands
browsed = nil
state.maps["<C-e>"]()
state.maps["<C-s>"]()
assert(not browsed and #state.commands == n and #state.notices >= 2)
state.maps["<A-s>"]()
assert(argv(state.commands[n + 1]) == "cue context pin other/repo/demo -C /repo --store /store")
assert(state.refreshed and state.refresh_opts.reset_prompt == false)

reset()
picker.pick_contexts({ pinned = true })
assert(argv(state.commands[1]) == "cue context list --json --pinned --sort recency")
select(1)
assert(state.selected:display()[6][1] == "demo")
state.rows = {}
state.maps["<A-s>"]()
assert(argv(state.commands[3]) == "cue context unpin org/repo/demo")
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
n = #state.commands
state.maps["<C-s>"]()
state.maps["<C-e>"]()
assert(#state.commands == n)
reset()
picker.pick_contexts()
select(1)
state.fail = true
state.maps["<A-s>"]()
assert(not state.refreshed and #state.notices > 0)
print("context picker tests passed")
