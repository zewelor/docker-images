vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.signcolumn = "yes"
vim.opt.termguicolors = true
vim.opt.cursorline = true
vim.opt.expandtab = true
vim.opt.shiftwidth = 2
vim.opt.tabstop = 2
vim.opt.smartcase = true
vim.opt.ignorecase = true
vim.opt.mouse = ""
vim.opt.splitright = true
vim.opt.splitbelow = true
vim.opt.updatetime = 200
vim.opt.timeoutlen = 300
vim.opt.scrolloff = 4
vim.opt.sidescrolloff = 8

vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  local out = vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "--branch=stable",
    "https://github.com/folke/lazy.nvim.git",
    lazypath,
  })
  if vim.v.shell_error ~= 0 then
    error(out)
  end
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  spec = {
    {
      "catppuccin/nvim",
      name = "catppuccin",
      lazy = false,
      priority = 1000,
      opts = {
        flavour = "latte",
        transparent_background = true,
      },
      config = function(_, opts)
        require("catppuccin").setup(opts)
        vim.cmd.colorscheme("catppuccin")
      end,
    },
    {
      "nvim-mini/mini.icons",
      opts = {},
      init = function()
        package.preload["nvim-web-devicons"] = function()
          require("mini.icons").mock_nvim_web_devicons()
          return package.loaded["nvim-web-devicons"]
        end
      end,
    },
    {
      "nvim-mini/mini.surround",
      version = "*",
      opts = {},
    },
    {
      "nvim-mini/mini.pairs",
      event = "InsertEnter",
      opts = {},
    },
    {
      "nvim-mini/mini.align",
      opts = {},
    },
    {
      "folke/which-key.nvim",
      event = "VeryLazy",
      opts = {
        expand = 1,
        delay = function(ctx)
          return ctx.plugin and 0 or 300
        end,
      },
    },
    {
      "folke/ts-comments.nvim",
      lazy = false,
      opts = {},
    },
    {
      "nvim-neo-tree/neo-tree.nvim",
      branch = "v3.x",
      lazy = false,
      opts = {
        log_to_file = false,
        filesystem = {
          filtered_items = {
            hide_dotfiles = false,
            hide_gitignored = false,
            hide_hidden = false,
            hide_ignored = false,
            show_hidden_count = false,
          },
        },
      },
      dependencies = {
        "nvim-lua/plenary.nvim",
        "MunifTanjim/nui.nvim",
        "nvim-mini/mini.icons",
      },
      keys = {
        { "<leader>e", "<cmd>Neotree toggle filesystem left<cr>", desc = "Toggle file tree" },
        { "<leader>o", "<cmd>Neotree focus filesystem left<cr>", desc = "Focus file tree" },
      },
    },
    {
      "lewis6991/gitsigns.nvim",
      event = { "BufReadPre", "BufNewFile" },
      opts = {},
    },
    {
      "nvim-telescope/telescope.nvim",
      tag = "0.1.8",
      dependencies = {
        "nvim-lua/plenary.nvim",
      },
      keys = {
        { "<leader>ff", function() require("telescope.builtin").find_files() end, desc = "Find files" },
        { "<leader>fg", function() require("telescope.builtin").live_grep() end, desc = "Live grep" },
      },
      opts = function()
        if vim.fn.executable("fdfind") ~= 1 then
          return {}
        end

        return {
          pickers = {
            find_files = {
              find_command = { "fdfind", "--type", "f", "--hidden", "--exclude", ".git" },
            },
          },
        }
      end,
    },
  },
})

local map = vim.keymap.set

local function stage_selected_hunk()
  local gitsigns = require("gitsigns")
  local start_line = vim.fn.line("v")
  local end_line = vim.fn.line(".")

  if start_line > end_line then
    start_line, end_line = end_line, start_line
  end

  gitsigns.stage_hunk({ start_line, end_line })
end

map("n", "<leader>?", function()
  require("which-key").show({ global = true })
end, { desc = "Global keymaps" })

map("n", "<leader>hs", function()
  require("gitsigns").stage_hunk()
end, { desc = "Stage hunk" })

map("x", "<leader>hs", stage_selected_hunk, { desc = "Stage selected lines" })

map("n", "<leader>hS", function()
  require("gitsigns").stage_buffer()
end, { desc = "Stage buffer" })

map("n", "gsa", function()
  require("mini.surround")
  MiniSurround.add()
end, { desc = "Add surrounding" })

map("x", "gsa", function()
  require("mini.surround")
  MiniSurround.add("visual")
end, { desc = "Add surrounding for selection" })

map("n", "gsd", function()
  require("mini.surround")
  MiniSurround.delete()
end, { desc = "Delete surrounding" })

map("n", "gsr", function()
  require("mini.surround")
  MiniSurround.replace()
end, { desc = "Replace surrounding" })

map("n", "gsf", function()
  require("mini.surround")
  MiniSurround.find()
end, { desc = "Find surrounding" })

map("n", "gsh", function()
  require("mini.surround")
  MiniSurround.highlight()
end, { desc = "Highlight surrounding" })

map("n", "gsn", function()
  require("mini.surround")
  MiniSurround.update_n_lines()
end, { desc = "Update surround n_lines" })

map("n", "<C-_>", "gcc", { remap = true, silent = true, desc = "Toggle comment line" })
map("x", "<C-_>", "gc", { remap = true, silent = true, desc = "Toggle comment selection" })
