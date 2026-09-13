--- Core helpers and artifact management functions
local M = {}

local config = require('cue.config')

-- ─── Context artifact browsing ────────────────────────────────────────────────
-- Pure helpers behind picker.pick_context_artifacts (cue-nvim-workflow spec
-- §8). Kept free of vim.* calls (beyond the NIL sentinel comparison) so they
-- are unit-testable without Neovim; see tests/test_context_artifacts.lua.

--- Normalise an explicitly supplied context slug.
---
--- Browsing a context is an EXPLICIT operation: there is deliberately no
--- fallback to the active context (`cue status` / `.cue/HEAD`). Consulting
--- another context must not depend on, or silently follow, the active one.
--- A nil/blank/non-string argument is a caller error, reported as nil.
---@param context string|nil
---@return string|nil  trimmed slug, or nil when no explicit context was given
function M.normalize_context(context)
  if type(context) ~= "string" then
    return nil
  end
  local trimmed = context:gsub("^%s+", ""):gsub("%s+$", "")
  if trimmed == "" then
    return nil
  end
  return trimmed
end

--- Build the `cue status --json` argv.
--- Optional repo dir (-C) and store root (--store) are supported.
---@param opts table|nil  supports: dir (string, -C), store (string, --store)
---@return table  argv list
function M.active_context_argv(opts)
  opts = opts or {}
  local cmd = { 'cue', 'status' }
  if type(opts.dir) == "string" and opts.dir ~= "" then
    table.insert(cmd, '-C')
    table.insert(cmd, opts.dir)
  end
  if type(opts.store) == "string" and opts.store ~= "" then
    table.insert(cmd, '--store')
    table.insert(cmd, opts.store)
  end
  table.insert(cmd, '--json')
  return cmd
end

--- Pure decision helper for resolving active context from a status table.
--- Kept free of side effects so it can be unit-tested without Neovim.
---@param status table|nil  decoded `cue status --json` output
---@return table  { action = "pick", context = string } or { action = "notify", message = string }
function M.active_context_decision(status)
  if not status or type(status) ~= "table" then
    return { action = "notify", message = "No active cue context" }
  end
  local ctx = status.context
  if ctx == nil or ctx == vim.NIL or type(ctx) ~= "string" or ctx:match("^%s*$") then
    return { action = "notify", message = "No active cue context" }
  end
  local trimmed = ctx:gsub("^%s+", ""):gsub("%s+$", "")
  return { action = "pick", context = trimmed }
end

--- A decoded JSON field as a trimmed, nonempty string, or nil.
--- Rejects vim.NIL and non-strings, which vim.json.decode yields for JSON
--- nulls and unquoted numerics respectively.
---@param value any
---@return string|nil
local function text_field(value)
  if value == nil or value == vim.NIL or type(value) ~= "string" then
    return nil
  end
  local trimmed = value:gsub("^%s+", ""):gsub("%s+$", "")
  if trimmed == "" then
    return nil
  end
  return trimmed
end

--- Absolute path to the active context's `context.md`, derived from a decoded
--- `cue status --json` table.
---
--- `cue context path` and `cue context init` were removed from the CLI, so
--- there is no query that answers this. There does not need to be one: in the
--- central-store model an absolute path IS the store root joined to the
--- canonical address, and `cue status --json` carries both `store` and
--- `address`. Deriving it here costs no extra subprocess, because
--- get_active_context already returns the whole status table.
---
--- `context.md` is the only piece of store layout the plugin knows. Everything
--- else it opens comes from a `path` field the CLI handed it.
---
--- Returns nil rather than a partial path when either field is unusable: a
--- path missing its store is relative and a path missing its address points at
--- the store root, and both would open as a new empty buffer instead of
--- surfacing the error.
---@param status table|nil  decoded `cue status --json` output
---@return string|nil
function M.active_context_path(status)
  if not status or status == vim.NIL or type(status) ~= "table" then
    return nil
  end

  local store = text_field(status.store)
  local address = text_field(status.address)
  if not store or not address then
    return nil
  end

  return (store:gsub("/+$", "")) .. "/" .. address .. "/context.md"
end

--- Build the `cue list` argv for ONE explicit context.
---
--- Emits the current CLI surface only: `--context` for the scope, `-C` for an
--- alternate repository directory and `--store` for an alternate store root
--- (both optional), plus one `--type` flag per approved group. Requesting the
--- types explicitly keeps the deferred `bin`/`tmp` artifacts out of the
--- payload rather than filtering them after the fact.
---
--- Returns nil when no explicit context was supplied: without `--context`,
--- `cue list` resolves the ACTIVE context, which this picker must never do.
---@param context string|nil  context slug (required)
---@param opts table|nil  supports: dir (string, -C), store (string, --store)
---@return table|nil  argv list, or nil when the context is missing
function M.context_artifacts_argv(context, opts)
  local ctx = M.normalize_context(context)
  if not ctx then
    return nil
  end
  opts = opts or {}

  local cmd = { 'cue', 'list' }
  if type(opts.dir) == "string" and opts.dir ~= "" then
    table.insert(cmd, '-C')
    table.insert(cmd, opts.dir)
  end
  if type(opts.store) == "string" and opts.store ~= "" then
    table.insert(cmd, '--store')
    table.insert(cmd, opts.store)
  end
  table.insert(cmd, '--context')
  table.insert(cmd, ctx)
  table.insert(cmd, '--json')
  table.insert(cmd, '--frontmatter')
  for _, cue_type in ipairs(config.CONTEXT_ARTIFACT_TYPES) do
    table.insert(cmd, '--type')
    table.insert(cmd, cue_type)
  end
  return cmd
end

--- Displayed title for an artifact row: the frontmatter title, falling back
--- to the filename when there is none.
---
--- Only a nonblank STRING title is accepted: YAML emits an unquoted numeric
--- title as a number, which cannot be rendered as a display column.
---@param artifact table|nil  a `cue list --json --frontmatter` row
---@return string
function M.artifact_display_title(artifact)
  if not artifact or artifact == vim.NIL or type(artifact) ~= "table" then
    return ""
  end
  local fm = artifact.frontmatter
  if fm and fm ~= vim.NIL and type(fm) == "table" then
    local title = fm.title
    if type(title) == "string" and title:match("%S") then
      return title
    end
  end
  return artifact.name or ""
end

--- Comparator for the context artifact picker: group order first
--- (config.CONTEXT_ARTIFACT_TYPES), then the displayed title alphabetically
--- within the group. Title comparison is case-insensitive so "beta" sorts
--- between "Alpha" and "Gamma".
---
--- Ties fall through to the filename and then to the full path. The filename
--- alone is NOT unique -- artifacts nest, so `spec/alpha/index.md` and
--- `spec/beta/index.md` share a basename -- and table.sort is not stable, so
--- the path is needed as the final discriminator to keep the order
--- deterministic and independent of input order.
---@param a table
---@param b table
---@return boolean
function M.context_artifact_less(a, b)
  local a_rank = config.CONTEXT_ARTIFACT_TYPE_RANK[a.type] or 99
  local b_rank = config.CONTEXT_ARTIFACT_TYPE_RANK[b.type] or 99
  if a_rank ~= b_rank then
    return a_rank < b_rank
  end

  local a_title = M.artifact_display_title(a):lower()
  local b_title = M.artifact_display_title(b):lower()
  if a_title ~= b_title then
    return a_title < b_title
  end

  local a_name = a.name or ""
  local b_name = b.name or ""
  if a_name ~= b_name then
    return a_name < b_name
  end

  return (a.path or "") < (b.path or "")
end

--- Turn a `cue list` payload into the picker's row list: keep the approved
--- artifact types (dropping the deferred bin/tmp and any unknown type), then
--- order them with context_artifact_less.
---
--- Tasks are kept whatever their status: the spec requires them in this list,
--- so no status filtering happens here.
---@param artifacts table|nil  decoded `cue list --json --frontmatter` output
---@return table  ordered rows (never nil)
function M.context_artifacts_view(artifacts)
  local rows = {}
  if type(artifacts) ~= "table" then
    return rows
  end
  for _, artifact in ipairs(artifacts) do
    if type(artifact) == "table"
       and type(artifact.path) == "string"
       and config.CONTEXT_ARTIFACT_TYPE_RANK[artifact.type] then
      rows[#rows + 1] = artifact
    end
  end
  table.sort(rows, M.context_artifact_less)
  return rows
end

--- The context browser's row label: the context title when it is a nonempty
--- string, else the slug. Mirrors artifact_display_title, including its
--- refusal of non-string titles: YAML emits an unquoted numeric title as a
--- number, which cannot be rendered as a display column.
---@param ctx table|nil  a `cue context list --json` row
---@return string
function M.context_display_title(ctx)
  if not ctx or ctx == vim.NIL or type(ctx) ~= "table" then
    return ""
  end
  local title = ctx.title
  if type(title) == "string" and title:match("%S") then
    return title
  end
  return ctx.context or ""
end

--- Turn a decoded `cue context list --json` payload into the browser's rows
--- by dropping malformed entries. CLI order is preserved exactly.
---
--- Ordering is deliberately not done here. `cue context list --sort recency`
--- documents its rule as "newest log entry first; contexts with no log entry
--- last", which is the rule this module used to implement by hand against a
--- caller-supplied slug -> timestamp map. cue owns the recency axis, so it
--- owns the sort; a second implementation here would only be something to
--- keep in step. The payload now also carries `last_logged_at` per row, so
--- the map has no source left to come from and the parameter is gone.
---
--- A row is malformed when it has no slug or no path: the slug identifies it
--- to pin/unpin and activate, and the path is what the previewer and <CR>
--- open. A row missing either cannot be acted on.
---@param contexts table|nil  decoded `cue context list --json` output
---@return table  rows in CLI order (never nil)
function M.context_list_view(contexts)
  local rows = {}
  if type(contexts) ~= "table" then
    return rows
  end
  for _, ctx in ipairs(contexts) do
    if type(ctx) == "table"
       and type(ctx.context) == "string"
       and type(ctx.path) == "string" then
      rows[#rows + 1] = ctx
    end
  end
  return rows
end

--- Strip the file extension from an artifact name, yielding the task slug.
--- Pure-Lua equivalent of vim.fn.fnamemodify(name, ":r").
---@param name string|nil
---@return string|nil
function M.task_slug(name)
  if not name then return nil end
  return (name:gsub("%.[^.]+$", ""))
end

--- Pure helper to compute a sorted list of scope slugs from task-card filenames.
--- ALWAYS contains "master", deduped, and sorted.
---@param task_filenames table|nil list of task-card basenames (e.g. { "auth-login.md" })
---@return table sorted list of scope slugs
function M.scope_set(task_filenames)
  local slugs = { master = true }
  if task_filenames then
    for _, name in ipairs(task_filenames) do
      local slug = M.task_slug(name)
      if slug then
        slugs[slug] = true
      end
    end
  end

  local result = {}
  for slug, _ in pairs(slugs) do
    table.insert(result, slug)
  end
  table.sort(result)
  return result
end

--- Slugify text for use as a filename
---@param text string|nil
---@return string|nil
function M.slugify(text)
  if not text then return nil end
  return text:lower()
    :gsub("[%s_/]+", "-")
    :gsub("[^%w%-]+", "")
    :gsub("%-+", "-")
    :gsub("^%-+", "")
    :gsub("%-+$", "")
end

--- Convert a slug (or raw slug-ish text) into a human-readable title.
---
--- Extracts word tokens, capitalising each and dropping separators/punctuation.
--- Short all-caps tokens (2-4 uppercase letters, no digits) are preserved as
--- acronyms, so "WSS-migration" -> "WSS Migration" when the user typed the
--- acronym in capitals.
---
--- Multi-byte (UTF-8) bytes are kept inside a token so accented/CJK input is
--- not split into bogus words; byte-wise case folding is a no-op on UTF-8
--- continuation bytes, so titles are not corrupted.
---
--- Kept free of vim.* calls so it is unit-testable without Neovim.
---@param text string|nil
---@return string  title, or "" for nil/empty/no-word input
function M.slug_to_title(text)
  if not text or text == "" then return "" end
  local words = {}
  -- [\128-\255] keeps multi-byte sequences together (see comment above).
  for word in text:gmatch("[%w'\128-\255]+") do
    -- Skip tokens with no core content (a stray "'" or "'''").
    if word:match("[%w\128-\255]") then
      local is_acronym = (#word >= 2 and #word <= 4 and word:match("^[A-Z]+$") ~= nil)
      if is_acronym then
        table.insert(words, word)
      else
        -- Capitalise the first ASCII alphanumeric so "'tis" -> "'Tis".
        local lead, first, tail = word:match("^([^%w]*)(%w)(.*)$")
        if first then
          table.insert(words, lead .. first:upper() .. tail:lower())
        else
          -- No ASCII alnum (e.g. pure CJK): emit as-is.
          table.insert(words, word)
        end
      end
    end
  end
  return table.concat(words, " ")
end

--- Pure helper that computes the filename and add() opts for a slug-based
--- artifact of a markdown type (task/note). Encodes slug-flow membership
--- (config.SLUG_TYPES) and the frontmatter defaults (config.TYPE_DEFAULTS).
---
--- Returns nil for types outside config.SLUG_TYPES: the slug flow slugifies
--- the entered name and forces a .md extension, which destroys a real path.
--- Those types belong to the path flow (see path_artifact_plan /
--- add_with_path).
---
--- Kept free of vim.* calls so it is unit-testable without Neovim.
---@param type string        artifact type ("task", "note")
---@param raw_slug string    user-entered slug text (normalised via slugify)
---@param context string|nil resolved cue context slug (e.g. "auth-login")
---@param extra_fm table|nil extra frontmatter fields (e.g. { parent = "refine-cue-skills" })
---@return table|nil  { filename=..., opts={ category, context, frontmatter } },
---                   or nil when the type is not a slug type or the slug
---                   normalises to empty
function M.slug_artifact_plan(type, raw_slug, context, extra_fm)
  if not config.SLUG_TYPES[type] then
    return nil
  end
  local slug = M.slugify(raw_slug)
  if not slug or slug == "" then
    return nil
  end
  -- Derive a human-readable title from the RAW slug (pre-slugify) so
  -- acronyms typed in capitals survive (e.g. "WSS-migration" -> "WSS
  -- Migration"). Merge over TYPE_DEFAULTS without vim.tbl_extend to keep
  -- this helper vim-free (unit-testable under the vim={} stub).
  -- Shallow copy is sufficient: TYPE_DEFAULTS values are scalars only.
  local defaults = config.TYPE_DEFAULTS[type] or {}
  local frontmatter = {}
  for k, v in pairs(defaults) do frontmatter[k] = v end

  if extra_fm and _G.type(extra_fm) == "table" then
    for k, v in pairs(extra_fm) do
      if v ~= nil and v ~= "" and v ~= vim.NIL then
        frontmatter[k] = v
      end
    end
  end

  -- Only set a title that contains at least one letter. A digit-only slug
  -- (e.g. "2026") would yield title="2026", which `cue add` emits as a YAML
  -- number (coerce_scalar leaves it unquoted); the picker then assigns that
  -- number straight to display_name, which must be a string. A digit "title"
  -- is not useful anyway, so omit it.
  local title = M.slug_to_title(raw_slug)
  if title:match("%a") and not frontmatter.title then
    frontmatter.title = title
  end

  return {
    filename = slug .. ".md",
    opts = {
      category    = type,
      context     = context,
      frontmatter = frontmatter,
    },
  }
end

--- Pure helper that computes the filename and add() opts for a path-based
--- artifact (e.g. trace, spec). The path is used VERBATIM: no slugification
--- and no forced extension, so nested paths (spec/index.md, a nested note)
--- and non-markdown types survive intact.
---
--- Frontmatter defaults (config.TYPE_DEFAULTS) apply only to markdown (.md)
--- paths: `cue add` prepends YAML frontmatter unconditionally, which would
--- corrupt a non-markdown file.
---
--- Kept free of vim.* calls so it is unit-testable without Neovim.
---@param type string        artifact type (e.g. "trace", "spec")
---@param path string        user-entered file path, used verbatim
---@param context string|nil resolved cue context slug
---@return table|nil  { filename=..., opts={ category, context, frontmatter } },
---                   or nil when the path is empty/whitespace-only
function M.path_artifact_plan(type, path, context)
  if not path or path:match("%S") == nil then
    return nil
  end

  local frontmatter = {}
  if path:match("%.md$") then
    local defaults = config.TYPE_DEFAULTS[type] or {}
    for k, v in pairs(defaults) do frontmatter[k] = v end
  end

  return {
    filename = path,
    opts = {
      category    = type,
      context     = context,
      frontmatter = frontmatter,
    },
  }
end

--- Execute a command (as an arg list) and return its stdout.
--- Uses vim.system, the idiomatic API on nvim 0.10+. stderr is captured but
--- discarded; a non-zero exit code yields (nil, error).
---@param cmd table  command as a list of arguments (no shell involved)
---@return string|nil, string|nil
function M.execute_command(cmd)
  local obj = vim.system(cmd, { text = true }):wait()
  if obj.code ~= 0 then
    return nil, "Command failed"
  end
  return obj.stdout
end

--- Parse a JSON string using the native Lua JSON decoder (vim.json).
--- Preferred over the legacy `vim.fn.json_decode` wrapper on nvim 0.10+.
---@param json_str string
---@return any, string|nil
function M.parse_json(json_str)
  local ok, result = pcall(vim.json.decode, json_str)
  if not ok then
    return nil, "Failed to parse JSON"
  end
  return result
end

--- Get the current git branch name (with / replaced by -)
---@return string|nil
function M.get_current_branch()
  local obj = vim.system({ 'git', 'rev-parse', '--abbrev-ref', 'HEAD' }, { text = true }):wait()
  if obj.code ~= 0 then
    return nil
  end
  local branch = (obj.stdout or ""):gsub("%s+", "")
  if branch == "" then return nil end
  return branch:gsub("/", "-")
end

--- Query cue status for the active context slug.
---
--- Emits `cue status --json` with optional `-C dir` and `--store store`.
--- In the central store model, cue status returns:
---   `{ context = "<slug>", ... }` when a context is active, or
---   `{ context = nil, ... }` when no context is active (unset).
---
--- Unlike the legacy model, there is no default or fallback context ("master"
--- is not a fallback). If context is unset, returns nil.
---
---@param opts table|nil  supports: dir (string, -C), store (string, --store)
---@return string|nil context_slug, table|nil full_status, string|nil error_message
function M.get_active_context(opts)
  local cmd = M.active_context_argv(opts)
  local output, err = M.execute_command(cmd)
  if not output or output == "" then
    return nil, nil, err or "no output from cue status"
  end

  local ok, status = pcall(vim.json.decode, output)
  if not ok or type(status) ~= "table" then
    return nil, nil, "invalid JSON from cue status"
  end

  local decision = M.active_context_decision(status)
  if decision.action == "notify" then
    return nil, status, nil
  end

  return decision.context, status, nil
end

--- Build the `cue context switch <slug>` argv.
---
--- The legacy top-level `cue switch` is gone: in the central-store model the
--- branch association is written by `cue context switch`, which requires an
--- explicit slug. There is no "master" fallback to substitute for a missing
--- one, so a blank/non-string slug returns nil rather than an argv.
---
--- Kept free of vim.* calls so it is unit-testable without Neovim.
---@param slug string|nil  context slug (required)
---@param opts table|nil   supports: dir (string, -C), store (string, --store)
---@return table|nil  argv list, or nil when the slug is missing
function M.switch_context_argv(slug, opts)
  local ctx = M.normalize_context(slug)
  if not ctx then
    return nil
  end
  opts = opts or {}

  local cmd = { 'cue', 'context', 'switch' }
  if type(opts.dir) == "string" and opts.dir ~= "" then
    table.insert(cmd, '-C')
    table.insert(cmd, opts.dir)
  end
  if type(opts.store) == "string" and opts.store ~= "" then
    table.insert(cmd, '--store')
    table.insert(cmd, opts.store)
  end
  table.insert(cmd, ctx)
  return cmd
end

--- Associate a cue context with the current git branch.
--- Writes `branch.<branch>.cue-context` via `cue context switch`.
---@param slug string  context slug
---@param opts table|nil  supports: dir (string, -C), store (string, --store)
function M.switch_context(slug, opts)
  local cmd = M.switch_context_argv(slug, opts)
  if not cmd then
    vim.notify("cue: a context slug is required to switch", vim.log.levels.ERROR)
    return
  end

  local obj = vim.system(cmd, { text = true }):wait()
  if obj.code == 0 then
    vim.notify("cue: switched to " .. cmd[#cmd], vim.log.levels.INFO)
  else
    local msg = vim.trim((obj.stderr or "") ~= "" and obj.stderr or (obj.stdout or "unknown"))
    vim.notify("cue context switch failed: " .. msg, vim.log.levels.ERROR)
  end
end

-- ─── Scope confirmation ───────────────────────────────────────────────────────

--- Prompt the user to confirm (or change) the cue scope for a new artifact.
---
--- Pure helper that builds the argv table for `cue context list`.
---
--- `scope`, `sort` and `limit` are validated against the CLI's own
--- vocabulary and silently omitted when they do not match. cue defines
--- exactly one sort (`recency`) and two breadths (`repo`, `store`), and
--- passing anything else makes cue exit non-zero, which surfaces to the
--- operator as a picker that opens empty rather than as an error.
---
--- Called with no opts this still yields the bare `cue context list`, whose
--- plain slug-per-line output list_contexts and confirm_scope parse.
---@param opts table|nil  supports: json (bool), scope ("repo"|"store"),
---  sort ("recency"), limit (positive integer), dir (string, -C),
---  store (string, --store)
---@return string[]
function M.list_contexts_argv(opts)
  local cmd = { 'cue', 'context', 'list' }
  if opts and opts.json then
    table.insert(cmd, '--json')
  end
  if opts and (opts.scope == "repo" or opts.scope == "store") then
    table.insert(cmd, '--scope')
    table.insert(cmd, opts.scope)
  end
  if opts and opts.sort == "recency" then
    table.insert(cmd, '--sort')
    table.insert(cmd, opts.sort)
  end
  if opts and type(opts.limit) == "number"
     and opts.limit > 0 and opts.limit % 1 == 0 then
    table.insert(cmd, '--limit')
    table.insert(cmd, tostring(opts.limit))
  end
  if opts and opts.dir then
    table.insert(cmd, '-C')
    table.insert(cmd, opts.dir)
  end
  if opts and opts.store then
    table.insert(cmd, '--store')
    table.insert(cmd, opts.store)
  end
  return cmd
end

--- Return a sorted list of context slugs in the repository scope via `cue context list`.
---@param opts table|nil  supports: dir (`cue -C`), store (`cue --store`)
---@return string[]|nil
function M.list_contexts(opts)
  local cmd = M.list_contexts_argv(opts)
  local output, _ = M.execute_command(cmd)
  if not output or output == "" then
    return nil
  end
  local contexts = {}
  for line in output:gmatch("[^\r\n]+") do
    local slug = vim.trim(line)
    if slug ~= "" then
      table.insert(contexts, slug)
    end
  end
  table.sort(contexts)
  return contexts
end

--- Confirm or prompt for target context for a new artifact.
--- Short-circuits without a dialog when context ~= nil (honours explicit binding choice).
--- Otherwise resolves the active context:
---   • When active context exists: offers "current: <active-slug>" or "select context..."
---   • When no active context exists: directly opens context selection
---
---@param type string         artifact type (e.g. "task", "note", "spec")
---@param context string|nil  pre-set context override, or nil to prompt
---@param callback function   called with the resolved context slug (string)
function M.confirm_scope(type, context, callback)
  if context ~= nil then
    callback(context)
    return
  end

  local Snacks = require('snacks')
  local active = M.get_active_context()

  local function select_from_all_contexts()
    local contexts = M.list_contexts()
    if not contexts or #contexts == 0 then
      vim.notify("No contexts found. Create a context first with 'cue context create'.", vim.log.levels.ERROR)
      return
    end
    Snacks.picker.select(contexts, { prompt = "Select context (" .. type .. "):" }, function(slug)
      if slug then callback(slug) end
    end)
  end

  if not active then
    select_from_all_contexts()
    return
  end

  local items = {
    { label = "current: " .. active, value = active },
    { label = "select context...",   value = "__pick__" },
  }

  Snacks.picker.select(items, {
    prompt = "Context for new " .. type .. ":",
    format_item = function(item) return item.label end,
  }, function(choice)
    if not choice then return end
    if choice.value ~= "__pick__" then
      callback(choice.value)
      return
    end
    select_from_all_contexts()
  end)
end

-- ─── Public API ───────────────────────────────────────────────────────────────

--- Open the active context's `context.md` in the editor.
---
--- One `cue status --json` call: it reports whether a context is active AND
--- carries the `store` and `address` the path is derived from.
---
--- The legacy implementation asked `cue context path` and, on a miss, ran
--- `cue context init` to conjure a context before retrying. Neither
--- subcommand exists, and the auto-init behaviour is not reinstated: cue has
--- no default or fallback context, and creating one as a side effect of a
--- navigation binding is exactly the implicit-context habit the central-store
--- model removes. With no active context this reports and stops.
function M.open_context()
  local ctx, status, err = M.get_active_context()
  if not ctx then
    vim.notify("cue: " .. (err or "no active context"), vim.log.levels.ERROR)
    return
  end

  local path = M.active_context_path(status)
  if not path then
    vim.notify("cue: status reported no store/address for " .. ctx, vim.log.levels.ERROR)
    return
  end

  if vim.fn.filereadable(path) == 0 then
    vim.notify("cue: context file does not exist: " .. path, vim.log.levels.ERROR)
    return
  end

  vim.cmd.edit(path)
end

--- Scan .cue/master/task/ for task cards and return a sorted list of slugs.
--- Always includes "master". Returns nil if .cue/ is absent.
---@return table|nil sorted list of scope slugs, or nil if no .cue/ found
function M.list_scopes()
  local cue_dir = ".cue"
  if vim.fn.isdirectory(cue_dir) == 0 then
    return nil
  end

  local task_dir = ".cue/master/task"
  local names = {}
  if vim.fn.isdirectory(task_dir) ~= 0 then
    for name, kind in vim.fs.dir(task_dir) do
      if kind == "file" and name:match("%.md$") then
        table.insert(names, name)
      end
    end
  end

  return M.scope_set(names)
end

--- Add a new artifact file via `cue add` and open it for editing
---@param filename string
---@param opts table|nil
---@return string|nil, string|nil
function M.add(filename, opts)
  opts = opts or {}

  if not filename or filename == "" then
    vim.notify("Error: filename is required", vim.log.levels.ERROR)
    return nil
  end

  local cmd = { 'cue', 'add', filename }

  if opts.category then
    table.insert(cmd, '--type')
    table.insert(cmd, opts.category)
  end

  local context = opts.context or opts.task
  if context then
    table.insert(cmd, '--context')
    table.insert(cmd, context)
  end

  if opts.dir then
    table.insert(cmd, '-C')
    table.insert(cmd, opts.dir)
  end

  if opts.store then
    table.insert(cmd, '--store')
    table.insert(cmd, opts.store)
  end

  if opts.frontmatter then
    for k, v in pairs(opts.frontmatter) do
      if type(v) == "table" then
        -- Array value: emit one --frontmatter flag per element. A repeated
        -- key becomes a YAML list in the output (see `cue add`). An empty
        -- table yields no flags (no frontmatter value).
        for _, el in ipairs(v) do
          table.insert(cmd, '--frontmatter')
          table.insert(cmd, string.format("%s=%s", k, el))
        end
      else
        table.insert(cmd, '--frontmatter')
        table.insert(cmd, string.format("%s=%s", k, v))
      end
    end
  end

  if opts.force then
    table.insert(cmd, '--force')
  end

  local obj = vim.system(cmd, { text = true }):wait()

  if obj.code ~= 0 then
    local error_msg = (obj.stderr and obj.stderr ~= "") and obj.stderr or obj.stdout
    error_msg = vim.trim(error_msg or "Unknown error")
    vim.notify("Cue Error: " .. error_msg, vim.log.levels.ERROR)
    return nil, error_msg
  end

  local filepath = vim.trim(obj.stdout or "")
  if filepath == "" then
    vim.notify("Error: failed to get file path from cue add output", vim.log.levels.ERROR)
    return nil
  end

  vim.notify("Successfully added: " .. filename, vim.log.levels.INFO)
  vim.cmd.edit(filepath)
  vim.cmd("normal! G")
  vim.cmd("startinsert!")

  return filepath
end

--- Prompt for parent task selection from available scopes
---@param callback function called with selected parent slug or nil
function M.prompt_parent(callback)
  local Snacks = require('snacks')
  local scopes = M.list_scopes() or { "master" }
  local active = M.get_active_context()

  local items = {
    { label = "(None)", value = nil, desc = "No parent link" },
  }

  if active and active ~= "master" then
    table.insert(items, { label = "active: " .. active, value = active, desc = "Active task context" })
  end

  for _, slug in ipairs(scopes) do
    if slug ~= "master" and slug ~= active then
      table.insert(items, { label = slug, value = slug, desc = "Task card" })
    end
  end

  Snacks.picker.select(items, {
    prompt = "Select Parent Task:",
    format_item = function(item)
      if item.desc then
        return string.format("%-30s  %s", item.label, item.desc)
      end
      return item.label
    end,
  }, function(choice)
    if choice then
      callback(choice.value)
    else
      callback(nil)
    end
  end)
end

--- Prompt for a slug, confirm scope, then add a markdown artifact of the
--- given type (task/note).
---
--- When context is non-nil the scope dialog is skipped (caller already pinned
--- context).
--- Types outside config.SLUG_TYPES are rejected up front: their filenames are
--- caller-chosen paths, so they belong to add_with_path instead.
---@param type string  artifact type ("task", "note")
---@param context string|nil  override context (nil = prompt via confirm_scope)
---@param extra_fm table|nil  extra frontmatter fields (e.g. { parent = "refine-cue-skills" })
function M.add_with_slug(type, context, extra_fm)
  if not config.SLUG_TYPES[type] then
    vim.notify(
      "Error: '" .. type .. "' is not a slug-based markdown type; use add_with_path",
      vim.log.levels.ERROR
    )
    return
  end
  local Snacks = require('snacks')
  Snacks.input({
    prompt = "Slug (" .. type .. "):",
    win = { row = 0.3 },
  }, function(raw_slug)
    if not raw_slug or raw_slug == "" then return end
    -- Bail before the scope dialog if the slug normalises to nothing.
    local slug = M.slugify(raw_slug)
    if not slug or slug == "" then
      vim.notify("Error: slug is empty after normalisation", vim.log.levels.ERROR)
      return
    end
    M.confirm_scope(type, context, function(target_context)
      local plan = M.slug_artifact_plan(type, raw_slug, target_context, extra_fm)
      M.add(plan.filename, plan.opts)
    end)
  end)
end

--- Prompt for a task slug, then create the task card.
--- The slug is used as the filename stem (e.g. "my-feature" → "my-feature.md").
---@param context string|nil  override context (nil = prompt via confirm_scope)
function M.add_task(context)
  M.add_with_slug("task", context)
end

--- Prompt for a title, then confirm scope, then add an artifact of the given type.
--- When context is non-nil the scope dialog is skipped (caller already pinned context).
---@param type string  artifact type (e.g. "task", "plan", "note")
---@param context string|nil  override context (nil = prompt via confirm_scope)
function M.add_with_title(type, context)
  local Snacks = require('snacks')
  Snacks.input({
    prompt = "Title (" .. type .. "):",
    win = { row = 0.3 },
  }, function(title)
    if not title or title == "" then return end
    M.confirm_scope(type, context, function(target_context)
      local filename = M.slugify(title) .. ".md"
      local defaults = config.TYPE_DEFAULTS[type] or {}
      -- Title wins over TYPE_DEFAULTS (matches slug_artifact_plan ordering).
      local frontmatter = vim.tbl_extend("force", defaults, { title = title })
      M.add(filename, {
        category    = type,
        context     = target_context,
        frontmatter = frontmatter,
      })
    end)
  end)
end

--- Prompt for a file path, then confirm scope, then add an artifact of the
--- given type. The path is used verbatim, so nested paths and non-markdown
--- extensions survive intact.
--- When context is non-nil the scope dialog is skipped (caller already pinned context).
---@param type string  artifact type (e.g. "trace", "spec")
---@param context string|nil  override context (nil = prompt via confirm_scope)
function M.add_with_path(type, context)
  local Snacks = require('snacks')
  Snacks.input({
    prompt = "Path (" .. type .. "):",
    completion = "file",
    win = { row = 0.3 },
  }, function(path)
    if not path or path == "" then return end
    M.confirm_scope(type, context, function(target_context)
      local plan = M.path_artifact_plan(type, path, target_context)
      if not plan then
        vim.notify("Error: path is empty", vim.log.levels.ERROR)
        return
      end
      M.add(plan.filename, plan.opts)
    end)
  end)
end

--- Prompt for a spec path, then confirm scope, then add a spec artifact.
--- When context is non-nil the scope dialog is skipped (caller already pinned context).
---@param context string|nil  override context (nil = prompt via confirm_scope)
function M.add_spec(context)
  local Snacks = require('snacks')
  Snacks.input({
    prompt = "Spec path:",
    completion = "file",
    win = { row = 0.3 },
  }, function(path)
    if not path or path == "" then return end
    M.confirm_scope("spec", context, function(target_context)
      M.add(path, { category = "spec", context = target_context })
    end)
  end)
end

return M
