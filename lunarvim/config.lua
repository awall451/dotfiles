-- Read the docs: https://www.lunarvim.org/docs/configuration
-- Example configs: https://github.com/LunarVim/starter.lvim
-- Video Tutorials: https://www.youtube.com/watch?v=sFA9kX-Ud_c&list=PLhoH5vyxr6QqGu0i7tt_XoVK9v-KvZ3m6
-- Forum: https://www.reddit.com/r/lunarvim/
-- Discord: https://discord.com/invite/Xb9B4Ny
-- ~/.config/lvim/config.lua

-- Read the docs: https://www.lunarvim.org/docs/configuration
-- ~/.config/lvim/config.lua

-- Appearance
lvim.colorscheme = "tokyonight"

lvim.plugins = {
  -- Pretty text/code folding w/ mouse click
  {
    "kevinhwang91/nvim-ufo",
    dependencies = { "kevinhwang91/promise-async" },
    config = function()
      require("ufo").setup({
        provider_selector = function()
          return { "treesitter", "indent" }
        end
      })
    end,
  },

  -- Plugin for JSON editing
  {
    "Wansmer/treesj",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    config = function()
      require("treesj").setup({
        use_default_keymaps = false,
        max_join_length = 500,
      })
    end,
  },

  -- Show treesitter context
  {
    "nvim-treesitter/nvim-treesitter-context",
    config = function()
      require("treesitter-context").setup({
        enable = true,
        max_lines = 10,
        mode = "cursor",
        separator = "━",
        multiline_threshold = 1,
      })
    end,
  },

  {
    "esmuellert/codediff.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
    },
  },

  -- PICO-8 syntax for .p8 files
  {
    "bakudankun/PICO-8.vim",
    ft = { "p8" },
  },

  -- Helm templates + YAML highlighting
  {
    "towolf/vim-helm",
    ft = { "helm", "yaml" },
  },

  -- Markdown TOC
  -- Commands:
  --   :Mtoc        (insert/update TOC)
  --   :MtocUpdate  (update existing TOC)
  --   :MtocInsert  (insert at cursor)
  {
    "hedyhli/markdown-toc.nvim",
    ft = { "markdown" },
    cmd = { "Mtoc", "MtocUpdate", "MtocInsert" },
    config = function()
      require("mtoc").setup({})
    end,
  },

  -- Markdown preview in browser
  {
    "iamcco/markdown-preview.nvim",
    ft = { "markdown" },
    build = "cd app && npm install",
    cmd = { "MarkdownPreview", "MarkdownPreviewStop", "MarkdownPreviewToggle" },
  },
  {
    "b0o/schemastore.nvim",
  },
  {
    "mfussenegger/nvim-lint",
  },

  -- Claude Code
  {
    "coder/claudecode.nvim",
    dependencies = { "folke/snacks.nvim" },
    opts = {
      terminal_cmd = "/home/dillon/.local/bin/claude", -- Point to local installation
    },
    config = true,
    keys = {
      { "<leader>a", nil, desc = "AI/Claude Code" },
      { "<leader>ac", "<cmd>ClaudeCode<cr>", desc = "Toggle Claude" },
      { "<leader>af", "<cmd>ClaudeCodeFocus<cr>", desc = "Focus Claude" },
      { "<leader>ar", "<cmd>ClaudeCode --resume<cr>", desc = "Resume Claude" },
      { "<leader>aC", "<cmd>ClaudeCode --continue<cr>", desc = "Continue Claude" },
      { "<leader>am", "<cmd>ClaudeCodeSelectModel<cr>", desc = "Select Claude model" },
      { "<leader>ab", "<cmd>ClaudeCodeAdd %<cr>", desc = "Add current buffer" },
      { "<leader>as", "<cmd>ClaudeCodeSend<cr>", mode = "v", desc = "Send to Claude" },
      {
        "<leader>as",
        "<cmd>ClaudeCodeTreeAdd<cr>",
        desc = "Add file",
        ft = { "NvimTree", "neo-tree", "oil", "minifiles", "netrw" },
      },
      -- Diff management
      { "<leader>aa", "<cmd>ClaudeCodeDiffAccept<cr>", desc = "Accept diff" },
      { "<leader>ad", "<cmd>ClaudeCodeDiffDeny<cr>", desc = "Deny diff" },
    },
  },

  -- File marks: pin a handful of hot files, jump between them with <leader>h1..4.
  {
    "ThePrimeagen/harpoon",
    branch = "harpoon2",
    dependencies = { "nvim-lua/plenary.nvim" },
    config = function()
      local harpoon = require("harpoon")
      harpoon:setup({})
      vim.keymap.set("n", "<leader>ha", function() harpoon:list():add() end, { desc = "Harpoon add file" })
      vim.keymap.set("n", "<leader>hh", function() harpoon.ui:toggle_quick_menu(harpoon:list()) end, { desc = "Harpoon menu" })
      vim.keymap.set("n", "<leader>h1", function() harpoon:list():select(1) end, { desc = "Harpoon file 1" })
      vim.keymap.set("n", "<leader>h2", function() harpoon:list():select(2) end, { desc = "Harpoon file 2" })
      vim.keymap.set("n", "<leader>h3", function() harpoon:list():select(3) end, { desc = "Harpoon file 3" })
      vim.keymap.set("n", "<leader>h4", function() harpoon:list():select(4) end, { desc = "Harpoon file 4" })
    end,
  },

  -- Edit directories as buffers. Rename/delete via vim motions, :w to commit.
  {
    "stevearc/oil.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      require("oil").setup({
        view_options = { show_hidden = true },
      })
      vim.keymap.set("n", "<leader>o", "<cmd>Oil<cr>", { desc = "Oil (edit dir)" })
      vim.keymap.set("n", "-", "<cmd>Oil<cr>", { desc = "Oil parent dir" })
    end,
  },

  -- Diagnostic / quickfix / references panel.
  {
    "folke/trouble.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    cmd = "Trouble",
    opts = {},
    keys = {
      { "<leader>xx", "<cmd>Trouble diagnostics toggle<cr>",                        desc = "Trouble diagnostics" },
      { "<leader>xd", "<cmd>Trouble diagnostics toggle filter.buf=0<cr>",           desc = "Buffer diagnostics" },
      { "<leader>xs", "<cmd>Trouble symbols toggle focus=false<cr>",                desc = "Symbols" },
      { "<leader>xl", "<cmd>Trouble lsp toggle focus=false win.position=right<cr>", desc = "LSP refs/defs" },
      { "<leader>xq", "<cmd>Trouble qflist toggle<cr>",                             desc = "Quickfix" },
      { "<leader>xL", "<cmd>Trouble loclist toggle<cr>",                            desc = "Location list" },
    },
  },

  -- Unified pane navigation across nvim windows and wezterm panes.
  -- Companion logic lives in wezterm/wezterm.lua (process-aware key handler).
  {
    "mrjones2014/smart-splits.nvim",
    lazy = false,
    config = function()
      require("smart-splits").setup({
        at_edge = "stop",
        cursor_follows_swapped_bufs = true,
      })
    end,
  },

  -- A collection of small QoL plugins for Neovim (Used for claude).
  {
    "folke/snacks.nvim",
    priority = 1000,
    lazy = false,
    ---@type snacks.Config
    opts = {
      -- your configuration comes here
      -- or leave it empty to use the default settings
      -- refer to the configuration section below
      bigfile = { enabled = true },
      dashboard = { enabled = true },
      explorer = { enabled = true },
      indent = { enabled = true },
      input = { enabled = true },
      picker = { enabled = true },
      notifier = { enabled = true },
      quickfile = { enabled = true },
      scope = { enabled = true },
      scroll = { enabled = true },
      statuscolumn = { enabled = true },
      words = { enabled = true },
    },
  },
}

-- Folding (Tree-sitter)
vim.opt.foldmethod = "expr"
vim.opt.foldexpr = "nvim_treesitter#foldexpr()"
vim.opt.foldenable = true
vim.opt.foldlevel = 99      -- keep everything open by default
vim.opt.foldlevelstart = 99 -- same on buffer open
vim.opt.foldcolumn = "auto:1"
vim.opt.foldtext = "v:lua.vim.treesitter.foldtext()"
vim.opt.fillchars = {
  fold = " ",
  foldopen = "",
  foldclose = "",
  foldsep = " ",
}

-- Mouse support in all modes
vim.opt.mouse = "a"

-- Keymaps for markdown toc/preview
lvim.keys.normal_mode["<leader>mT"] = ":Mtoc<CR>"
lvim.keys.normal_mode["<leader>mp"] = ":MarkdownPreview<CR>"
lvim.keys.normal_mode["<leader>mP"] = ":MarkdownPreviewStop<CR>"

-- Keymaps for folding/treesitter
lvim.keys.normal_mode["zR"] = function()
  require("ufo").openAllFolds()
end

lvim.keys.normal_mode["zM"] = function()
  require("ufo").closeAllFolds()
end

lvim.keys.normal_mode["zp"] = function()
  require("ufo").peekFoldedLinesUnderCursor()
end

-- Window navigation: smart-splits handles nvim windows AND wezterm panes
-- with a single Ctrl+hjkl. Falls through to wezterm at the nvim window edge.
lvim.keys.normal_mode["<C-h>"] = "<cmd>SmartCursorMoveLeft<cr>"
lvim.keys.normal_mode["<C-j>"] = "<cmd>SmartCursorMoveDown<cr>"
lvim.keys.normal_mode["<C-k>"] = "<cmd>SmartCursorMoveUp<cr>"
lvim.keys.normal_mode["<C-l>"] = "<cmd>SmartCursorMoveRight<cr>"

-- Resize: Alt+hjkl resizes nvim window or wezterm pane based on context.
lvim.keys.normal_mode["<M-h>"] = "<cmd>SmartResizeLeft<cr>"
lvim.keys.normal_mode["<M-j>"] = "<cmd>SmartResizeDown<cr>"
lvim.keys.normal_mode["<M-k>"] = "<cmd>SmartResizeUp<cr>"
lvim.keys.normal_mode["<M-l>"] = "<cmd>SmartResizeRight<cr>"

-- Keep Tree-sitter for folding/treesj/context, but stop illuminate from using it (prevents error spam)
lvim.builtin.illuminate.options = {
  providers = { "lsp", "regex" },
}

-- Add additional leader commands to leader pop-up
local wk = require("which-key")
wk.register({
  t = {
    name = "Treesitter",
    c = { "<cmd>lua (function() local t=require('treesitter-context'); if t.enabled() then t.disable() else t.enable() end end)()<CR>", "Toggle TS context" },
    g = { "<cmd>lua require('treesitter-context').go_to_context()<CR>", "Go to TS context" },
  },
  j = { "<cmd>lua require('treesj').toggle()<CR>", "Toggle join/split" },
  h = { name = "Harpoon" },
  x = { name = "Trouble" },
}, { prefix = "<leader>" })

-- Filter the position_encoding warning without redefining vim.notify
local orig_notify = vim.notify

vim.notify = function(msg, level, opts)
  if msg and (
    msg:match("position_encoding param is required") or
    msg:match("deprecated")
  ) then
    return
  end
  orig_notify(msg, level, opts)
end

-- Nvim-tree
lvim.builtin.nvimtree.setup.view.side = "right"
lvim.builtin.nvimtree.setup.view.width = 50

-- Windows clipboard fix maybe
vim.opt.clipboard:append("unnamedplus")
vim.g.clipboard = {
  name = "win32yank-wsl",
  copy = {
    ["+"] = "win32yank.exe -i --crlf",
    ["*"] = "win32yank.exe -i --crlf",
  },
  paste = {
    ["+"] = "win32yank.exe -o --lf",
    ["*"] = "win32yank.exe -o --lf",
  },
  cache_enabled = 0,
}

-- Detach yamlls from helm buffers after it attaches
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(args)
    local bufnr = args.buf
    local client = vim.lsp.get_client_by_id(args.data.client_id)

    if not client then
      return
    end

    if vim.bo[bufnr].filetype == "helm" and client.name == "yamlls" then
      vim.schedule(function()
        vim.lsp.buf_detach_client(bufnr, client.id)
        vim.diagnostic.reset(nil, bufnr)
      end)
    end
  end,
})

local lspconfig = require("lspconfig")

lspconfig.helm_ls.setup({
  settings = {
    ["helm-ls"] = {
      yamlls = {
        enabled = false,
      },
    },
  },
})

-- Spell check
vim.opt.spell = true
vim.opt.spelllang = { "en_us" }

-- Force strong underline style
vim.cmd [[
highlight SpellBad gui=undercurl guisp=#ff0000
highlight SpellCap gui=undercurl guisp=#ffaa00
highlight SpellRare gui=undercurl guisp=#00ffff
highlight SpellLocal gui=undercurl guisp=#00ff00
]]
