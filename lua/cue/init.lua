--- cue.nvim — public API
---
--- Usage in your config:
---   require('cue').setup({})
---
--- All public functions are re-exported here so callers can do:
---   local cue = require('cue')
---   cue.pick_artifacts({ type = "todo" })
---   cue.add_with_title("todo")
---   etc.

local M = {}

--- Bootstrap the plugin: apply config, set highlights, register commands.
---@param opts table|nil
function M.setup(opts)
  require('cue.config').apply(opts)
  require('cue.highlights').setup()
  require('cue.commands').setup()
end

-- ─── Re-export core functions ─────────────────────────────────────────────────

--- Open the current cue context file
function M.open_context()
  return require('cue.core').open_context()
end

--- Open the active task context log file
---@param task string|nil  task slug (nil = active context)
function M.open_log(task)
  return require('cue.core').open_log(task)
end

--- Open the active task card (the .cue/master/task/<slug>.md for the active
--- context). Notifies and does nothing when the global (master) context is
--- active.
function M.open_active_task()
  return require('cue.core').open_active_task()
end

--- Add a new artifact via `cue add`
---@param filename string
---@param opts table|nil
function M.add(filename, opts)
  return require('cue.core').add(filename, opts)
end

--- Switch the active cue context to the given task slug
---@param slug string  task slug or "master"
function M.switch_context(slug)
  return require('cue.core').switch_context(slug)
end

--- Prompt for a task slug, create the task card on master
function M.add_task()
  return require('cue.core').add_task()
end

--- Prompt for title, then add an artifact of the given type
---@param type string
---@param task string|nil  task context (nil = active)
function M.add_with_title(type, task)
  return require('cue.core').add_with_title(type, task)
end

--- Prompt for a file path, then add a root artifact of the given type
---@param type string
---@param task string|nil  task context (nil = active)
function M.add_with_path(type, task)
  return require('cue.core').add_with_path(type, task)
end

--- Prompt for a spec path, then add a root spec artifact
---@param task string|nil  task context (nil = active)
function M.add_spec(task)
  return require('cue.core').add_spec(task)
end

-- ─── Re-export picker functions ───────────────────────────────────────────────

--- Open Telescope artifact picker
---@param opts table|nil
function M.pick_artifacts(opts)
  return require('cue.picker').pick_artifacts(opts)
end

--- Open Telescope context file picker
function M.pick_context()
  return require('cue.picker').pick_context()
end

--- Guided task-context→type→artifact picker
function M.ui_pick()
  return require('cue.picker').ui_pick()
end

--- Open task-context selector, then show its artifacts
function M.pick_task_context_artifacts()
  return require('cue.picker').pick_task_context_artifacts()
end

--- Open task-context selector, then open that context's log file
function M.pick_logs()
  return require('cue.picker').pick_logs()
end

return M
