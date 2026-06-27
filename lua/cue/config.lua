local M = {}

-- Status values considered "done" per cue framework vocabulary.
-- Framework statuses: open, closed, in-progress, complete.
M.DONE_STATUSES = {
  closed = true,
  complete = true,
}

M.TYPE_DEFAULTS = {
  task = { status = "open", priority = "normal" },
  todo = { status = "open", priority = "normal" },
  plan = { status = "open", priority = "normal" },
  note = { status = "open" },
}

M.category_highlights = {
  spec  = "CueCategorySpec",
  plan  = "CueCategoryPlan",
  task  = "CueCategoryTask",
  todo  = "CueCategoryTodo",
  note  = "CueCategoryNote",
  doc   = "CueCategoryDoc",
  bin   = "CueCategoryBin",
  trace = "CueCategoryTrace",
  tmp   = "CueCategoryTmp",
  ref   = "CueCategoryRef",
}

-- Resolved config (populated by apply())
M.values = {}

local defaults = {}

--- Merge user opts over defaults and store in M.values
---@param opts table|nil
function M.apply(opts)
  M.values = vim.tbl_deep_extend("force", defaults, opts or {})
end

return M
