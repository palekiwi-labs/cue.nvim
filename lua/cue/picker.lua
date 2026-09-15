--- Telescope pickers for cue artifacts
local M = {}

local config = require("cue.config")
local core = require("cue.core")

local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local entry_display = require("telescope.pickers.entry_display")
local make_entry = require("telescope.make_entry")

-- ─── Private helpers ──────────────────────────────────────────────────────────

--- Format the type badge for display. Sparse label map first (review maps
--- to REV: the badge column is five cells and "REVIEW" truncates), then the
--- uppercased type name, so a type cue adds later badges itself with no
--- plugin change.
---@param category string
---@return string
local function format_category(category)
	return config.TYPE_BADGES[category] or string.upper(category)
end

--- Return the highlight group for a category badge
---@param category string
---@return string
local function get_category_highlight(category)
	return config.category_highlights[category] or "TelescopeResultsNormal"
end

-- ─── Context artifact picker ──────────────────────────────────────────────────

--- Fetch ONE explicit context's artifacts via `cue list --context`.
--- Returns nil (after notifying) on a missing context, a failed CLI call or
--- an unparseable payload.
---@param context string  normalised context slug
---@param opts table|nil  supports: dir, store
---@return table|nil
local function get_context_artifacts(context, opts)
	local cmd = core.context_artifacts_argv(context, opts)
	if not cmd then
		return nil
	end

	local output, err = core.execute_command(cmd)
	if not output or output == "" then
		vim.notify("Error fetching cue artifacts: " .. (err or "no output"), vim.log.levels.ERROR)
		return nil
	end

	local artifacts, parse_err = core.parse_json(output)
	if type(artifacts) ~= "table" then
		vim.notify("Error parsing cue data: " .. (parse_err or "unexpected payload"), vim.log.levels.ERROR)
		return nil
	end

	return artifacts
end

--- Put a value on the system clipboard and say so.
---
--- Register `+` only: it is the SYSTEM clipboard, which is what a copied
--- path or address is wanted for (pasting into a shell, a message, another
--- editor). The unnamed register is left alone so copying from a picker does
--- not clobber whatever the operator last yanked in the buffer they came
--- from.
---
--- The value is echoed in the notification: a copy is invisible otherwise,
--- and seeing it is how a wrong selection is caught before it is pasted.
---@param label string  what was copied, for the notification
---@param value string  the text placed on the clipboard
local function copy_to_clipboard(label, value)
	vim.fn.setreg("+", value)
	vim.notify("Cue: copied " .. label .. ": " .. value, vim.log.levels.INFO)
end

--- The entries a copy action acts on when the operator has toggled a
--- multi-selection (`<Tab>`): every toggled entry. An empty table when
--- none are toggled -- the caller then falls back to the highlighted
--- entry, which is the single-selection contract the pickers honor.
---
--- Nil-safe against a missing picker, as master's helper was: a copy
--- must never crash over how action_state answers.
---@param prompt_bufnr integer
---@return table
local function multi_selection(prompt_bufnr)
	local current = action_state.get_current_picker(prompt_bufnr)
	local multi = current and current:get_multi_selection() or {}
	return multi
end

--- Copy one value per entry, space-joined, in a single register write:
--- the multi-selection contract master's copy actions honored.
---
--- Entries whose getter returns nil, "" or vim.NIL are silently skipped --
--- one unaddressable row among five must not sink the other four. When
--- every entry is skipped the miss is reported and nothing is copied.
---
--- The notification reports the item count rather than echoing every
--- value: several store-long paths in one notification are noise, and the
--- register holds the truth for inspection anyway.
---@param entries table  the multi-selected entries
---@param getter function  receives an entry, returns its value or nil
---@param label string
local function copy_values(entries, getter, label)
	local values = {}
	for _, e in ipairs(entries) do
		local v = getter(e)
		if v and v ~= "" and v ~= vim.NIL then
			table.insert(values, tostring(v))
		end
	end

	if #values == 0 then
		vim.notify("Cue: nothing to copy for " .. label, vim.log.levels.WARN)
		return
	end

	local joined = table.concat(values, " ")
	vim.fn.setreg("+", joined)
	if #values == 1 then
		vim.notify("Cue: copied " .. label .. ": " .. joined, vim.log.levels.INFO)
	else
		vim.notify("Cue: copied " .. label .. " (" .. #values .. " items)", vim.log.levels.INFO)
	end
end

--- The Jira-style priority caret for an artifact row, as a (glyph, highlight)
--- pair. Only critical and high are flagged: normal is the norm and low is
--- rare clutter, so both render blank and the column reads as a flag rather
--- than a fourth colour (operator decision 2026-08-22, carried over from the
--- retired task picker).
---
--- bin and tmp rows carry no frontmatter at all, so they always fall through
--- to the blank caret.
---@param frontmatter table|nil
---@return string, string
local function priority_caret(frontmatter)
	if type(frontmatter) ~= "table" or frontmatter == vim.NIL then
		return "", "TelescopeResultsNormal"
	end
	local priority = frontmatter.priority
	if type(priority) ~= "string" or priority == "" then
		return "", "TelescopeResultsNormal"
	end
	priority = priority:lower()
	local glyph = config.PRIORITY_GLYPH[priority]
	if not glyph then
		return "", "TelescopeResultsNormal"
	end
	return glyph, config.priority_highlights[priority] or "TelescopeResultsNormal"
end

--- Entry maker for the context artifact picker: a type badge, the priority
--- caret, the displayed title (frontmatter title, else filename) and the
--- creation age. The ordinal indexes the type, the title and the filename,
--- so the single list stays searchable across groups.
---
--- Every column is a fixed width, including the title: the age is a fixed
--- four cells that follows the title rather than the right edge of the
--- pane, which is what a `{ remaining = true }` title would have done. The
--- window is wide (95% of the editor), so a flexible title would push the
--- age column to the far edge of an ultrawide terminal and leave the row
--- reading as two unrelated halves. 72 cells is wide enough for the titles
--- cue artifacts actually carry and keeps the age beside them.
---@param opts table|nil
---@param now number  Unix seconds, sampled once when the picker is built
---@return function
local function make_context_artifact_entry_maker(opts, now)
	opts = opts or {}

	local displayer = entry_display.create({
		separator = " ",
		items = {
			{ width = 5 }, -- artifact type badge
			{ width = 1 }, -- priority caret (critical/high only)
			{ width = 72 }, -- title, falling back to the filename
			-- creation age, right justified within its own column. Four cells is
			-- the widest value core.relative_age can return ("364d").
			{ width = 4, right_justify = true },
		},
	})

	local make_display = function(entry)
		local dim = core.artifact_finished(entry.value) and "CueStatusComplete" or nil
		local caret, caret_hl = priority_caret(entry.frontmatter)
		return displayer({
			{ format_category(entry.category), dim or get_category_highlight(entry.category) },
			{ caret, dim or caret_hl },
			{ entry.title, dim or "TelescopeResultsNormal" },
			{ core.artifact_created_age(entry.value, now), dim or "TelescopeResultsComment" },
		})
	end

	return function(artifact)
		if not artifact or not artifact.path then
			return nil
		end

		local title = core.artifact_display_title(artifact)

		return make_entry.set_default_entry_mt({
			value = artifact,
			display = make_display,
			ordinal = string.format("%s %s %s", artifact.type or "", title, artifact.name or ""),
			path = artifact.path,
			title = title,
			name = artifact.name,
			context = artifact.context,
			category = artifact.type,
			frontmatter = artifact.frontmatter,
		}, opts)
	end
end

--- Browse ONE context's artifacts as a single searchable list, grouped by
--- type (task, spec, plan, note, trace). Within each group, unfinished comes
--- first, complete/closed last; each section is newest-created first.
---
--- Browsing is not activation: the context must be passed explicitly, the
--- picker never falls back to the active context, and Enter opens the
--- selected file WITHOUT switching context. Creation stays outside the
--- picker, so no actions beyond Enter are mapped.
---
---@param context string  context slug (required; no active-context fallback)
---@param opts table|nil  supports: dir (repository dir, `cue -C`),
---                       store (store root, `cue --store`)
function M.pick_context_artifacts(context, opts)
	opts = opts or {}

	local ctx = core.normalize_context(context)
	if not ctx then
		vim.notify("Error: pick_context_artifacts requires an explicit context slug", vim.log.levels.ERROR)
		return
	end

	local artifacts = get_context_artifacts(ctx, opts)
	if not artifacts then
		return
	end

	local rows = core.context_artifacts_view(artifacts)
	if #rows == 0 then
		vim.notify("No cue artifacts in context: " .. ctx, vim.log.levels.INFO)
		return
	end

	-- One clock read for the whole list: every row's age is measured against
	-- the same instant, so the column is internally consistent and a long
	-- list does not pay for a syscall per row.
	local now = os.time()

	-- The repository scope behind the canonical address (<C-h>), resolved at
	-- most once per picker and only if it is asked for.
	--
	-- Lazy, because opening the picker is the common path and copying an
	-- address is the rare one: eagerly shelling out to `cue status` would add
	-- a subprocess to every open to serve a keystroke most opens never see.
	-- Memoised on success, so holding <C-h> down does not spawn a process per
	-- press; a failure is not cached, so a transient one can be retried.
	local scope = nil
	local function resolve_scope()
		if scope then
			return scope
		end
		-- The SAME dir/store the artifacts were listed with. Scope follows the
		-- repository, so a status query aimed anywhere else would answer about
		-- a different one -- which is also why the cwd is not consulted.
		local _, status, err = core.get_active_context(opts)
		scope = core.status_scope(status)
		if not scope then
			vim.notify(
				"Cue: cannot resolve the repository scope for a canonical address: "
					.. (err or "cue status reported none"),
				vim.log.levels.ERROR
			)
		end
		return scope
	end

	pickers
		.new({}, {
			prompt_title = "Cue Artifacts (" .. ctx .. ")",
			layout_strategy = "vertical",
			-- 0.95 is a percentage: Telescope reads a layout width below 1 as a
			-- share of the editor. The window is deliberately near-fullscreen --
			-- the preview below the results needs the height, and the results row
			-- is fixed-width, so the extra columns go to the preview rather than
			-- stretching the row.
			layout_config = {
				width = 0.95,
				mirror = true,
				prompt_position = "top",
				preview_height = 0.5,
			},
			finder = finders.new_table({
				results = rows,
				entry_maker = make_context_artifact_entry_maker(opts, now),
			}),
			sorter = conf.generic_sorter({}),
			previewer = conf.file_previewer({}),
			-- Keep the grouped order. Telescope's fzy sorter scores every entry 1
			-- for an empty prompt, and the entry manager appends equal scores, so
			-- insertion order already survives an empty query; but for a non-empty
			-- prompt the DEFAULT tiebreak re-sorts equal scores by ordinal length,
			-- which would scramble the groups. Returning false never inserts an
			-- entry ahead of an equally scored one, so ties keep finder order.
			tiebreak = function()
				return false
			end,
			attach_mappings = function(prompt_bufnr, map)
				-- Enter opens the file. No activation: consulting a context must not
				-- change the active one.
				--
				-- fnameescape is mandatory: `:edit` expands `%` to the current file
				-- name and `#` to the alternate one, so a raw path silently opens the
				-- WRONG file (an artifact named `a%b.md` opened `a<current-file>b.md`).
				-- Escaping also protects spaces and other special characters. Verified
				-- end to end in headless Neovim (tests/nvim/test_open_path.lua).
				actions.select_default:replace(function()
					actions.close(prompt_bufnr)
					local entry = action_state.get_selected_entry()
					if entry and entry.path then
						vim.cmd.edit(vim.fn.fnameescape(entry.path))
					end
				end)

				-- Both yanks leave the picker OPEN. Copying is a lookup, not a
				-- destination: the list is usually consulted for several rows in a
				-- row, and closing would make each one cost a reopen.
				--
				-- Both honor <Tab> multi-selection, as master's copy actions did:
				-- toggled rows are copied space-joined in one register write, and
				-- the highlighted row alone is copied when nothing is toggled.
				local function copy_path()
					local multi = multi_selection(prompt_bufnr)
					if next(multi) ~= nil then
						copy_values(multi, function(e)
							return e.path
						end, "path")
						return
					end
					local entry = action_state.get_selected_entry()
					if not entry or type(entry.path) ~= "string" or entry.path == "" then
						vim.notify("Cue: no artifact selected to copy a path from", vim.log.levels.WARN)
						return
					end
					copy_to_clipboard("path", entry.path)
				end

				--- Copy the canonical address `<scope>/<context>/<type>/<name>`: what
				--- cue accepts in `parent:`/`refs:` frontmatter and on the command
				--- line, and what another agent or repository can resolve.
				---
				--- Never the absolute store path -- that is what <C-y> is for, and an
				--- absolute path is meaningless to anyone whose store lives elsewhere.
				--- If the scope or the row's metadata cannot supply a real address,
				--- nothing is copied: a plausible-looking wrong address is worse than
				--- none, because it pastes cleanly and resolves to nothing.
				local function copy_address()
					local multi = multi_selection(prompt_bufnr)
					if next(multi) ~= nil then
						-- The scope resolves once for the whole batch; a failure has
						-- already been reported and aborts the copy.
						local repo = resolve_scope()
						if not repo then
							return
						end
						copy_values(multi, function(e)
							return core.artifact_address(repo, e.value, ctx)
						end, "address")
						return
					end
					local entry = action_state.get_selected_entry()
					if not entry then
						vim.notify("Cue: no artifact selected to copy an address from", vim.log.levels.WARN)
						return
					end
					local repo = resolve_scope()
					if not repo then
						return
					end
					local address = core.artifact_address(repo, entry.value, ctx)
					if not address then
						vim.notify(
							"Cue: the selected row carries no context/type/name to address",
							vim.log.levels.ERROR
						)
						return
					end
					copy_to_clipboard("address", address)
				end

				for _, mode in ipairs({ "i", "n" }) do
					map(mode, "<C-y>", copy_path)
					map(mode, "<C-h>", copy_address)
				end
				return true
			end,
		})
		:find()
end

--- Browse the active context's artifacts using the context artifact picker (<C-s>).
---
--- Resolves the active context via `cue status --json`. When a context is
--- active, opens `pick_context_artifacts(context, opts)`. When no context is
--- active (or on error), notifies the user without opening a picker.
---
---@param opts table|nil  supports: dir (`cue -C`), store (`cue --store`)
function M.pick_active_context_artifacts(opts)
	opts = opts or {}
	local ctx, _, err = core.get_active_context(opts)
	if not ctx then
		if err then
			vim.notify("Error resolving active context: " .. err, vim.log.levels.ERROR)
		else
			vim.notify("No active cue context", vim.log.levels.WARN)
		end
		return
	end
	return M.pick_context_artifacts(ctx, opts)
end

--- Browse all or pinned contexts, preserving cue's recency order.
---
--- A-s stays view-scoped rather than a state-aware toggle: it pins in the
--- full view and unpins in the pinned view. `pinned` on every row is read
--- for the indicator column and for the guard that keeps the active context
--- pinned; it does not choose the operation.
---
--- Activation pins first, so a failed pin cannot leave the branch on a
--- context the pinned view will not show.
---
--- Foreign scopes may be opened, pinned and unpinned, but artifact browsing
--- and branch activation require the current repo.
function M.pick_contexts(opts)
	opts = opts or {}
	local query = {
		json = true,
		pinned = opts.pinned,
		scope = opts.scope,
		sort = opts.sort or "recency",
		limit = opts.limit,
		dir = opts.dir,
		store = opts.store,
	}
	local function fetch()
		local output, err = core.execute_command(core.list_contexts_argv(query))
		if not output or output == "" then
			vim.notify("Error fetching cue contexts: " .. (err or "no output"), vim.log.levels.ERROR)
			return nil
		end
		local decoded, parse_err = core.parse_json(output)
		if type(decoded) ~= "table" then
			vim.notify("Error parsing cue contexts: " .. (parse_err or "unexpected payload"), vim.log.levels.ERROR)
			return nil
		end
		return core.context_list_view(decoded)
	end
	local rows = fetch()
	if not rows then
		return
	end
	if #rows == 0 then
		vim.notify("No cue contexts" .. (opts.pinned == true and " pinned" or ""), vim.log.levels.INFO)
		return
	end

	local _, status = core.get_active_context(opts)
	local function address(row)
		if type(row.scope) ~= "string" or row.scope == "" then
			return nil
		end
		return row.scope .. "/" .. row.context
	end
	local function finder(items)
		local now = os.time()
		local displayer = entry_display.create({
			separator = " ",
			items = {
				{ width = 1 }, -- pin marker
				{ width = 45 }, -- title (CueMarkerActive on the active row)
				{ width = 8 }, -- mode
				{ width = 6, right_justify = true }, -- activity
				{ width = 9 }, -- kind
				{ remaining = true }, -- slug (canonical address at store breadth)
			},
		})
		local kind_highlights = {
			work = "CueKindWork",
			coord = "CueKindCoord",
			reference = "CueKindReference",
		}
		local mode_highlights = {
			research = "CueModeResearch",
			design = "CueModeDesign",
			build = "CueModeBuild",
			review = "CueModeReview",
			learn = "CueModeLearn",
		}
		local function text(value)
			return type(value) == "string" and value:match("%S") and value or "—"
		end
		return finders.new_table({
			results = items,
			entry_maker = function(row)
				local identity = address(row)
				local title = core.context_display_title(row)
				local active = core.context_is_active(status, row)
				local label = opts.scope == "store" and (identity or row.context) or row.context
				local mode, kind = text(row.mode), text(row.kind)
				-- Activation is a COLOUR, not a glyph: the active row's title
				-- renders in CueMarkerActive, which reads at a glance without
				-- spending a marker cell, and is unrelated to Telescope's own
				-- cursor-selection highlight (that follows the cursor; this
				-- follows the branch). The marker column is left to the pin.
				local title_hl = active and "CueMarkerActive" or "TelescopeResultsNormal"
				-- An active row is pinned too (activation pins), and the stronger
				-- signal wins the shared cell: "this is the branch's context"
				-- outranks "this is in the working set".
				local marker_hl = active and "CueMarkerActive"
					or (row.pinned == true and "CueMarkerPinned" or "TelescopeResultsComment")
				return make_entry.set_default_entry_mt({
					value = row,
					path = row.path,
					ordinal = (identity or row.context) .. " " .. title .. " " .. mode .. " " .. kind,
					display = function()
						return displayer({
							{ core.context_pin_marker(row), marker_hl },
							{ title, title_hl },
							{ mode:upper(), mode_highlights[mode] or "TelescopeResultsComment" },
							{ core.context_activity(row.last_logged_at, now), "TelescopeResultsComment" },
							{ kind, kind_highlights[kind] or "TelescopeResultsNormal" },
							{ label, "TelescopeResultsComment" },
						})
					end,
				}, opts)
			end,
		})
	end
	pickers
		.new({}, {
			prompt_title = opts.pinned == true and "Cue Pinned Contexts" or "Cue Contexts",
			layout_strategy = "vertical",
			layout_config = { mirror = true, prompt_position = "top", preview_height = 0.5 },
			finder = finder(rows),
			sorter = conf.generic_sorter({}),
			previewer = conf.file_previewer({}),
			tiebreak = function()
				return false
			end,
			attach_mappings = function(prompt_bufnr, map)
				local function local_selection()
					local entry = action_state.get_selected_entry()
					if not entry then
						return nil
					end
					if not status or type(status.scope) ~= "string" or status.scope ~= entry.value.scope then
						vim.notify(
							"Cue: browsing artifacts and activation require the current repository scope",
							vim.log.levels.WARN
						)
						return nil
					end
					return entry.value
				end
				actions.select_default:replace(function()
					local entry = action_state.get_selected_entry()
					if not entry or not entry.path then
						return
					end
					actions.close(prompt_bufnr)
					vim.cmd.edit(vim.fn.fnameescape(entry.path))
				end)
				-- `cue context pin|unpin` takes a canonical address, so pin state can
				-- be changed in any scope -- unlike browsing and activation.
				local function pin_argv(operation, identity)
					local cmd = { "cue", "context", operation, identity }
					if opts.dir then
						table.insert(cmd, "-C")
						table.insert(cmd, opts.dir)
					end
					if opts.store then
						table.insert(cmd, "--store")
						table.insert(cmd, opts.store)
					end
					return cmd
				end
				local function browse()
					local row = local_selection()
					if not row then
						return
					end
					actions.close(prompt_bufnr)
					M.pick_context_artifacts(row.context, opts)
				end
				--- Activate on the current branch, pinning first.
				---
				--- The order is load-bearing, not cosmetic. Activating puts the branch
				--- on this context, so the context belongs in the working set; running
				--- the pin AFTER the switch would, on a pin failure, leave the branch
				--- pointed at a context the pinned view cannot show. Pinning first
				--- makes the failure abort the activation instead, leaving both
				--- unchanged. `cue context pin` is idempotent, so re-pinning an
				--- already-pinned context costs one call and changes nothing.
				local function activate()
					local row = local_selection()
					if not row then
						return
					end
					local identity = address(row)
					if not identity then
						vim.notify("Cue: context row has no scope for pinning", vim.log.levels.ERROR)
						return
					end
					local output, err = core.execute_command(pin_argv("pin", identity))
					if not output then
						vim.notify(
							"Cue context pin failed, not activating " .. identity .. ": " .. (err or "unknown error"),
							vim.log.levels.ERROR
						)
						return
					end
					actions.close(prompt_bufnr)
					core.switch_context(row.context, opts)
				end
				local function pin()
					local entry = action_state.get_selected_entry()
					if not entry then
						return
					end
					local identity = address(entry.value)
					if not identity then
						vim.notify("Cue: context row has no scope for pinning", vim.log.levels.ERROR)
						return
					end
					-- A-s is view-scoped, not a state-aware toggle: it pins in the full
					-- view and unpins in the pinned view.
					local operation = opts.pinned == true and "unpin" or "pin"
					-- The active context stays pinned. Activation pins precisely so the
					-- branch's context is in the working set; unpinning it would hide
					-- the row the pinned view exists to show, while the branch stayed on
					-- it. Switch away first. Matched on scope identity, so the guard
					-- holds a same-named context in another scope unpinnable.
					if operation == "unpin" and core.context_is_active(status, entry.value) then
						vim.notify(
							"Cue: "
								.. identity
								.. " is the active context and stays pinned;"
								.. " switch away before unpinning",
							vim.log.levels.WARN
						)
						return
					end
					local output, err = core.execute_command(pin_argv(operation, identity))
					if not output then
						vim.notify(
							"Cue context " .. operation .. " failed: " .. (err or "unknown error"),
							vim.log.levels.ERROR
						)
						return
					end
					local updated = fetch()
					if updated then
						action_state.get_current_picker(prompt_bufnr):refresh(finder(updated), { reset_prompt = false })
					end
				end
				--- Copy the selected context's canonical address `<scope>/<context>`:
				--- the form cue accepts on the command line and in `parent:`/`refs:`
				--- frontmatter, and what another agent or repository can resolve.
				---
				--- Built from the SAME `address` helper pin, unpin and activate
				--- already address rows with, so the copied value is exactly what the
				--- CLI would be handed -- never the row's absolute `path`, which is
				--- meaningless to anyone whose store lives elsewhere, and never a
				--- bare slug, which is only unique within one scope.
				---
				--- Scope travels on the row, so this needs no `cue status` query and
				--- works for foreign rows in the store-wide view: an address names
				--- its own scope, unlike browsing and activation which require the
				--- current repository. A row without one is not addressed at all: a
				--- partial address pastes cleanly and resolves to nothing.
				---
				--- `<Tab>` multi-selection is honored, as in the artifact picker's
				--- yanks: every toggled row's address is copied space-joined in one
				--- register write; scopeless rows are skipped rather than fatal.
				---
				--- Like the artifact picker's yanks, this leaves the picker OPEN:
				--- copying is a lookup, not a destination.
				local function copy_address()
					local multi = multi_selection(prompt_bufnr)
					if next(multi) ~= nil then
						copy_values(multi, function(e)
							return address(e.value)
						end, "address")
						return
					end
					local entry = action_state.get_selected_entry()
					if not entry then
						vim.notify("Cue: no context selected to copy an address from", vim.log.levels.WARN)
						return
					end
					local identity = address(entry.value)
					if not identity then
						vim.notify("Cue: the selected context row carries no scope to address", vim.log.levels.WARN)
						return
					end
					copy_to_clipboard("address", identity)
				end
				for _, mode in ipairs({ "i", "n" }) do
					map(mode, "<C-e>", browse)
					map(mode, "<C-s>", activate)
					map(mode, "<A-s>", pin)
					map(mode, "<C-h>", copy_address)
				end
				return true
			end,
		})
		:find()
end

return M
