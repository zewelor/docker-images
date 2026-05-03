# nvim

Minimal Neovim image based on Docker Hardened Images Debian.

## Run

```bash
docker run --rm -it -v "$PWD":/workspace ghcr.io/zewelor/nvim
```

## Included plugins

- `catppuccin/nvim` - colorscheme
- `nvim-mini/mini.pairs` - autopairs
- `nvim-neo-tree/neo-tree.nvim` - file tree
- `lewis6991/gitsigns.nvim` - git signs in the gutter
- `nvim-telescope/telescope.nvim` - file and text search
- `folke/which-key.nvim` - keybinding hints

## Included tools

- `git`
- `ripgrep`
- `fd-find`

## Notes

- The image keeps the config intentionally minimal and non-opinionated.
- Plugins are installed at build time to avoid network access at runtime.
