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

  vim.fn.system('which cue 2>/dev/null')
  if vim.v.shell_error ~= 0 then
    vim.notify("Error: 'cue' command not found. Please ensure it's installed and in your PATH.", vim.log.levels.ERROR)
    return nil
  end

  local cmd = 'cue list --json --frontmatter'
  if opts.all then
    cmd = cmd .. ' --all'
  end
  if opts.branch then
    cmd = cmd .. ' --branch ' .. vim.fn.shellescape(opts.branch)
  end
  if opts.type then
    cmd = cmd .. ' --type ' .. vim.fn.shellescape(opts.type)
  end
  if not opts.all then
    cmd = cmd .. ' --include-gitignored'
  end
  cmd = cmd .. ' 2>/dev/null'

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

--- Custom Telescope entry maker for cue artifacts
---@param opts table|nil
---@return function
local function make_mem_entry_maker(opts)
  opts = opts or {}

  local displayer = entry_display.create {
    separator = " ",
    items = {
      { width = 5 },        -- category badge
      { width = 50 },       -- filename / title
      { width = 10 },       -- hash
      { remaining = true }, -- branch
    },
  }

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
        display_name = fm.title .. " (" .. display_name .. ")"
      end
      if core.is_done(entry) then
        highlight = "CueStatusDone"
      end
    end

    return displayer {
      { format_category(entry.category), get_category_highlight(entry.category) },
      { display_name,                    highlight },
      { hash_display,                    "TelescopeResultsComment" },
      { entry.branch,                    "TelescopeResultsComment" },
    }
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

--- Sort artifacts: active first, current branch first, then by category, then by recency
---@param artifacts table
---@return table
local function sort_artifacts(artifacts)
  local current_branch = core.get_current_branch()

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

    local a_is_current = a.branch == current_branch
    local b_is_current = b.branch == current_branch
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
---@param opts table|nil  supports: all, branch, type
function M.pick_artifacts(opts)
  opts = opts or {}

  local artifacts = get_cue_artifacts(opts)
  if not artifacts or #artifacts == 0 then return end

  artifacts = sort_artifacts(artifacts)

  local prompt_title = "Cue Artifacts"
  if opts.all then
    prompt_title = prompt_title .. " (All Branches)"
  else
    local branch = opts.branch or core.get_current_branch()
    if branch then
      prompt_title = prompt_title .. " (" .. branch .. ")"
    end
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

      return true
    end,
  }):find()
end

--- Open a Telescope picker for all cue context files
function M.pick_context()
  local output, err = core.execute_command("cue context path --all 2>/dev/null")

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

--- Guided branch selector → artifact type selector → artifact picker
function M.ui_pick()
  local Snacks = require('snacks')

  local branch_items = {
    { label = "Current Branch",   value = "current" },
    { label = "Master Branch",    value = vim.g.git_master or "master" },
    { label = "Base Branch",      value = vim.g.git_base   or "master" },
    { label = "All Branches",     value = "all" },
    { label = "Select Branch...", value = "pick" },
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

  local function pick_with_branch(branch)
    Snacks.picker.select(category_items, {
      prompt = "Select artifact type:",
      format_item = function(item)
        return string.format("%-8s  %s", item.label, item.desc)
      end,
    }, function(choice)
      if not choice then return end
      local pick_opts = {}
      if branch == "all" then
        pick_opts.all = true
      else
        pick_opts.branch = branch
      end
      pick_opts.type = choice.label
      M.pick_artifacts(pick_opts)
    end)
  end

  local function select_branch(callback)
    Snacks.picker.select(branch_items, {
      prompt = "Select Branch Scope:",
      format_item = function(item) return item.label end,
    }, function(choice)
      if not choice then return end
      if choice.value == "pick" then
        local cue_dir = ".cue"
        local branches = {}
        local p = io.popen('ls -d ' .. cue_dir .. '/*/ 2>/dev/null')
        if p then
          for line in p:lines() do
            local branch = line:match(".cue/(.+)/")
            if branch then table.insert(branches, branch) end
          end
          p:close()
        end
        if #branches == 0 then
          vim.notify("No branches with artifacts found", vim.log.levels.INFO)
          return
        end
        Snacks.picker.select(branches, { prompt = "Select Branch:" }, function(branch)
          if branch then callback(branch) end
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

  select_branch(function(branch)
    pick_with_branch(branch)
  end)
end

--- Open a branch selector, then show artifacts for the chosen branch
function M.pick_branch_artifacts()
  local cue_dir = ".cue"
  if vim.fn.isdirectory(cue_dir) == 0 then
    vim.notify("Error: .cue directory not found", vim.log.levels.ERROR)
    return
  end

  local branches = {}
  local p = io.popen('ls -d ' .. cue_dir .. '/*/ 2>/dev/null')
  if p then
    for line in p:lines() do
      local branch = line:match(".cue/(.+)/")
      if branch then
        table.insert(branches, branch)
      end
    end
    p:close()
  end

  if #branches == 0 then
    vim.notify("No branches with artifacts found", vim.log.levels.INFO)
    return
  end

  local Snacks = require('snacks')
  Snacks.picker.select(branches, { prompt = "Select Branch:" }, function(branch)
    if branch then
      M.pick_artifacts({ branch = branch })
    end
  end)
end

--- Open a branch selector, then open that branch's log file.
--- Symmetric to pick_context() and pick_branch_artifacts().
function M.pick_logs()
  local cue_dir = ".cue"
  if vim.fn.isdirectory(cue_dir) == 0 then
    vim.notify("Error: .cue directory not found", vim.log.levels.ERROR)
    return
  end

  local branches = {}
  local p = io.popen('ls -d ' .. cue_dir .. '/*/ 2>/dev/null')
  if p then
    for line in p:lines() do
      local branch = line:match(".cue/(.+)/")
      if branch then table.insert(branches, branch) end
    end
    p:close()
  end

  if #branches == 0 then
    vim.notify("No branches found", vim.log.levels.INFO)
    return
  end

  local Snacks = require('snacks')
  Snacks.picker.select(branches, { prompt = "Select Branch (log):" }, function(branch)
    if branch then require('cue.core').open_log(branch) end
  end)
end

return M
