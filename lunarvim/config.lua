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

-- Explorer navigation
-- Window navigation (move between splits easily)
lvim.keys.normal_mode["<C-S-h>"] = "<C-w>h"
lvim.keys.normal_mode["<C-S-j>"] = "<C-w>j"
lvim.keys.normal_mode["<C-S-k>"] = "<C-w>k"
lvim.keys.normal_mode["<C-S-l>"] = "<C-w>l"

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
