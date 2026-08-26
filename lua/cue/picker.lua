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

--- List selectable scopes via core.list_scopes() (task-card slugs, always
--- including "master"). Thin wrapper so the three call sites below share a
--- single source of truth with core.confirm_scope.
---@return table|nil  sorted list of scope slugs, or nil if .cue/ is absent
local function list_task_contexts()
  return core.list_scopes()
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
    ref   = 9,
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

      -- Copy hash to clipboard
      map({ 'i', 'n' }, '<C-h>', function()
        copy_to_clipboard(prompt_bufnr, function(e) return e.hash end, "hash")
      end)

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

      -- Open the selected task's log.md (<C-l>). Task-picker only — other
      -- pickers have no status column. The slug is the filename stem;
      -- core.open_log resolves .cue/<slug>/log.md, checks filereadable, and
      -- notifies the user if the log does not exist yet.
      if opts.type == "task" then
        map({ 'i', 'n' }, '<C-l>', function()
          local entry = action_state.get_selected_entry()
          if not entry then return end
          local slug = vim.fn.fnamemodify(entry.name, ":r")
          if not slug or slug == "" then return end
          actions.close(prompt_bufnr)
          vim.schedule(function()
            core.open_log(slug)
          end)
        end)
      end

      return true
    end,
  }):find()
end

--- Open a picker over the INBOX: task cards with status "inbox"
--- (operator's idea-intake status). Positive status filter via
--- opts.status, so the picker lists only inbox cards and the prompt
--- title reflects it.
function M.pick_inbox_tasks()
  return M.pick_artifacts({ type = "task", task = "master", status = "inbox" })
end

--- Open a picker over DONE task cards: statuses "complete" and
--- "closed" (config.DONE_STATUSES). List-based positive filter via
--- opts.statuses, mirroring pick_inbox_tasks. Counterpart of the
--- <C-t> board, which hides these statuses (config.
--- HIDDEN_TASK_STATUSES).
---
--- dim_done=false: every card here is done, so the grey scanning aid
--- for mixed lists would grey out the whole picker (operator
--- 2026-08-26). Normal colors; closed titles still strike through.
function M.pick_done_tasks()
  return M.pick_artifacts({
    type = "task",
    task = "master",
    statuses = { "complete", "closed" },
    dim_done = false,
  })
end

--- Open the artifact picker scoped to the ACTIVE task's context.
---
--- Resolves the active task via `cue status --json` (core.get_active_task)
--- and delegates the scope decision to core.task_scope_for. Notifies when
--- the global (master) context is active, since it has no task scope; use
--- pick_artifacts() to follow the current scope unconditionally.
function M.pick_active_task_artifacts()
  local decision = core.task_scope_for(core.get_active_task())
  if decision.action == "notify" then
    vim.notify(decision.message, vim.log.levels.WARN)
    return
  end
  return M.pick_artifacts({ task = decision.task })
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

--- Guided task-context selector → artifact type selector → artifact picker
function M.ui_pick()
  local Snacks = require('snacks')

  local task_items = {
    { label = "Current Task",    value = "current" },
    { label = "Master",          value = "master" },
    { label = "All",             value = "all" },
    { label = "Select Task...",  value = "pick" },
  }

  local category_items = {
    { label = "task",  desc = "Task (on master)" },
    { label = "todo",  desc = "TODO (informal note)" },
    { label = "note",  desc = "Note" },
    { label = "spec",  desc = "Specification" },
    { label = "plan",  desc = "Plan artifact" },
    { label = "doc",   desc = "Documentation artifact" },
    { label = "trace", desc = "Trace / debug artifact" },
    { label = "bin",   desc = "Binary artifact" },
    { label = "tmp",   desc = "Temporary artifact" },
    { label = "ref",   desc = "Reference artifact" },
  }

  local function pick_with_task(task)
    Snacks.picker.select(category_items, {
      prompt = "Select artifact type:",
      format_item = function(item)
        return string.format("%-8s  %s", item.label, item.desc)
      end,
    }, function(choice)
      if not choice then return end
      local pick_opts = {}
      if task == "all" then
        pick_opts.all = true
      else
        pick_opts.task = task
      end
      pick_opts.type = choice.label
      M.pick_artifacts(pick_opts)
    end)
  end

  local function select_task(callback)
    Snacks.picker.select(task_items, {
      prompt = "Select Task Scope:",
      format_item = function(item) return item.label end,
    }, function(choice)
      if not choice then return end
      if choice.value == "pick" then
        local contexts = list_task_contexts()
        if not contexts or #contexts == 0 then
          vim.notify("No task contexts with artifacts found", vim.log.levels.INFO)
          return
        end
        Snacks.picker.select(contexts, { prompt = "Select Task:" }, function(ctx)
          if ctx then callback(ctx) end
        end)
      elseif choice.value == "current" then
        callback(nil)
      elseif choice.value == "all" then
        callback("all")
      else
        callback(choice.value)
      end
    end)
  end

  select_task(function(task)
    pick_with_task(task)
  end)
end

--- Open a task-context selector, then show artifacts for the chosen context
function M.pick_task_context_artifacts()
  local contexts = list_task_contexts()
  if not contexts then
    vim.notify("Error: .cue directory not found", vim.log.levels.ERROR)
    return
  end

  if #contexts == 0 then
    vim.notify("No task contexts with artifacts found", vim.log.levels.INFO)
    return
  end

  local Snacks = require('snacks')
  Snacks.picker.select(contexts, { prompt = "Select Task Context:" }, function(ctx)
    if ctx then
      M.pick_artifacts({ task = ctx })
    end
  end)
end

--- Open a task-context selector, then open that context's log file.
--- Symmetric to pick_context() and pick_task_context_artifacts().
function M.pick_logs()
  local contexts = list_task_contexts()
  if not contexts then
    vim.notify("Error: .cue directory not found", vim.log.levels.ERROR)
    return
  end

  if #contexts == 0 then
    vim.notify("No task contexts found", vim.log.levels.INFO)
    return
  end

  local Snacks = require('snacks')
  Snacks.picker.select(contexts, { prompt = "Select Task (log):" }, function(ctx)
    if ctx then require('cue.core').open_log(ctx) end
  end)
end

return M
