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

--- Open the current branch log file
function M.open_log(branch)
  return require('cue.core').open_log(branch)
end

--- Add a new artifact via `cue add`
---@param filename string
---@param opts table|nil
function M.add(filename, opts)
  return require('cue.core').add(filename, opts)
end

--- Prompt for title, then add an artifact of the given type
---@param type string
---@param branch string|nil
function M.add_with_title(type, branch)
  return require('cue.core').add_with_title(type, branch)
end

--- Prompt for a file path, then add a root artifact of the given type
---@param type string
---@param branch string|nil
function M.add_with_path(type, branch)
  return require('cue.core').add_with_path(type, branch)
end

--- Prompt for a spec path, then add a root spec artifact
---@param branch string|nil
function M.add_spec(branch)
  return require('cue.core').add_spec(branch)
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

--- Guided branch→type→artifact picker
function M.ui_pick()
  return require('cue.picker').ui_pick()
end

--- Open branch selector, then artifact picker
function M.pick_branch_artifacts()
  return require('cue.picker').pick_branch_artifacts()
end

--- Open branch selector, then open that branch's log file
function M.pick_logs()
  return require('cue.picker').pick_logs()
end

return M
