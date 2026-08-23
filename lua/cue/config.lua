local M = {}

-- Status values considered "done" per cue framework vocabulary.
-- Framework statuses: open, closed, in-progress, complete.
M.DONE_STATUSES = {
  closed = true,
  complete = true,
}

-- Sort rank for the frontmatter `priority` field, used as the secondary
-- sort key in the task picker (after the marker). Unknown/missing values
-- sort last (callers map to 99).
M.PRIORITY_RANK = {
  critical = 0,
  high     = 1,
  normal   = 2,
  low      = 3,
}

M.TYPE_DEFAULTS = {
  task = { status = "open", priority = "normal", kind = "build" },
  todo = { status = "open", priority = "normal" },
  plan = { status = "open", priority = "normal" },
  note = { status = "open" },
}

-- Type-intrinsic root placement policy for the markdown types that share the
-- slug-prompt creation flow (task/note/todo). Drives `slug_artifact_plan`.
--   task -> root (flat, lives on master)
--   note -> root (flat, stored root-level per cue skill)
--   todo -> NOT root (pinned / point-in-time)
M.SLUG_ROOT = {
  task = true,
  note = true,
  todo = false,
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

M.kind_highlights = {
  research = "CueKindResearch",
  design   = "CueKindDesign",
  build    = "CueKindBuild",
  review   = "CueKindReview",
  coord    = "CueKindCoord",
}

-- Status values hidden from the task BOARD picker (<C-t>). Operator
-- decisions 2026-08-22 and 2026-08-23: complete and closed cards are
-- archive noise (dedicated done picker: <space>ec) and "inbox" is an
-- idea-intake status with a dedicated picker (<space>ei). Applied ONLY
-- when opts.board is set -- other task pickers (<space>et, <C-f>
-- drill-in, all-scopes) still list every status.
M.HIDDEN_TASK_STATUSES = {
  complete = true,
  closed   = true,
  inbox    = true,
}

-- Nerd Font glyphs for the task picker priority column (single-width
-- carets, Jira-style). Operator decision 2026-08-22: flag ONLY critical
-- and high; normal is the norm and low is rare clutter, so they render
-- blank. Byte sequences are UTF-8 encodings of the codepoints:
--   critical  U+F102 angle-double-up (red)
--   high      U+F106 angle-up        (orange)
M.PRIORITY_GLYPH = {
  critical = "\xEF\x84\x82",
  high     = "\xEF\x84\x86",
}

-- Nerd Font glyphs for the task picker marker column (single-width).
-- Display-only translation of the internal sentinel markers returned
-- by core.task_marker_for; sorting still compares the sentinels
-- ("*" active, "!" in-progress, " " none), so this map never affects
-- ordering. Same FontAwesome range as the priority carets, chosen for
-- distinct silhouettes: star (active) vs circle-arrows (in-progress)
-- vs carets (priority).
--   "*" active        U+F005 star     (cyan)
--   "!" in-progress   U+F021 refresh  (yellow)
M.MARKER_GLYPH = {
  ["*"] = "\xEF\x80\x85",
  ["!"] = "\xEF\x80\xA1",
}

M.priority_highlights = {
  critical = "CuePriorityCritical",
  high     = "CuePriorityHigh",
  normal   = "CuePriorityNormal",
  low      = "CuePriorityLow",
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
