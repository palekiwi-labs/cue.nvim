local M = {}

local COLORS = {
  grey   = "#4c566a",
  dark   = "#161B22",
  darker = "#101010",
  blue   = "#58a6ff",
  cyan   = "#39c5cf",
  orange = "#d29922",
  yellow = "#e5c07b",
  pink   = "#ff7b72",
  purple = "#bc8cff",
  red    = "#f85149",
  green  = "#98C379",
}

function M.setup()
  vim.api.nvim_set_hl(0, "CueStatusDone", { fg = COLORS.grey, strikethrough = true })

  -- Width-1 task-picker markers. Bold so the symbol reads at a glance.
  vim.api.nvim_set_hl(0, "CueMarkerActive", { fg = COLORS.cyan, bold = true })
  vim.api.nvim_set_hl(0, "CueMarkerInProgress", { fg = COLORS.yellow, bold = true })

  vim.api.nvim_set_hl(0, "CueCategorySpec", { fg = COLORS.pink, bold = false })
  vim.api.nvim_set_hl(0, "CueCategoryPlan", { fg = COLORS.purple, bold = false })
  vim.api.nvim_set_hl(0, "CueCategoryTask", { fg = COLORS.cyan, bold = false })
  vim.api.nvim_set_hl(0, "CueCategoryTodo", { fg = COLORS.blue, bold = false })
  vim.api.nvim_set_hl(0, "CueCategoryNote", { fg = COLORS.green, bold = false })
  vim.api.nvim_set_hl(0, "CueCategoryDoc", { fg = COLORS.orange, bold = false })
  vim.api.nvim_set_hl(0, "CueCategoryTrace", { fg = COLORS.yellow, bold = false })
  vim.api.nvim_set_hl(0, "CueCategoryBin", { fg = COLORS.red, bold = false })
  vim.api.nvim_set_hl(0, "CueCategoryTmp", { fg = COLORS.grey, bold = false })
  vim.api.nvim_set_hl(0, "CueCategoryRef", { fg = COLORS.grey, bold = false })
end

return M
