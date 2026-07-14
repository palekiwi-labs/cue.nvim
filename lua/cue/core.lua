--- Core helpers and artifact management functions
local M = {}

local config = require('cue.config')

-- ─── Private helpers ──────────────────────────────────────────────────────────

--- Check if artifact status is a "done" variant
---@param artifact table
---@return boolean
function M.is_done(artifact)
  if not artifact.frontmatter or artifact.frontmatter == vim.NIL then
    return false
  end
  local status = artifact.frontmatter.status
  return status and type(status) == "string" and config.DONE_STATUSES[status:lower()] or false
end

--- Check if artifact is done
---@param artifact table
---@return boolean
function M.is_finished(artifact)
  return M.is_done(artifact)
end

--- Slugify text for use as a filename
---@param text string|nil
---@return string|nil
function M.slugify(text)
  if not text then return nil end
  return text:lower()
    :gsub("[%s_/]+", "-")
    :gsub("[^%w%-]+", "")
    :gsub("%-+", "-")
    :gsub("^%-+", "")
    :gsub("%-+$", "")
end

--- Execute a command (as an arg list) and return its stdout.
--- Uses vim.system, the idiomatic API on nvim 0.10+. stderr is captured but
--- discarded; a non-zero exit code yields (nil, error).
---@param cmd table  command as a list of arguments (no shell involved)
---@return string|nil, string|nil
function M.execute_command(cmd)
  local obj = vim.system(cmd, { text = true }):wait()
  if obj.code ~= 0 then
    return nil, "Command failed"
  end
  return obj.stdout
end

--- Parse a JSON string using the native Lua JSON decoder (vim.json).
--- Preferred over the legacy `vim.fn.json_decode` wrapper on nvim 0.10+.
---@param json_str string
---@return any, string|nil
function M.parse_json(json_str)
  local ok, result = pcall(vim.json.decode, json_str)
  if not ok then
    return nil, "Failed to parse JSON"
  end
  return result
end

--- Get the current git branch name (with / replaced by -)
---@return string|nil
function M.get_current_branch()
  local obj = vim.system({ 'git', 'rev-parse', '--abbrev-ref', 'HEAD' }, { text = true }):wait()
  if obj.code ~= 0 then
    return nil
  end
  local branch = (obj.stdout or ""):gsub("%s+", "")
  if branch == "" then return nil end
  return branch:gsub("/", "-")
end

--- Get the active task context (resolved from `.cue/HEAD` via `cue status`).
--- This replaces the git branch as the cue scope. `get_current_branch()` is
--- kept above only for git operations (diffview, gitsigns, etc.).
---@return table  { context = "master", global = true } or
---                { context = "<slug>", global = false, title = "...", status = "..." }
function M.get_active_task()
  local output = M.execute_command({ 'cue', 'status', '--json' })
  if not output or output == "" then
    return { context = "master", global = true }
  end
  local ok, result = pcall(vim.json.decode, output)
  if not ok or type(result) ~= "table" or not result.context then
    return { context = "master", global = true }
  end
  return result
end

--- Switch the active cue context to the given task slug.
--- Calls `cue switch <slug>` and notifies the user of the result.
---@param slug string  task slug or "master"
function M.switch_context(slug)
  local obj = vim.system({ 'cue', 'switch', slug }, { text = true }):wait()
  if obj.code == 0 then
    vim.notify("cue: switched to " .. slug, vim.log.levels.INFO)
  else
    local msg = vim.trim((obj.stderr or "") ~= "" and obj.stderr or (obj.stdout or "unknown"))
    vim.notify("cue switch failed: " .. msg, vim.log.levels.ERROR)
  end
end

-- ─── Scope confirmation ───────────────────────────────────────────────────────

--- Prompt the user to confirm (or change) the cue scope for a new artifact.
---
--- Short-circuits without a dialog in two cases:
---   1. type == "task": tasks always live in master; callback("master") immediately.
---   2. task ~= nil: the caller already pinned a scope (e.g. add_with_title("todo",
---      "master")); callback(task) immediately (honours the explicit binding choice).
---
--- Otherwise shows a two-item Snacks select:
---   • "current: <active-slug>"  →  callback(active_slug)
---   • "select scope…"           →  opens a .cue/ subdirectory list, then callback(chosen)
---
---@param type string      artifact type ("task" bypasses the dialog)
---@param task string|nil  pre-set scope override, or nil to prompt
---@param callback function  called with the resolved task slug (string)
function M.confirm_scope(type, task, callback)
  if type == "task" then
    callback("master")
    return
  end

  if task ~= nil then
    callback(task)
    return
  end

  local Snacks = require('snacks')
  local active = M.get_active_task().context

  local items = {
    { label = "current: " .. active, value = active      },
    { label = "select scope...",     value = "__pick__"  },
  }

  Snacks.picker.select(items, {
    prompt = "Scope for new artifact:",
    format_item = function(item) return item.label end,
  }, function(choice)
    if not choice then return end
    if choice.value ~= "__pick__" then
      callback(choice.value)
      return
    end
    -- Enumerate .cue/ subdirectories (mirrors list_task_contexts in picker.lua).
    local cue_dir = ".cue"
    if vim.fn.isdirectory(cue_dir) == 0 then
      vim.notify("No .cue directory found", vim.log.levels.ERROR)
      return
    end
    local contexts = {}
    for name, kind in vim.fs.dir(cue_dir) do
      if kind == "directory" then
        table.insert(contexts, name)
      end
    end
    table.sort(contexts)
    if #contexts == 0 then
      vim.notify("No task contexts found", vim.log.levels.INFO)
      return
    end
    Snacks.picker.select(contexts, { prompt = "Select scope:" }, function(ctx)
      if ctx then callback(ctx) end
    end)
  end)
end

-- ─── Public API ───────────────────────────────────────────────────────────────

--- Open the current cue context file in the editor
function M.open_context()
  local cmd = { 'cue', 'context', 'path' }
  local output = M.execute_command(cmd)

  if not output or output == "" then
    vim.notify("Context not found, initializing...", vim.log.levels.INFO)
    local init_output, init_err = M.execute_command({ 'cue', 'context', 'init' })
    if not init_output then
      vim.notify("Error initializing context: " .. (init_err or "unknown"), vim.log.levels.ERROR)
      return
    end
    local err
    output, err = M.execute_command(cmd)
    if not output or output == "" then
      vim.notify("Error: " .. (err or "No current context found after init"), vim.log.levels.ERROR)
      return
    end
  end

  local path = vim.trim(output)
  if vim.fn.filereadable(path) == 0 then
    vim.notify("Error: Context file does not exist: " .. path, vim.log.levels.ERROR)
    return
  end

  vim.cmd.edit(path)
end

--- Open the task context's log file and jump to the end.
--- Default is the active task context (from `cue status`); pass a task slug
--- (e.g. "master") to override.
---@param task string|nil  task slug (nil = active context)
function M.open_log(task)
  task = task or M.get_active_task().context
  if not task or task == "" then
    vim.notify("Error: Could not determine active task context", vim.log.levels.ERROR)
    return
  end

  local path = ".cue/" .. task .. "/log.md"
  if vim.fn.filereadable(path) == 0 then
    vim.notify("Error: Log file does not exist: " .. path, vim.log.levels.ERROR)
    return
  end

  vim.cmd.edit(path)
  vim.cmd("normal! G")
end

--- Add a new artifact file via `cue add` and open it for editing
---@param filename string
---@param opts table|nil
---@return string|nil, string|nil
function M.add(filename, opts)
  opts = opts or {}

  if not filename or filename == "" then
    vim.notify("Error: filename is required", vim.log.levels.ERROR)
    return nil
  end

  local cmd = { 'cue', 'add', filename }

  if opts.category then
    table.insert(cmd, '--type')
    table.insert(cmd, opts.category)
  end

  if opts.root then
    table.insert(cmd, '--root')
  end

  if opts.task then
    table.insert(cmd, '--task')
    table.insert(cmd, opts.task)
  end

  if opts.frontmatter then
    for k, v in pairs(opts.frontmatter) do
      if type(v) == "table" then
        -- Array value: emit one --frontmatter flag per element. A repeated
        -- key becomes a YAML list in the output (see `cue add`). An empty
        -- table yields no flags (no frontmatter value).
        for _, el in ipairs(v) do
          table.insert(cmd, '--frontmatter')
          table.insert(cmd, string.format("%s=%s", k, el))
        end
      else
        table.insert(cmd, '--frontmatter')
        table.insert(cmd, string.format("%s=%s", k, v))
      end
    end
  end

  if opts.commit and (opts.category == "trace" or opts.category == "tmp") then
    table.insert(cmd, '--commit')
    table.insert(cmd, opts.commit)
  end

  if opts.force then
    table.insert(cmd, '--force')
  end

  local obj = vim.system(cmd, { text = true }):wait()

  if obj.code ~= 0 then
    local error_msg = (obj.stderr and obj.stderr ~= "") and obj.stderr or obj.stdout
    error_msg = vim.trim(error_msg or "Unknown error")
    vim.notify("Cue Error: " .. error_msg, vim.log.levels.ERROR)
    return nil, error_msg
  end

  local filepath = vim.trim(obj.stdout or "")
  if filepath == "" then
    vim.notify("Error: failed to get file path from cue add output", vim.log.levels.ERROR)
    return nil
  end

  vim.notify("Successfully added: " .. filename, vim.log.levels.INFO)
  vim.cmd.edit(filepath)
  vim.cmd("normal! G")
  vim.cmd("startinsert!")

  return filepath
end

--- Prompt for a task slug, then create the task card on master.
--- Tasks always live in .cue/master/task/; no scope dialog is shown.
--- The slug is used as the filename stem (e.g. "my-feature" → "my-feature.md").
function M.add_task()
  local Snacks = require('snacks')
  Snacks.input({
    prompt = "Task slug (e.g. my-feature):",
    win = { row = 0.3 },
  }, function(slug)
    if not slug or slug == "" then return end
    -- Normalise: lowercase, spaces/underscores → hyphens, strip non-slug chars.
    slug = M.slugify(slug)
    if not slug or slug == "" then
      vim.notify("Error: slug is empty after normalisation", vim.log.levels.ERROR)
      return
    end
    local filename = slug .. ".md"
    local defaults = config.TYPE_DEFAULTS["task"] or {}
    M.add(filename, {
      category    = "task",
      task        = "master",
      root        = true,
      frontmatter = defaults,
    })
  end)
end

--- Prompt for a title, then confirm scope, then add an artifact of the given type.
--- When task is non-nil the scope dialog is skipped (caller already pinned scope).
---@param type string  artifact type (e.g. "task", "todo", "plan", "doc")
---@param task string|nil  override task context (nil = prompt via confirm_scope)
function M.add_with_title(type, task)
  local Snacks = require('snacks')
  Snacks.input({
    prompt = "Title (" .. type .. "):",
    win = { row = 0.3 },
  }, function(title)
    if not title or title == "" then return end
    M.confirm_scope(type, task, function(target_task)
      local filename = M.slugify(title) .. ".md"
      local defaults = config.TYPE_DEFAULTS[type] or {}
      local frontmatter = vim.tbl_extend("force", { title = title }, defaults)
      M.add(filename, {
        category    = type,
        task        = target_task,
        root        = type == "task",
        frontmatter = frontmatter,
      })
    end)
  end)
end

--- Prompt for a file path, then confirm scope, then add a root artifact of the given type.
--- When task is non-nil the scope dialog is skipped (caller already pinned scope).
---@param type string  artifact type (e.g. "note")
---@param task string|nil  override task context (nil = prompt via confirm_scope)
function M.add_with_path(type, task)
  local Snacks = require('snacks')
  Snacks.input({
    prompt = "Path (" .. type .. "):",
    completion = "file",
    win = { row = 0.3 },
  }, function(path)
    if not path or path == "" then return end
    M.confirm_scope(type, task, function(target_task)
      local defaults = config.TYPE_DEFAULTS[type] or {}
      M.add(path, {
        category    = type,
        task        = target_task,
        root        = true,
        frontmatter = defaults,
      })
    end)
  end)
end

--- Prompt for a spec path, then confirm scope, then add a root spec artifact.
--- When task is non-nil the scope dialog is skipped (caller already pinned scope).
---@param task string|nil  override task context (nil = prompt via confirm_scope)
function M.add_spec(task)
  local Snacks = require('snacks')
  Snacks.input({
    prompt = "Spec path:",
    completion = "file",
    win = { row = 0.3 },
  }, function(path)
    if not path or path == "" then return end
    M.confirm_scope("spec", task, function(target_task)
      M.add(path, { category = "spec", task = target_task, root = true })
    end)
  end)
end

return M
