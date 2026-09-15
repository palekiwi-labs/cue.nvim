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
	high = 1,
	normal = 2,
	low = 3,
}

-- Frontmatter defaults per artifact type. Every type starts at "open":
-- `inbox` was removed from task status, because a captured idea becomes a
-- note and a task is therefore created deliberately and triaged as it is
-- written. Tasks carry no `kind` default either -- `kind` is a context
-- field (work/coord/reference) and says what ends the context, not what a
-- task is.
M.TYPE_DEFAULTS = {
	task = { status = "open", priority = "normal" },
	plan = { status = "open", priority = "normal" },
	note = { status = "open" },
}

-- Membership test for the slug-prompt creation flow, which slugifies the
-- entered name and forces a .md extension. Drives `slug_artifact_plan`.
--
-- This is the surviving half of the deleted SLUG_ROOT table. Root placement
-- is gone -- every markdown artifact is a named file at <type>/<name>.md, so
-- there is no root/pinned distinction left to encode -- but the membership
-- guard is load-bearing on its own: slugifying destroys a real path, so
-- types whose filename is a caller-chosen path (spec/index.md, a nested
-- note, a trace) belong to the path flow instead. See `path_artifact_plan`.
M.SLUG_TYPES = {
	task = true,
	note = true,
}

-- Display order for the artifact picker's type groups. PRESENTATION ONLY:
-- it arranges rows cue already returned and never gates them. cue owns the
-- artifact universe (`cue list` reports every type it recognises and nothing
-- else), so this table restates no vocabulary -- a type absent from it
-- still renders, in the trailing group, with a fallback badge and colour.
-- review sits after trace (it carries decoded metadata, unlike the opaque
-- bin/tmp tail) and before bin.
M.ARTIFACT_TYPE_ORDER = {
	task = 1,
	spec = 2,
	plan = 3,
	note = 4,
	trace = 5,
	review = 6,
	bin = 7,
	tmp = 8,
}

-- Badge labels for the picker's type column. Sparse: a type not listed
-- renders as its uppercased name, so a new cue type needs no plugin
-- release to appear legibly. `review` maps to REV because the fixed-width
-- badge column is five cells and "REVIEW" truncates.
M.TYPE_BADGES = {
	review = "REV",
}

M.category_highlights = {
	spec = "CueCategorySpec",
	plan = "CueCategoryPlan",
	task = "CueCategoryTask",
	todo = "CueCategoryTodo",
	note = "CueCategoryNote",
	doc = "CueCategoryDoc",
	bin = "CueCategoryBin",
	trace = "CueCategoryTrace",
	review = "CueCategoryReview",
	tmp = "CueCategoryTmp",
}

M.kind_highlights = {
	research = "CueKindResearch",
	design = "CueKindDesign",
	build = "CueKindBuild",
	review = "CueKindReview",
	coord = "CueKindCoord",
}

-- Status values hidden from the task BOARD picker (<C-t>). Operator
-- decisions 2026-08-22 and 2026-08-23: complete and closed cards are
-- archive noise (dedicated done picker: <space>ec) and "inbox" is an
-- idea-intake status with a dedicated picker (<space>ei). Applied ONLY
-- when opts.board is set -- other task pickers (<space>et, <C-f>
-- drill-in, all-scopes) still list every status.
M.HIDDEN_TASK_STATUSES = {
	complete = true,
	closed = true,
	inbox = true,
}

-- Nerd Font glyphs for the task picker priority column (single-width
-- carets, Jira-style). Operator decision 2026-08-22: flag ONLY critical
-- and high; normal is the norm and low is rare clutter, so they render
-- blank. Byte sequences are UTF-8 encodings of the codepoints:
--   critical  U+F102 angle-double-up (red)
--   high      U+F106 angle-up        (orange)
M.PRIORITY_GLYPH = {
	critical = "\xEF\x84\x82",
	high = "\xEF\x84\x86",
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

-- Nerd Font glyph for the context browser's pin marker (single-width).
--   U+F08D nf-fa-thumb_tack, UTF-8 EF 82 8D
--
-- A Nerd Font private-use codepoint, NOT an emoji: emoji are double-width
-- (and width-unstable across terminals), which would shear the aligned
-- columns the browser renders, and they inherit their own colour instead of
-- the row's highlight group.
M.PIN_GLYPH = "\xEF\x82\x8D"

M.priority_highlights = {
	critical = "CuePriorityCritical",
	high = "CuePriorityHigh",
	normal = "CuePriorityNormal",
	low = "CuePriorityLow",
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
