--- Register all :Cue* user commands
local M = {}

--- Generic arg parser shared by :CuePick and :CueAdd.
--- Tokens are whitespace-separated. Three shapes:
---   "todo"          -> positional
---   "root" / "all"  -> flag (must be in KNOWN_FLAGS)
---   "branch=master" -> kwargs (value is everything after first =)
--- No quote handling; values with spaces will break. Acceptable for prototype.
local KNOWN_FLAGS = { root = true, force = true, all = true }

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
--- Known kwargs (branch, commit) become opts fields;
--- remaining kwargs become frontmatter key=value pairs.
local function build_add_opts(category, parsed)
  local frontmatter = nil
  for k, v in pairs(parsed.kwargs) do
    if k ~= "branch" and k ~= "commit" then
      frontmatter = frontmatter or {}
      frontmatter[k] = v
    end
  end
  return {
    category    = category == "spec" and nil or category,
    root        = parsed.flags.root and true or nil,
    force       = parsed.flags.force and true or nil,
    branch      = parsed.kwargs.branch,
    commit      = parsed.kwargs.commit,
    frontmatter = frontmatter,
  }
end

function M.setup()
  local core   = require('cue.core')
  local picker = require('cue.picker')

  local function prompt_root_and_add(filename, opts)
    local Snacks = require('snacks')
    local root_items = {
      { label = "No",  root = false, desc = "Save as pinned artifact (timestamped, default)" },
      { label = "Yes", root = true,  desc = "Save in branch-specific directory" },
    }
    Snacks.picker.select(root_items, {
      prompt = "Save in branch root?",
      format_item = function(item)
        return string.format("%-3s  %s", item.label, item.desc)
      end,
    }, function(choice)
      if choice then
        opts.root = choice.root
        core.add(filename, opts)
      end
    end)
  end

  local function select_category(callback)
    local Snacks = require('snacks')
    local items = {
      { label = "task",  desc = "Task artifact" },
      { label = "todo",  desc = "TODO artifact" },
      { label = "spec",  desc = "Specification" },
      { label = "plan",  desc = "Plan artifact" },
      { label = "doc",   desc = "Documentation artifact" },
      { label = "trace", desc = "Trace / debug artifact" },
      { label = "bin",   desc = "Binary artifact" },
      { label = "tmp",   desc = "Temporary artifact" },
      { label = "ref",   desc = "Reference artifact" },
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
      prompt_filename(category, function(filename)
        prompt_root_and_add(filename, { category = category == "spec" and nil or category })
      end)
    end)
  end

  -- :CuePick [type] [key=value ...] [all]
  -- Examples:
  --   :CuePick
  --   :CuePick todo
  --   :CuePick todo branch=master
  --   :CuePick todo all
  vim.api.nvim_create_user_command('CuePick', function(args)
    local parsed = parse_args(args.args)
    local opts = {}
    for k, v in pairs(parsed.kwargs) do opts[k] = v end
    for k in pairs(parsed.flags) do opts[k] = true end
    if parsed.positional[1] then opts.type = parsed.positional[1] end
    picker.pick_artifacts(opts)
  end, {
    nargs = "*",
    desc  = "Open cue artifact picker (e.g. :CuePick todo branch=master all)",
  })

  -- :CueAdd [type] [filename] [key=value ...] [root] [force]
  -- No args           -> full wizard (type, filename, root status prompts)
  -- Type only         -> prompt filename, no root prompt (pinned by default)
  -- Type + filename   -> no prompts unless root flag forces root placement
  -- Extra key=value   -> branch/commit become opts, rest become frontmatter
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
    desc  = "Add a cue artifact (no args = wizard; e.g. :CueAdd todo weekly.md root branch=master)",
  })

  -- :CueLog [branch]
  -- No arg  -> open current branch log
  -- <branch> -> open that branch's log
  vim.api.nvim_create_user_command('CueLog', function(args)
    local branch = vim.trim(args.args or "")
    core.open_log(branch ~= "" and branch or nil)
  end, {
    nargs = "?",
    desc  = "Open cue log file (optional branch override)",
  })

  -- :CueContext
  -- Open (or initialize) the current branch's context file.
  vim.api.nvim_create_user_command('CueContext', function()
    core.open_context()
  end, {
    nargs = 0,
    desc  = "Open (or initialize) current cue context file",
  })
end

return M
