--- Cue log: form UI, parsing, and submission
local M = {}

local LOG_TEMPLATE = {
  "## Title",
  "Write your title here",
  "",
  "## Body",
  "Optional multi-line body.",
  "",
  "## Found",
  "- ",
  "",
  "## Decided",
  "- ",
  "",
  "## Open",
  "- ",
}

-- ─── Private helpers ──────────────────────────────────────────────────────────

--- Parse the structured scratch buffer into a log entry table
---@param lines string[]
---@return table  { title, body, found, decided, open }
local function parse_log_buffer(lines)
  local entry = { title = nil, body = {}, found = {}, decided = {}, open = {} }
  local valid_sections = { title = true, body = true, found = true, decided = true, open = true }
  local section = "title"

  for _, line in ipairs(lines) do
    local header = line:match("^##%s+(%w+)")
    if header and valid_sections[header:lower()] then
      section = header:lower()
    else
      if section == "title" then
        if line ~= "" and not entry.title then
          entry.title = vim.trim(line)
        end
      elseif section == "body" then
        table.insert(entry.body, line)
      else
        local item = line:match("^%s*[%-%*]%s+(.+)") or (line ~= "" and vim.trim(line) or nil)
        if item and item ~= "" then
          table.insert(entry[section], item)
        end
      end
    end
  end

  entry.body = #entry.body > 0 and vim.trim(table.concat(entry.body, "\n")) or nil
  if entry.body == "" then entry.body = nil end

  return entry
end

-- ─── Public API ───────────────────────────────────────────────────────────────

--- Build and submit a `cue log add` entry via a temporary JSON file
---@param entry table  { title, body?, found?, decided?, open? }
---@return boolean
function M.log_add(entry)
  if not entry.title or entry.title == "" then
    vim.notify("Cue Log Error: Title is required", vim.log.levels.ERROR)
    return false
  end

  local tmpfile = vim.fn.tempname() .. ".json"
  local data = {
    title   = entry.title,
    body    = entry.body or vim.NIL,
    found   = #(entry.found   or {}) > 0 and entry.found   or vim.NIL,
    decided = #(entry.decided or {}) > 0 and entry.decided or vim.NIL,
    open    = #(entry.open    or {}) > 0 and entry.open    or vim.NIL,
  }

  local ok, err = pcall(function()
    local json = vim.fn.json_encode(data)
    local f = assert(io.open(tmpfile, "w"))
    f:write(json)
    f:close()
  end)

  if not ok then
    vim.notify("Cue Log Error: Failed to write temp file: " .. tostring(err), vim.log.levels.ERROR)
    return false
  end

  local obj = vim.system({ "cue", "log", "add", "--file", tmpfile }, { text = true }):wait()
  vim.fn.delete(tmpfile)

  if obj.code ~= 0 then
    local msg = vim.trim((obj.stderr and obj.stderr ~= "") and obj.stderr or obj.stdout or "Unknown error")
    vim.notify("Cue Log Error: " .. msg, vim.log.levels.ERROR)
    return false
  end

  vim.notify("Cue Log: Entry added: " .. entry.title, vim.log.levels.INFO)
  return true
end

--- Open a floating form for composing a cue log entry
function M.log_form()
  local Snacks = require('snacks')

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype  = "markdown"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, LOG_TEMPLATE)
  vim.bo[buf].modified = false

  local win = Snacks.win({
    buf    = buf,
    width  = 0.6,
    height = 0.7,
    border = "rounded",
    title  = "  Cue Log Add  |  <C-s> Submit  |  q Cancel  ",
    title_pos = "center",
    wo = { wrap = true, linebreak = true, conceallevel = 2 },
  })

  local function submit()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local entry = parse_log_buffer(lines)
    if M.log_add(entry) then
      win:close()
    end
  end

  vim.keymap.set({ "n", "i" }, "<C-s>", submit,
    { buffer = buf, desc = "Submit cue log entry" })
  vim.keymap.set("n", "q", function() win:close() end,
    { buffer = buf, desc = "Cancel cue log entry" })

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer   = buf,
    callback = submit,
  })

  vim.api.nvim_win_set_cursor(win.win, { 2, 0 })
  vim.cmd("startinsert!")
end

return M
