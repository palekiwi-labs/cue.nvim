--- Telescope pickers for cue artifacts
local M = {}

local config = require('cue.config')
local core   = require('cue.core')

local pickers       = require('telescope.pickers')
local finders       = require('telescope.finders')
local conf          = require('telescope.config').values
local actions       = require('telescope.actions')
local action_state  = require('telescope.actions.state')
local entry_display = require('telescope.pickers.entry_display')
local make_entry    = require('telescope.make_entry')

-- ─── Private helpers ──────────────────────────────────────────────────────────

--- Format category badge for display (uppercase)
---@param category string
---@return string
local function format_category(category)
  return string.upper(category)
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

--- Entry maker for the context artifact picker: a type badge plus the
--- displayed title (frontmatter title, else filename). The ordinal indexes
--- the type, the title and the filename, so the single list stays searchable
--- across groups.
---@param opts table|nil
---@return function
local function make_context_artifact_entry_maker(opts)
  opts = opts or {}

  local displayer = entry_display.create {
    separator = " ",
    items = {
      { width = 5 },        -- artifact type badge
      { remaining = true }, -- title, falling back to the filename
    },
  }

  local make_display = function(entry)
    local dim = core.artifact_finished(entry.value) and "CueStatusComplete" or nil
    return displayer {
      { format_category(entry.category), dim or get_category_highlight(entry.category) },
      { entry.title, dim or "TelescopeResultsNormal" },
    }
  end

  return function(artifact)
    if not artifact or not artifact.path then
      return nil
    end

    local title = core.artifact_display_title(artifact)

    return make_entry.set_default_entry_mt({
      value       = artifact,
      display     = make_display,
      ordinal     = string.format("%s %s %s", artifact.type or "", title, artifact.name or ""),
      path        = artifact.path,
      title       = title,
      name        = artifact.name,
      context     = artifact.context,
      category    = artifact.type,
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
    vim.notify(
      "Error: pick_context_artifacts requires an explicit context slug",
      vim.log.levels.ERROR
    )
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

  pickers.new({}, {
    prompt_title = "Cue Artifacts (" .. ctx .. ")",
    finder = finders.new_table({
      results     = rows,
      entry_maker = make_context_artifact_entry_maker(opts),
    }),
    sorter    = conf.generic_sorter({}),
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
    attach_mappings = function(prompt_bufnr, _)
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
      return true
    end,
  }):find()
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
--- Pin state is a query predicate, not a row field: A-s pins in the full
--- view and unpins in the pinned view. Foreign scopes may be opened/pinned,
--- but artifact browsing and branch activation require the current repo.
function M.pick_contexts(opts)
  opts = opts or {}
  local query = {
    json = true, pinned = opts.pinned, scope = opts.scope,
    sort = opts.sort or "recency", limit = opts.limit,
    dir = opts.dir, store = opts.store,
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
  if not rows then return end
  if #rows == 0 then
    vim.notify("No cue contexts" .. (opts.pinned == true and " pinned" or ""), vim.log.levels.INFO)
    return
  end

  local _, status = core.get_active_context(opts)
  local function address(row)
    if type(row.scope) ~= "string" or row.scope == "" then return nil end
    return row.scope .. "/" .. row.context
  end
  local function finder(items)
    local now = os.time()
    local displayer = entry_display.create {
      separator = " ",
      items = {
        { width = 1 },          -- active marker
        { width = 8 },          -- mode
        { width = 70 },         -- title: legacy task-picker width
        { width = 6, right_justify = true }, -- activity
        { width = 9 },          -- kind
        { remaining = true },  -- slug (canonical address at store breadth)
      },
    }
    local kind_highlights = {
      work = "CueKindWork", coord = "CueKindCoord", reference = "CueKindReference",
    }
    local mode_highlights = {
      research = "CueModeResearch", design = "CueModeDesign", build = "CueModeBuild",
      review = "CueModeReview", learn = "CueModeLearn",
    }
    local function text(value)
      return type(value) == "string" and value:match("%S") and value or "—"
    end
    return finders.new_table({
      results = items,
      entry_maker = function(row)
        local identity = address(row)
        local title = core.context_display_title(row)
        local active = status and status.scope == row.scope and status.context == row.context
        local label = opts.scope == "store" and (identity or row.context) or row.context
        local mode, kind = text(row.mode), text(row.kind)
        return make_entry.set_default_entry_mt({
          value = row, path = row.path,
          ordinal = (identity or row.context) .. " " .. title .. " " .. mode .. " " .. kind,
          display = function()
            return displayer {
              { active and "*" or " ", "CueMarkerActive" },
              { mode:upper(), mode_highlights[mode] or "TelescopeResultsComment" },
              { title, "TelescopeResultsNormal" },
              { core.context_activity(row.last_logged_at, now), "TelescopeResultsComment" },
              { kind, kind_highlights[kind] or "TelescopeResultsNormal" },
              { label, "TelescopeResultsComment" },
            }
          end,
        }, opts)
      end,
    })
  end
  pickers.new({}, {
    prompt_title = opts.pinned == true and "Cue Pinned Contexts" or "Cue Contexts",
    layout_strategy = "vertical",
    layout_config = { mirror = true, prompt_position = "top", preview_height = 0.5 },
    finder = finder(rows),
    sorter = conf.generic_sorter({}),
    previewer = conf.file_previewer({}),
    tiebreak = function() return false end,
    attach_mappings = function(prompt_bufnr, map)
      local function local_selection()
        local entry = action_state.get_selected_entry()
        if not entry then return nil end
        if not status or type(status.scope) ~= "string" or status.scope ~= entry.value.scope then
          vim.notify("Cue: browsing artifacts and activation require the current repository scope",
            vim.log.levels.WARN)
          return nil
        end
        return entry.value
      end
      actions.select_default:replace(function()
        local entry = action_state.get_selected_entry()
        if not entry or not entry.path then return end
        actions.close(prompt_bufnr)
        vim.cmd.edit(vim.fn.fnameescape(entry.path))
      end)
      local function browse()
        local row = local_selection()
        if not row then return end
        actions.close(prompt_bufnr)
        M.pick_context_artifacts(row.context, opts)
      end
      local function activate()
        local row = local_selection()
        if not row then return end
        actions.close(prompt_bufnr)
        core.switch_context(row.context, opts)
      end
      local function pin()
        local entry = action_state.get_selected_entry()
        if not entry then return end
        local identity = address(entry.value)
        if not identity then
          vim.notify("Cue: context row has no scope for pinning", vim.log.levels.ERROR)
          return
        end
        local operation = opts.pinned == true and "unpin" or "pin"
        local cmd = { 'cue', 'context', operation, identity }
        if opts.dir then
          table.insert(cmd, '-C'); table.insert(cmd, opts.dir)
        end
        if opts.store then
          table.insert(cmd, '--store'); table.insert(cmd, opts.store)
        end
        local output, err = core.execute_command(cmd)
        if not output then
          vim.notify("Cue context " .. operation .. " failed: " .. (err or "unknown error"), vim.log.levels.ERROR)
          return
        end
        local updated = fetch()
        if updated then
          action_state.get_current_picker(prompt_bufnr):refresh(finder(updated), { reset_prompt = false })
        end
      end
      for _, mode in ipairs({ 'i', 'n' }) do
        map(mode, '<C-e>', browse)
        map(mode, '<C-s>', activate)
        map(mode, '<A-s>', pin)
      end
      return true
    end,
  }):find()
end

return M
