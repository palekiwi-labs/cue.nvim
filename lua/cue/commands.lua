--- Register all :Cue* user commands
local M = {}

function M.setup()
  local core   = require('cue.core')
  local log    = require('cue.log')
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

  -- :CueLog [title]
  vim.api.nvim_create_user_command('CueLog', function(args)
    local title = vim.trim(args.args)
    if title ~= "" then
      log.log_add({ title = title, found = {}, decided = {}, open = {} })
    else
      log.log_form()
    end
  end, {
    nargs = "*",
    desc  = "Add a cue log entry (no args = open form, with args = title-only fast path)",
  })

  -- :CueAdd
  vim.api.nvim_create_user_command('CueAdd', function()
    select_category(function(category)
      prompt_filename(category, function(filename)
        prompt_root_and_add(filename, { category = category == "spec" and nil or category })
      end)
    end)
  end, {
    nargs = 0,
    desc  = "Add a new cue artifact (prompts for type, filename, then root status)",
  })

  -- :CueAddBin <filename>
  vim.api.nvim_create_user_command('CueAddBin', function(args)
    local filename = args.args
    if not filename or filename == "" then
      vim.notify("Usage: :CueAddBin <filename>", vim.log.levels.ERROR)
      return
    end
    prompt_root_and_add(filename, { category = 'bin' })
  end, {
    nargs    = 1,
    complete = 'file',
    desc     = "Add a new cue bin artifact and open it for editing",
  })

  -- :CueAddTrace <filename>
  vim.api.nvim_create_user_command('CueAddTrace', function(args)
    local filename = args.args
    if not filename or filename == "" then
      vim.notify("Usage: :CueAddTrace <filename>", vim.log.levels.ERROR)
      return
    end
    prompt_root_and_add(filename, { category = 'trace' })
  end, {
    nargs    = 1,
    complete = 'file',
    desc     = "Add a new cue trace artifact and open it for editing",
  })

  -- :CueAddTmp <filename>
  vim.api.nvim_create_user_command('CueAddTmp', function(args)
    local filename = args.args
    if not filename or filename == "" then
      vim.notify("Usage: :CueAddTmp <filename>", vim.log.levels.ERROR)
      return
    end
    prompt_root_and_add(filename, { category = 'tmp' })
  end, {
    nargs    = 1,
    complete = 'file',
    desc     = "Add a new cue tmp artifact and open it for editing",
  })

  -- :CueAddRef <filename>
  vim.api.nvim_create_user_command('CueAddRef', function(args)
    local filename = args.args
    if not filename or filename == "" then
      vim.notify("Usage: :CueAddRef <filename>", vim.log.levels.ERROR)
      return
    end
    prompt_root_and_add(filename, { category = 'ref' })
  end, {
    nargs    = 1,
    complete = 'file',
    desc     = "Add a new cue ref artifact and open it for editing",
  })

  -- :CueAddDoc <filename>
  vim.api.nvim_create_user_command('CueAddDoc', function(args)
    local filename = args.args
    if not filename or filename == "" then
      vim.notify("Usage: :CueAddDoc <filename>", vim.log.levels.ERROR)
      return
    end
    prompt_root_and_add(filename, { category = 'doc' })
  end, {
    nargs    = 1,
    complete = 'file',
    desc     = "Add a new cue doc artifact and open it for editing",
  })

  -- :CuePick [type]
  vim.api.nvim_create_user_command('CuePick', function(args)
    local type_arg = vim.trim(args.args)
    local opts = {}
    if type_arg ~= "" then
      opts.type = type_arg
    end
    picker.pick_artifacts(opts)
  end, {
    nargs = "?",
    desc  = "Open cue artifact picker (optional type filter)",
  })
end

return M
