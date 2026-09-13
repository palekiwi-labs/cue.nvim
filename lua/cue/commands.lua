--- Register all :Cue* user commands
local M = {}

--- Generic arg parser shared by :CuePick and :CueAdd.
--- Tokens are whitespace-separated. Three shapes:
---   "note"          -> positional
---   "force" / "all" -> flag (must be in KNOWN_FLAGS)
---   "task=master"   -> kwargs (value is everything after first =)
--- No quote handling; values with spaces will break. Acceptable for prototype.
local KNOWN_FLAGS = { force = true, all = true }

local function parse_args(args)
  local out = { positional = {}, flags = {}, kwargs = {} }
  for token in vim.gsplit(args or "", "%s+", true) do
    if token ~= "" then
      local k, v = token:match("^([%w_]+)=(.+)$")
      if k then
        out.kwargs[k] = v
      elseif KNOWN_FLAGS[token] then
        out.flags[token] = true
      else
        table.insert(out.positional, token)
      end
    end
  end
  return out
end

--- Build opts table for core.add() from parsed args.
--- Known kwarg (context/task) becomes an opts field;
--- remaining kwargs become frontmatter key=value pairs.
local function build_add_opts(category, parsed)
  local frontmatter = nil
  for k, v in pairs(parsed.kwargs) do
    if k ~= "context" and k ~= "task" then
      frontmatter = frontmatter or {}
      frontmatter[k] = v
    end
  end
  return {
    category    = category == "spec" and nil or category,
    force       = parsed.flags.force and true or nil,
    context     = parsed.kwargs.context or parsed.kwargs.task,
    frontmatter = frontmatter,
  }
end

function M.setup()
  local core   = require('cue.core')
  local picker = require('cue.picker')

  local function select_category(callback)
    local Snacks = require('snacks')
    -- The seven types in the model. `todo` and `doc` are gone: a checklist
    -- is a plan and a single deferred obligation is a task, while synthesised
    -- knowledge is a note and anything about a revision is a trace.
    local items = {
      { label = "task",  desc = "Task artifact" },
      { label = "note",  desc = "Note" },
      { label = "spec",  desc = "Specification" },
      { label = "plan",  desc = "Plan artifact" },
      { label = "trace", desc = "Trace / debug artifact" },
      { label = "bin",   desc = "Binary artifact" },
      { label = "tmp",   desc = "Temporary artifact" },
    }
    Snacks.picker.select(items, {
      prompt = "Select artifact type:",
      format_item = function(item)
        return string.format("%-8s  %s", item.label, item.desc)
      end,
    }, function(choice)
      if choice then callback(choice.label) end
    end)
  end

  local function prompt_filename(category, callback)
    local Snacks = require('snacks')
    Snacks.input({
      prompt = "Artifact filename (" .. category .. "):",
      completion = "file",
      win = { row = 0.3 },
    }, function(value)
      if not value or value == "" then
        value = "index.md"
      end
      callback(value)
    end)
  end

  local function run_wizard()
    select_category(function(category)
      -- task/note share the slug-prompt flow with a wizard parent prompt.
      if category == "task" or category == "note" then
        core.prompt_parent(function(parent)
          local fm = {}
          if parent then fm.parent = parent end
          core.add_with_slug(category, nil, fm)
        end)
        return
      end

      prompt_filename(category, function(filename)
        -- confirm_scope shows the scope dialog for non-task types.
        core.confirm_scope(category, nil, function(context)
          core.prompt_parent(function(parent)
            local fm = {}
            if parent then fm.parent = parent end
            core.add(filename, {
              category    = category == "spec" and nil or category,
              context     = context,
              frontmatter = fm,
            })
          end)
        end)
      end)
    end)
  end

  -- :CuePick [type] [key=value ...] [all]
  -- Examples:
  --   :CuePick
  --   :CuePick note
  --   :CuePick note task=master
  --   :CuePick note all
  vim.api.nvim_create_user_command('CuePick', function(args)
    local parsed = parse_args(args.args)
    local opts = {}
    for k, v in pairs(parsed.kwargs) do opts[k] = v end
    for k in pairs(parsed.flags) do opts[k] = true end
    if parsed.positional[1] then opts.type = parsed.positional[1] end
    picker.pick_artifacts(opts)
  end, {
    nargs = "*",
    desc  = "Open cue artifact picker (e.g. :CuePick note task=master all)",
  })

  -- :CueAdd [type] [filename] [key=value ...] [force]
  -- No args           -> full wizard (type and filename prompts)
  -- Type only         -> prompt filename
  -- Type + filename   -> no prompts
  -- Extra key=value   -> task becomes an opt, rest become frontmatter
  vim.api.nvim_create_user_command('CueAdd', function(args)
    local parsed = parse_args(args.args)
    if #parsed.positional == 0 then return run_wizard() end
    local category = parsed.positional[1]
    local filename = parsed.positional[2]
    local opts     = build_add_opts(category, parsed)
    local function go(fn) core.add(fn, opts) end
    if filename then
      go(filename)
    else
      prompt_filename(category, go)
    end
  end, {
    nargs = "*",
    desc  = "Add a cue artifact (no args = wizard; e.g. :CueAdd note weekly.md context=my-feature)",
  })

  -- :CueLog [task]
  -- No arg   -> open active task context log
  -- <slug>   -> open that task context's log (e.g. :CueLog master)
  vim.api.nvim_create_user_command('CueLog', function(args)
    local task = vim.trim(args.args or "")
    core.open_log(task ~= "" and task or nil)
  end, {
    nargs = "?",
    desc  = "Open cue log file (optional task slug override, e.g. :CueLog master)",
  })

  -- :CueContext
  -- Open (or initialize) the current branch's context file.
  vim.api.nvim_create_user_command('CueContext', function()
    core.open_context()
  end, {
    nargs = 0,
    desc  = "Open (or initialize) current cue context file",
  })

  -- :CueActiveTask
  -- Open the active task card in a new buffer. Notifies when the global
  -- (master) context is active (no associated task).
  vim.api.nvim_create_user_command('CueActiveTask', function()
    core.open_active_task()
  end, {
    nargs = 0,
    desc  = "Open the active task card",
  })
end

return M
