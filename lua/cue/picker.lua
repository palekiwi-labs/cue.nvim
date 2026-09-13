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

return M
