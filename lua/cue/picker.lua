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
local utils         = require('telescope.utils')

-- ─── Private helpers ──────────────────────────────────────────────────────────

--- Fetch artifacts from the cue CLI as a decoded JSON table
---@param opts table|nil
---@return table|nil
local function get_cue_artifacts(opts)
  opts = opts or {}

  -- Verify `cue` is on PATH without spawning a shell. cue --version exits 0.
  local probe = vim.system({ 'cue', '--version' }, { text = true }):wait()
  if probe.code ~= 0 then
    vim.notify("Error: 'cue' command not found. Please ensure it's installed and in your PATH.", vim.log.levels.ERROR)
    return nil
  end

  local cmd = { 'cue', 'list', '--json', '--frontmatter' }
  if opts.all then
    table.insert(cmd, '--all')
  end
  if opts.task then
    table.insert(cmd, '--task')
    table.insert(cmd, opts.task)
  end
  if opts.type then
    table.insert(cmd, '--type')
    table.insert(cmd, opts.type)
  end
  if not opts.all then
    table.insert(cmd, '--include-gitignored')
  end

  local output, err = core.execute_command(cmd)
  if not output or output == "" then
    if err then
      vim.notify("Error fetching cue artifacts: " .. err, vim.log.levels.ERROR)
    else
      vim.notify("No cue artifacts found", vim.log.levels.INFO)
    end
    return nil
  end

  local artifacts, parse_err = core.parse_json(output)
  if not artifacts then
    vim.notify("Error parsing cue data: " .. (parse_err or "unknown"), vim.log.levels.ERROR)
    return nil
  end

  return artifacts
end

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

--- Marker glyph for a task card. Resolves the slug from the entry's
--- filename stem and delegates to core.task_marker_for, so display and
--- sort share a single source of truth; the sentinel marker is then
--- translated to a Nerd Font glyph (config.MARKER_GLYPH) for display
--- only -- sorting keeps comparing the raw sentinels.
---@param entry table
---@param active_task string|nil
---@return string marker_glyph, string highlight
local function entry_marker(entry, active_task)
  local slug = vim.fn.fnamemodify(entry.name, ":r")
  local status = nil
  if entry.frontmatter and entry.frontmatter ~= vim.NIL then
    status = entry.frontmatter.status
  end
  local marker = core.task_marker_for(slug, status, active_task)
  local hl = "TelescopeResultsComment"
  if marker == "*" then
    hl = "CueMarkerActive"
  elseif marker == "!" then
    hl = "CueMarkerInProgress"
  end
  -- " " (no marker) passes through unmapped.
  return config.MARKER_GLYPH[marker] or marker, hl
end

--- Normalized tag list for an entry (see core.task_tags). Shared by the
--- display (first tag) and the search ordinal (all tags).
---@param entry table
---@return table
local function entry_tags(entry)
  return core.task_tags(entry.frontmatter)
end

--- Custom Telescope entry maker for cue artifacts
---@param opts table|nil  supports: active_task (string), show_marker (bool)
---@return function
local function make_mem_entry_maker(opts)
  opts = opts or {}

  -- active_task is fetched once by pick_artifacts and passed via opts so that
  -- all entries share a single cue status call (not one per row).
  local active_task = opts.active_task
  -- show_marker is true only for task-type pickers (pick_artifacts sets it).
  local show_marker = opts.show_marker

  local displayer
  if show_marker then
    displayer = entry_display.create {
      separator = " ",
      items = {
        { width = 1 },        -- active-task marker ("*" or " ")
        { width = 9 },        -- kind (full word; "research" is the longest)
        { width = 1 },        -- priority caret (critical/high only)
        { width = 70 },       -- filename / title
        { width = 12 },       -- tag (#first-tag; all tags searchable)
        { remaining = true }, -- task slug (absorbs all spare width)
      },
    }
  else
    displayer = entry_display.create {
      separator = " ",
      items = {
        { width = 5 },        -- category badge
        { width = 60 },       -- filename / title
        { width = 10 },       -- hash
        { remaining = true }, -- task context slug (entry.branch = JSON wire field)
      },
    }
  end

  local make_display = function(entry)
    local hash_display = ""
    if entry.hash and entry.hash ~= vim.NIL then
      hash_display = entry.hash
    end

    local display_name = utils.transform_path(opts, entry.name)
    local highlight    = "TelescopeResultsNormal"
    local done_hl      = nil

    -- Grey dimming of finished cards is a scanning aid for MIXED lists
    -- (<C-s> etc.); pickers listing only done cards (pick_done_tasks)
    -- pass dim_done=false and render normal colors (operator 2026-08-26).
    local dim_done = opts.dim_done ~= false

    if entry.frontmatter and entry.frontmatter ~= vim.NIL then
      local fm = entry.frontmatter
      if fm.title and fm.title ~= vim.NIL and fm.title ~= "" then
        display_name = fm.title
      end
      done_hl = core.done_highlight_for(fm.status, dim_done)
      if done_hl then
        highlight = done_hl
      end
    end

    -- In dim mode, strikethrough (CueStatusDone) applies ONLY to the
    -- title; metadata columns use CueStatusComplete (grey, no
    -- strikethrough). In no-dim mode there is no metadata override.
    local done_no_strike_hl = (dim_done and done_hl) and "CueStatusComplete" or nil

    local cols = {}
    if show_marker then
      -- "*" = active task (overrides), "!" = in-progress, " " otherwise.
      -- entry_marker is shared with sort_artifacts so the column and the
      -- ordering never disagree.
      local marker, marker_hl = entry_marker(entry, active_task)
      table.insert(cols, { marker, marker_hl })

      -- Kind column: full lowercase word, colored per kind. Overloading
      -- this column with priority color was unreadable (operator QA
      -- 2026-08-22); priority now has its own caret column. Missing kind
      -- (majority of legacy cards) shows the generic "task".
      local kind_word = "task"
      local kind_hl = "CueCategoryTask"
      if entry.frontmatter and entry.frontmatter ~= vim.NIL then
        local fm = entry.frontmatter
        if fm.kind and fm.kind ~= vim.NIL and fm.kind ~= "" then
          kind_word = fm.kind:lower()
          kind_hl = config.kind_highlights[kind_word] or "CueCategoryTask"
        end
      end
      if done_no_strike_hl then
        kind_hl = done_no_strike_hl
      end
      table.insert(cols, { kind_word, kind_hl })

      -- Priority column: Jira-style caret glyph for critical/high only
      -- (operator decision: normal is the norm, low is rare clutter --
      -- both render blank). Color carries the priority, kind no longer
      -- does.
      local prio_glyph = ""
      local prio_hl = "TelescopeResultsNormal"
      if entry.frontmatter and entry.frontmatter ~= vim.NIL then
        local fm = entry.frontmatter
        if fm.priority and fm.priority ~= vim.NIL and fm.priority ~= "" then
          local prio = fm.priority:lower()
          prio_glyph = config.PRIORITY_GLYPH[prio] or ""
          if prio_glyph ~= "" then
            prio_hl = config.priority_highlights[prio] or prio_hl
          end
        end
      end
      if done_no_strike_hl then
        prio_hl = done_no_strike_hl
      end
      table.insert(cols, { prio_glyph, prio_hl })

      table.insert(cols, { display_name, highlight })

      -- Tag column: first tag only, "#" prefixed. All tags feed the search
      -- ordinal (see below), so filtering by any tag still works even when
      -- it is not the displayed one.
      local tags = entry_tags(entry)
      local tag_display = tags[1] and ("#" .. tags[1]) or ""
      local tag_hl = done_no_strike_hl or "CueTag"
      table.insert(cols, { tag_display, tag_hl })

      local meta_hl = done_no_strike_hl or "TelescopeResultsComment"

      local task_slug = vim.fn.fnamemodify(entry.name, ":t:r")
      table.insert(cols, { task_slug, meta_hl })
      -- No parent column (operator 2026-08-24: space-hungry and confusing;
      -- parent stays searchable via the "^ slug" ordinal token and
      -- jumpable via <A-p>). No hash column: task cards never carry
      -- content hashes (hash is null on every master card); the trailing
      -- space belongs to slug.
    else
      local cat_hl = done_no_strike_hl or get_category_highlight(entry.category)
      local meta_hl = done_no_strike_hl or "TelescopeResultsComment"
      table.insert(cols, { format_category(entry.category), cat_hl })
      table.insert(cols, { display_name, highlight })
      table.insert(cols, { hash_display, meta_hl })
      table.insert(cols, { entry.branch, meta_hl })
    end

    return displayer(cols)
  end

  return function(entry)
    if not entry or not entry.path then
      return nil
    end

    local hash_for_search = ""
    if entry.hash and entry.hash ~= vim.NIL then
      hash_for_search = entry.hash
    end

    local fm_search = ""
    if entry.frontmatter and entry.frontmatter ~= vim.NIL then
      local fm = entry.frontmatter
      if fm.title and fm.title ~= vim.NIL then
        fm_search = fm_search .. " " .. fm.title
      end
      if fm.status and fm.status ~= vim.NIL then
        fm_search = fm_search .. " " .. fm.status
      end
      if fm.kind and fm.kind ~= vim.NIL then
        fm_search = fm_search .. " " .. fm.kind
      end
      if fm.priority and fm.priority ~= vim.NIL then
        fm_search = fm_search .. " " .. fm.priority
      end
      if fm.parent and fm.parent ~= vim.NIL then
        fm_search = fm_search .. " ^ " .. fm.parent .. " " .. fm.parent
      end
    end

    -- All tags (not just the displayed first one) feed the fuzzy ordinal,
    -- so typing any tag name filters tasks by that tag.
    for _, tag in ipairs(entry_tags(entry)) do
      fm_search = fm_search .. " " .. tag
    end

    local ordinal = string.format("%s %s %s %s%s",
      entry.name, hash_for_search, entry.branch, entry.category, fm_search)

    return make_entry.set_default_entry_mt({
      value            = entry,
      display          = make_display,
      ordinal          = ordinal,
      path             = entry.path,
      category         = entry.category,
      hash             = entry.hash,
      name             = entry.name,
      branch           = entry.branch,
      commit_timestamp = entry.commit_timestamp,
      commit_hash      = entry.commit_hash,
      frontmatter      = entry.frontmatter,
    }, opts)
  end
end

--- Apply pickers' exclude/status filters to fetched artifacts.
---
--- exclude_type (client-side negative type filter; no cue list CLI
--- equivalent exists) applies to every picker. Status filters apply to
--- task-type pickers only: opts.status/opts.statuses are positive
--- filters (inbox/done pickers), opts.board hides config.
--- HIDDEN_TASK_STATUSES (C-t board). opts.dim_done (default true)
--- toggles grey dimming of finished cards. All decisions live in pure
--- core helpers under unit test.
---@param artifacts table
---@param opts table|nil  supports: exclude_type, status, statuses, board, type
---@return table
local function filter_artifacts(artifacts, opts)
  opts = opts or {}
  local is_task_picker = opts.type == "task"
  local out = {}
  for _, a in ipairs(artifacts) do
    -- exclude_type: negative type filter (all pickers).
    local excluded = core.type_excluded(a.category, opts)
    -- Status filters: task-type pickers only (positive filter or board
    -- hiding of config.HIDDEN_TASK_STATUSES).
    if not excluded and is_task_picker then
      excluded = core.task_status_excluded(a.frontmatter, opts)
    end
    if not excluded then
      out[#out + 1] = a
    end
  end
  return out
end

--- Sort artifacts.
---
--- For the task picker (opts.show_marker), ordering is delegated entirely
--- to core.task_less: marker ("*" < "!" < blank), then finished
--- (complete/closed) sinks to the bottom, then priority, then recency,
--- then name. Extracting the comparator keeps the finished-before-priority
--- invariant under unit test (see tests/test_task_sort.lua).
---
--- All other pickers share: finished last, active context first, category,
--- recency, then name.
---@param artifacts table
---@param opts table|nil  supports: show_marker (bool, task picker only)
---@return table
local function sort_artifacts(artifacts, opts)
  opts = opts or {}
  local active_task = core.get_active_task().context
  local task_sort = opts.show_marker == true

  local category_priority = {
    task  = 0,
    plan  = 1,
    todo  = 2,
    note  = 3,
    spec  = 4,
    trace = 5,
    doc   = 6,
    bin   = 7,
    tmp   = 8,
  }

  table.sort(artifacts, function(a, b)
    -- Task picker: the full ordering lives in core.task_less.
    if task_sort then
      return core.task_less(a, b, active_task)
    end

    local a_finished = core.is_finished(a)
    local b_finished = core.is_finished(b)
    if a_finished ~= b_finished then
      return not a_finished
    end

    local a_is_current = a.branch == active_task
    local b_is_current = b.branch == active_task
    if a_is_current ~= b_is_current then
      return a_is_current
    end

    local a_priority = category_priority[a.category] or 999
    local b_priority = category_priority[b.category] or 999
    if a_priority ~= b_priority then
      return a_priority < b_priority
    end

    local a_ts = a.commit_timestamp and a.commit_timestamp ~= vim.NIL and a.commit_timestamp or 0
    local b_ts = b.commit_timestamp and b.commit_timestamp ~= vim.NIL and b.commit_timestamp or 0
    if a_ts ~= b_ts then
      return a_ts > b_ts
    end

    return a.name < b.name
  end)

  return artifacts
end

--- Copy a value to the clipboard and notify.
--- Honors multi-selection: when entries are toggled via <Tab>, all values
--- are copied space-separated. Falls back to the highlighted entry when
--- nothing is multi-selected. Entries whose getter returns nil/""/vim.NIL
--- are silently skipped.
---@param prompt_bufnr integer
---@param getter function  receives a selected entry, returns the string to copy
---@param label string
local function copy_to_clipboard(prompt_bufnr, getter, label)
  local picker = action_state.get_current_picker(prompt_bufnr)
  local multi  = picker and picker:get_multi_selection() or {}

  local entries = {}
  if next(multi) ~= nil then
    for _, e in ipairs(multi) do
      table.insert(entries, e)
    end
  else
    local entry = action_state.get_selected_entry()
    if entry then table.insert(entries, entry) end
  end

  if #entries == 0 then return end

  local values = {}
  for _, e in ipairs(entries) do
    local v = getter(e)
    if v and v ~= "" and v ~= vim.NIL then
      table.insert(values, tostring(v))
    end
  end

  if #values == 0 then
    vim.notify("Nothing to copy for " .. label, vim.log.levels.WARN)
    return
  end

  local joined = table.concat(values, " ")
  vim.fn.setreg("+", joined)
  if #values == 1 then
    vim.notify("Copied " .. label .. ": " .. joined, vim.log.levels.INFO)
  else
    vim.notify("Copied " .. label .. " (" .. #values .. " items)", vim.log.levels.INFO)
  end
end

-- ─── Pickers ──────────────────────────────────────────────────────────────────

--- Open a Telescope picker for cue artifacts
---@param opts table|nil  supports: all, task, type
function M.pick_artifacts(opts)
  opts = opts or {}

  -- Fetch active task once; used for prompt title and the marker column.
  local active_task = core.get_active_task().context
  opts.active_task = active_task
  -- Marker column is shown only for task-type pickers (compares filename stem
  -- to active_task). All other pickers omit the column to save space.
  opts.show_marker = (opts.type == "task")

  local artifacts = get_cue_artifacts(opts)
  if not artifacts or #artifacts == 0 then return end

  artifacts = filter_artifacts(artifacts, opts)
  if #artifacts == 0 then
    vim.notify("No cue artifacts after filters", vim.log.levels.INFO)
    return
  end

  artifacts = sort_artifacts(artifacts, opts)

  local prompt_title = "Cue Artifacts"
  if opts.all then
    prompt_title = prompt_title .. " (all)"
  elseif opts.task then
    -- Explicit scope (drill-in, master binding, etc.) — show the slug.
    prompt_title = prompt_title .. " (" .. opts.task .. ")"
  else
    -- No explicit scope: picker follows HEAD. Label as "current" so the
    -- title is distinct from a picker explicitly scoped to the active task.
    prompt_title = prompt_title .. " (current)"
  end
  if opts.type then
    prompt_title = prompt_title .. " [" .. opts.type:upper() .. "]"
  end
  if opts.status then
    prompt_title = prompt_title .. " [" .. opts.status:upper() .. "]"
  elseif opts.statuses then
    local names = {}
    for _, s in ipairs(opts.statuses) do
      table.insert(names, s:upper())
    end
    prompt_title = prompt_title .. " [" .. table.concat(names, "/") .. "]"
  end

  local previewer
  if opts.preview ~= nil then
    previewer = opts.preview and conf.file_previewer({}) or false
  else
    previewer = conf.file_previewer({})
  end

  -- Task picker: stack the layout (vertical strategy, mirrored) so the
  -- preview becomes a full-width band below the results. Task rows are wide
  -- (marker, kind, title, tag, slug); a side-by-side preview
  -- would steal width and cut the trailing columns off. Unspecified keys
  -- (width, height, preview_cutoff) inherit the global telescope config.
  local layout_strategy, layout_config
  if opts.type == "task" then
    layout_strategy = "vertical"
    layout_config = {
      vertical = {
        mirror = true,        -- preview below the prompt/results block
        prompt_position = "top",
        preview_height = 0.5, -- even split: task list above, preview below
      },
    }
  end

  pickers.new({}, {
    prompt_title = prompt_title,
    default_text = opts.default_text,
    finder = finders.new_table({
      results     = artifacts,
      entry_maker = make_mem_entry_maker(opts),
    }),
    sorter          = conf.generic_sorter({}),
    previewer       = previewer,
    layout_strategy = layout_strategy,
    layout_config   = layout_config,
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local entry = action_state.get_selected_entry()
        if entry then
          vim.cmd.edit(entry.path)
        end
      end)

      -- Copy path to clipboard
      map({ 'i', 'n' }, '<C-y>', function()
        copy_to_clipboard(prompt_bufnr, function(e)
          return vim.fn.fnamemodify(e.path, ":p")
        end, "path")
      end)

      -- Copy to clipboard (<C-h>). Context-sensitive: task-type pickers
      -- copy the task slug (filename stem, same resolution as
      -- <C-s>/<C-e>); every other picker copies the artifact hash.
      -- Task cards never carry content hashes (hash is null on every
      -- master card -- same reason the hash column was dropped from the
      -- task layout), so the hash binding was dead in task pickers and
      -- the key is repurposed there. Multi-selection joins values
      -- space-separated (copy_to_clipboard).
      if opts.type == "task" then
        map({ 'i', 'n' }, '<C-h>', function()
          copy_to_clipboard(prompt_bufnr, function(e)
            return vim.fn.fnamemodify(e.name, ":r")
          end, "task slug")
        end)
      else
        map({ 'i', 'n' }, '<C-h>', function()
          copy_to_clipboard(prompt_bufnr, function(e) return e.hash end, "hash")
        end)
      end

      -- Jump to the parent artifact (<A-p>)
      map({ 'i', 'n' }, '<A-p>', function()
        local entry = action_state.get_selected_entry()
        if not entry or not entry.frontmatter or entry.frontmatter == vim.NIL then return end
        local parent_slug = entry.frontmatter.parent
        if not parent_slug or parent_slug == vim.NIL or parent_slug == "" then
          vim.notify("Selected artifact has no parent link", vim.log.levels.WARN)
          return
        end
        local parent_path = ".cue/master/task/" .. parent_slug .. ".md"
        if vim.fn.filereadable(parent_path) == 0 then
          parent_path = ".cue/" .. parent_slug .. ".md"
        end
        if vim.fn.filereadable(parent_path) == 0 then
          vim.notify("Parent artifact file not found: " .. parent_slug, vim.log.levels.WARN)
          return
        end
        actions.close(prompt_bufnr)
        vim.cmd.edit(parent_path)
      end)

      -- Filter child tasks of selected task (<C-f>)
      if opts.type == "task" then
        map({ 'i', 'n' }, '<C-f>', function()
          local entry = action_state.get_selected_entry()
          if not entry then return end
          local slug = vim.fn.fnamemodify(entry.name, ":r")
          if not slug or slug == "" then return end
          actions.close(prompt_bufnr)
          vim.schedule(function()
            M.pick_artifacts({ type = "task", default_text = slug })
          end)
        end)
      end

      -- Switch active task context to the selected entry's context (<C-s>).
      -- For task-type pickers the slug is the filename stem (entry.branch is
      -- always "master" for task cards). For all other pickers entry.branch
      -- holds the context slug directly.
      map({ 'i', 'n' }, '<C-s>', function()
        local entry = action_state.get_selected_entry()
        if not entry then return end
        local slug
        if opts.type == "task" then
          slug = vim.fn.fnamemodify(entry.name, ":r")
        else
          slug = entry.branch
        end
        if not slug or slug == "" then return end
        -- Central switch path: all context switches funnel through
        -- core.switch_context.
        core.switch_context(slug)
        actions.close(prompt_bufnr)
      end)

      -- Open artifacts for the selected entry's task context (<C-e>).
      -- Same slug resolution as <C-s>: use filename stem for task-type pickers.
      -- vim.schedule defers the new picker open until Telescope has fully torn
      -- down the current one; without it the picker silently does nothing.
      map({ 'i', 'n' }, '<C-e>', function()
        local entry = action_state.get_selected_entry()
        if not entry then return end
        local slug
        if opts.type == "task" then
          slug = vim.fn.fnamemodify(entry.name, ":r")
        else
          slug = entry.branch
        end
        if not slug or slug == "" then return end
        actions.close(prompt_bufnr)
        vim.schedule(function()
          M.pick_artifacts({ task = slug })
        end)
      end)

      -- Load review findings JSON into diagnostics (<A-d> actionable, <A-a> all)
      local load_review_diagnostics = function(opts_override)
        local entry = action_state.get_selected_entry()
        if not entry or not entry.path then return end

        if vim.endswith(entry.name, ".json") or (entry.category == "trace" and vim.endswith(entry.path, ".json")) then
          actions.close(prompt_bufnr)
          local ok, cue_review = pcall(require, "cue.review")
          if not ok then
            ok, cue_review = pcall(require, "config.utils.cue_review")
          end
          if ok and cue_review.load_file then
            cue_review.load_file(entry.path, opts_override)
          else
            vim.notify("Review diagnostics module not found", vim.log.levels.WARN)
          end
        else
          vim.notify("Selected artifact is not a JSON trace: " .. (entry.name or ""), vim.log.levels.WARN)
        end
      end

      map({ 'i', 'n' }, '<A-d>', function() load_review_diagnostics({}) end)
      map({ 'i', 'n' }, '<A-a>', function() load_review_diagnostics({ all = true }) end)

      return true
    end,
  }):find()
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
    return displayer {
      { format_category(entry.category), get_category_highlight(entry.category) },
      { entry.title, "TelescopeResultsNormal" },
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
--- type (task, spec, plan, note, trace) and sorted alphabetically by
--- displayed title within each group (cue-nvim-workflow spec §8).
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

--- Open a Telescope picker for all cue context files
function M.pick_context()
  local output, err = core.execute_command({ 'cue', 'context', 'path', '--all' })

  if not output or output == "" then
    vim.notify("Error: " .. (err or "No context files found"), vim.log.levels.ERROR)
    return
  end

  local paths = {}
  for line in output:gmatch("[^\r\n]+") do
    local path = vim.trim(line)
    if path ~= "" then
      table.insert(paths, path)
    end
  end

  if #paths == 0 then
    vim.notify("No context files found", vim.log.levels.INFO)
    return
  end

  pickers.new({}, {
    prompt_title = "Cue Context Files",
    finder = finders.new_table({
      results     = paths,
      entry_maker = make_entry.gen_from_file({}),
    }),
    previewer = conf.file_previewer({}),
    sorter    = conf.file_sorter({}),
    attach_mappings = function(prompt_bufnr, _)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        if selection then
          vim.cmd.edit(selection.value)
        end
      end)
      return true
    end,
  }):find()
end

return M
