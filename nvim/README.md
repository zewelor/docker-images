# nvim

Minimal Neovim image based on Docker Hardened Images Debian.

## Run

```bash
docker run --rm -it -v "$PWD":/workspace ghcr.io/zewelor/nvim
```

## Included plugins

- `catppuccin/nvim` - colorscheme
- `nvim-neo-tree/neo-tree.nvim` - file tree
- `folke/which-key.nvim` - keybinding hints

## Notes

- The image keeps the config intentionally minimal and non-opinionated.
- Plugins are installed at build time to avoid network access at runtime.
