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

--- Execute a shell command and return stdout
---@param cmd string
---@return string|nil, string|nil
function M.execute_command(cmd)
  local handle = io.popen(cmd)
  if not handle then
    return nil, "Failed to execute command"
  end
  local result = handle:read("*a")
  local success = handle:close()
  if not success then
    return nil, "Command failed"
  end
  return result
end

--- Parse a JSON string via vim's json_decode
---@param json_str string
---@return any, string|nil
function M.parse_json(json_str)
  local ok, result = pcall(vim.fn.json_decode, json_str)
  if not ok then
    return nil, "Failed to parse JSON"
  end
  return result
end

--- Get the current git branch name (with / replaced by -)
---@return string|nil
function M.get_current_branch()
  local result = vim.fn.system('git rev-parse --abbrev-ref HEAD 2>/dev/null')
  if vim.v.shell_error == 0 then
    local branch = result:gsub("%s+", "")
    return branch:gsub("/", "-")
  end
  return nil
end

-- ─── Public API ───────────────────────────────────────────────────────────────

--- Open the current cue context file in the editor
function M.open_context()
  local cmd = "cue context path 2>/dev/null"
  local output = M.execute_command(cmd)

  if not output or output == "" then
    vim.notify("Context not found, initializing...", vim.log.levels.INFO)
    local init_output, init_err = M.execute_command("cue context init 2>/dev/null")
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

--- Open the branch's log file and jump to the end.
--- Default branch is the current git branch; pass a branch name to override.
---@param branch string|nil  branch name (nil = current)
function M.open_log(branch)
  branch = branch or M.get_current_branch()
  if not branch then
    vim.notify("Error: Could not determine git branch", vim.log.levels.ERROR)
    return
  end

  local path = ".cue/" .. branch .. "/spec/log.md"
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

  if opts.branch then
    table.insert(cmd, '--branch')
    table.insert(cmd, opts.branch)
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

--- Prompt for a title, then add an artifact of the given type
---@param type string  artifact type (e.g. "task", "todo", "plan", "doc")
---@param branch string|nil  override branch
function M.add_with_title(type, branch)
  local Snacks = require('snacks')
  Snacks.input({
    prompt = "Title (" .. type .. "):",
    win = { row = 0.3 },
  }, function(title)
    if not title or title == "" then return end

    -- Tasks are special: they ALWAYS live on the master branch
    local target_branch = branch
    if type == "task" then
      target_branch = "master"
    end

    local filename = M.slugify(title) .. ".md"
    local defaults = config.TYPE_DEFAULTS[type] or {}
    local frontmatter = vim.tbl_extend("force", { title = title }, defaults)

    M.add(filename, {
      category    = type,
      branch      = target_branch,
      frontmatter = frontmatter,
    })
  end)
end

--- Prompt for a file path, then add a root artifact of the given type.
--- The typed path is the artifact's address (so subdirectories can be
--- controlled); only the type's default frontmatter is applied (no title).
---@param type string  artifact type (e.g. "note")
---@param branch string|nil  override branch
function M.add_with_path(type, branch)
  local Snacks = require('snacks')
  Snacks.input({
    prompt = "Path (" .. type .. "):",
    completion = "file",
    win = { row = 0.3 },
  }, function(path)
    if not path or path == "" then return end
    local defaults = config.TYPE_DEFAULTS[type] or {}
    M.add(path, {
      category    = type,
      branch      = branch,
      root        = true,
      frontmatter = defaults,
    })
  end)
end

--- Prompt for a spec path, then add a root spec artifact
---@param branch string|nil
function M.add_spec(branch)
  local Snacks = require('snacks')
  Snacks.input({
    prompt = "Spec path:",
    completion = "file",
    win = { row = 0.3 },
  }, function(path)
    if not path or path == "" then return end
    M.add(path, { category = "spec", branch = branch, root = true })
  end)
end

return M
