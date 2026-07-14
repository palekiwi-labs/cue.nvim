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

--- List task-context directories under .cue/ (excluding stray files like
--- tags/.gitignore). Uses vim.fs.dir, the idiomatic API on nvim 0.8+.
--- Returns a sorted list of task context slugs (including "master").
---@return table|nil  sorted list of context slugs, or nil if .cue/ is absent
local function list_task_contexts()
  local cue_dir = ".cue"
  if vim.fn.isdirectory(cue_dir) == 0 then
    return nil
  end
  local contexts = {}
  for name, kind in vim.fs.dir(cue_dir) do
    if kind == "directory" then
      table.insert(contexts, name)
    end
  end
  table.sort(contexts)
  return contexts
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
        { width = 5 },        -- category badge
        { width = 60 },       -- filename / title
        { width = 10 },       -- hash
        { remaining = true }, -- task context slug (entry.branch = JSON wire field)
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

    if entry.frontmatter and entry.frontmatter ~= vim.NIL then
      local fm = entry.frontmatter
      if fm.title and fm.title ~= vim.NIL and fm.title ~= "" then
        display_name = fm.title
      end
      if core.is_done(entry) then
        highlight = "CueStatusDone"
      end
    end

    local cols = {}
    if show_marker then
      -- Task cards live in .cue/master/task/<slug>.md; entry.branch is always
      -- "master" for all of them. Compare the filename stem (the task slug)
      -- against active_task instead.
      local slug = vim.fn.fnamemodify(entry.name, ":r")
      local marker = (active_task and slug == active_task) and "*" or " "
      table.insert(cols, { marker, "TelescopeResultsComment" })
    end
    table.insert(cols, { format_category(entry.category),    get_category_highlight(entry.category) })
    table.insert(cols, { display_name,                       highlight })
    table.insert(cols, { hash_display,                       "TelescopeResultsComment" })
    table.insert(cols, { entry.branch,                       "TelescopeResultsComment" })

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

--- Sort artifacts: active first, active task context first, then by category, then by recency
---@param artifacts table
---@return table
local function sort_artifacts(artifacts)
  local active_task = core.get_active_task().context

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

  artifacts = sort_artifacts(artifacts)

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

  pickers.new({}, {
    prompt_title = prompt_title,
    finder = finders.new_table({
      results     = artifacts,
      entry_maker = make_mem_entry_maker(opts),
    }),
    sorter    = conf.generic_sorter({}),
    previewer = conf.file_previewer({}),
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
        local obj = vim.system({ 'cue', 'switch', slug }, { text = true }):wait()
        if obj.code == 0 then
          vim.notify("Switched to task: " .. slug, vim.log.levels.INFO)
        else
          local msg = vim.trim((obj.stderr or "") ~= "" and obj.stderr or (obj.stdout or "unknown"))
          vim.notify("cue switch failed: " .. msg, vim.log.levels.ERROR)
        end
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

      return true
    end,
  }):find()
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
