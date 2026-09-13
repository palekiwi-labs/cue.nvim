--- cue.nvim — public API
---
--- Usage in your config:
---   require('cue').setup({})
---
--- All public functions are re-exported here so callers can do:
---   local cue = require('cue')
---   cue.pick_artifacts({ type = "note" })
---   cue.add_with_title("note")
---   etc.

local M = {}

--- Bootstrap the plugin: apply config and set highlights.
---
--- The plugin registers no `:Cue*` user commands. Every entry point is a
--- function on this module; bind the ones you use to keys.
---@param opts table|nil
function M.setup(opts)
  require('cue.config').apply(opts)
  require('cue.highlights').setup()
end

-- ─── Re-export core functions ─────────────────────────────────────────────────

--- Open the current cue context file
function M.open_context()
  return require('cue.core').open_context()
end

--- Add a new artifact via `cue add`
---@param filename string
---@param opts table|nil
function M.add(filename, opts)
  return require('cue.core').add(filename, opts)
end

--- Associate a cue context with the current git branch
---@param slug string  context slug
---@param opts table|nil  supports: dir (string, -C), store (string, --store)
function M.switch_context(slug, opts)
  return require('cue.core').switch_context(slug, opts)
end

--- Prompt for a task slug, create the task card
---@param context string|nil  context slug (nil = active/prompt)
function M.add_task(context)
  return require('cue.core').add_task(context)
end

--- Prompt for a slug, then add a markdown artifact (task/note).
---@param type string
---@param context string|nil  context slug (nil = active/prompt)
function M.add_with_slug(type, context)
  return require('cue.core').add_with_slug(type, context)
end

--- Prompt for title, then add an artifact of the given type
---@param type string
---@param context string|nil  context slug (nil = active/prompt)
function M.add_with_title(type, context)
  return require('cue.core').add_with_title(type, context)
end

--- Prompt for a file path (verbatim, extension preserved), then add an
--- artifact of the given type with the type-intrinsic root policy
---@param type string
---@param context string|nil  context slug (nil = active/prompt)
function M.add_with_path(type, context)
  return require('cue.core').add_with_path(type, context)
end

--- Prompt for a spec path, then add a spec artifact
---@param context string|nil  context slug (nil = active/prompt)
function M.add_spec(context)
  return require('cue.core').add_spec(context)
end

-- ─── Re-export picker functions ───────────────────────────────────────────────

--- Open Telescope artifact picker
---@param opts table|nil
function M.pick_artifacts(opts)
  return require('cue.picker').pick_artifacts(opts)
end

--- Browse the active context's artifacts (task/spec/plan/note/trace) (<C-s>).
--- Resolves active context via `cue status --json`.
---@param opts table|nil  supports: dir (`cue -C`), store (`cue --store`)
function M.pick_active_context_artifacts(opts)
  return require('cue.picker').pick_active_context_artifacts(opts)
end

--- Browse one context's artifacts (task/spec/plan/note/trace) as a single
--- searchable, type-grouped list. The context is explicit: there is no
--- fallback to the active context, and Enter opens without activating.
---@param context string  context slug (required)
---@param opts table|nil  supports: dir (`cue -C`), store (`cue --store`)
function M.pick_context_artifacts(context, opts)
  return require('cue.picker').pick_context_artifacts(context, opts)
end

--- Open Telescope context file picker
function M.pick_context()
  return require('cue.picker').pick_context()
end

return M
