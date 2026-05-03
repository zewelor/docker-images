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
      "nvim-mini/mini.pairs",
      event = "InsertEnter",
      opts = {},
    },
    {
      "folke/which-key.nvim",
      event = "VeryLazy",
      opts = {
        delay = function(ctx)
          return ctx.plugin and 0 or 300
        end,
      },
    },
    {
      "nvim-neo-tree/neo-tree.nvim",
      branch = "v3.x",
      lazy = false,
      dependencies = {
        "nvim-lua/plenary.nvim",
        "MunifTanjim/nui.nvim",
        "nvim-mini/mini.icons",
      },
      keys = {
        { "<leader>e", "<cmd>Neotree toggle filesystem left<cr>", desc = "Toggle file tree" },
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
