---
priority: normal
title: List and cleanup shipped commands and feats
status: open
---

1. Make a list of all the features currently supported by the plugin
2. Decide which of these are worth keeping for the minimal version of the app
  in order to ship a coherent and logical API


## Context

Here is a snippet from my personal confgi which is how I use the plugin now.
I rely entirely on keybindings not user commands.

We need to ship with **some** user commands but let's make it as minimal as possible.

```lua
  { "<C-t>",           cue_utils.pick_artifacts,                                                                    desc = "[Cue] Current artifacts" },
  { "<A-t>",           function() cue_utils.pick_artifacts({ branch = vim.g.git_base }) end,                        desc = "Base branch (" .. (vim.g.git_base or "???") .. ")" },
  { "<space>e",        group = "entries" },
  { "<space>et",       function() cue_utils.pick_artifacts({ type = "task", branch = vim.g.git_master }) end,       desc = "Tasks (master)" },
  { "<space>eo",       function() cue_utils.pick_artifacts({ type = "todo" }) end,                                  desc = "Todos (current)" },
  { "<space>eT",       function() cue_utils.pick_artifacts({ type = "todo", branch = vim.g.git_master }) end,       desc = "Todos (" .. (vim.g.git_master or "master") .. ")" },
  { "<space>es",       function() cue_utils.pick_artifacts({ type = "spec" }) end,                                  desc = "Specs (current)" },
  { "<space>eS",       function() cue_utils.pick_artifacts({ type = "spec", branch = vim.g.git_master }) end,       desc = "Specs (" .. (vim.g.git_master or "master") .. ")" },
  { "<space>ed",       function() cue_utils.pick_artifacts({ type = "doc" }) end,                                   desc = "Docs (current)" },
  { "<space>eD",       function() cue_utils.pick_artifacts({ type = "doc", branch = vim.g.git_master }) end,        desc = "Docs (" .. (vim.g.git_master or "master") .. ")" },
  { "<space>ep",       function() cue_utils.pick_artifacts({ type = "plan" }) end,                                  desc = "Plans (current)" },
  { "<space>eP",       function() cue_utils.pick_artifacts({ type = "plan", branch = vim.g.git_master }) end,       desc = "Plans (" .. (vim.g.git_master or "master") .. ")" },
  { "<space>ea",       group = "all branches" },
  { "<space>eat",      function() cue_utils.pick_artifacts({ type = "task", all = true }) end,                      desc = "Tasks" },
  { "<space>eao",      function() cue_utils.pick_artifacts({ type = "todo", all = true }) end,                      desc = "Todos" },
  { "<space>eas",      function() cue_utils.pick_artifacts({ type = "spec", all = true }) end,                      desc = "Specs" },
  { "<space>ead",      function() cue_utils.pick_artifacts({ type = "doc", all = true }) end,                       desc = "Docs" },
  { "<space>eap",      function() cue_utils.pick_artifacts({ type = "plan", all = true }) end,                      desc = "Plans" },
  { "<space>eaa",      function() cue_utils.pick_artifacts({ all = true }) end,                                     desc = "All artifacts" },
  { "<space>eB",       cue_utils.pick_branch_artifacts,                                                             desc = "Select branch" },
  { "<space>eu",       cue_utils.ui_pick,                                                                           desc = "UI (Pick)" },
  { "<space>n",        group = "new" },
  { "<space>nt",       function() cue_utils.add_with_title("task") end,                                             desc = "Task (master)" },
  { "<space>no",       function() cue_utils.add_with_title("todo") end,                                             desc = "Todo (current)" },
  { "<space>nT",       function() cue_utils.add_with_title("todo", vim.g.git_master) end,                           desc = "Todo (" .. (vim.g.git_master or "master") .. ")" },
  { "<space>np",       function() cue_utils.add_with_title("plan") end,                                             desc = "Plan (current)" },
  { "<space>nP",       function() cue_utils.add_with_title("plan", vim.g.git_master) end,                           desc = "Plan (" .. (vim.g.git_master or "master") .. ")" },
  { "<space>ns",       function() cue_utils.add_spec() end,                                                         desc = "Spec (current)" },
  { "<space>nS",       function() cue_utils.add_spec(vim.g.git_master) end,                                         desc = "Spec (" .. (vim.g.git_master or "master") .. ")" },
  { "<space>nd",       function() cue_utils.add_with_title("doc") end,                                              desc = "Doc (current)" },
  { "<space>nD",       function() cue_utils.add_with_title("doc", vim.g.git_master) end,                            desc = "Doc (" .. (vim.g.git_master or "master") .. ")" },

```
