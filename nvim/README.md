# nvim

Minimal Neovim image for lightweight editing in containers and Kubernetes debug sessions.

The image is built on Docker Hardened Images Debian and keeps the runtime intentionally small, predictable, and editing-focused. It is designed for cases where full personal dotfiles would be overkill, especially when opening files through ephemeral debug containers such as `nvim_pod`.

## Goals

- fast startup and low operational overhead
- useful file navigation and search out of the box
- build-time plugin installation with no runtime network dependency
- practical Git support without turning the image into a full development environment

## Build

```bash
docker build -t ghcr.io/zewelor/nvim ./nvim
```

## Run

```bash
docker run --rm -it -v "$PWD":/workspace ghcr.io/zewelor/nvim
```

Runtime defaults:

- working directory: `/workspace`
- user: `65532:65532`
- `HOME=/tmp`
- `GIT_CONFIG_COUNT=1`, `GIT_CONFIG_KEY_0=safe.directory`, `GIT_CONFIG_VALUE_0=*`
- `GIT_PAGER=cat`
- `XDG_CONFIG_HOME=/etc/xdg`

## Included tools

- `nvim`
- `git`
- `ssh`
- `ssh-keyscan`
- `ripgrep`
- `fd-find`

`fd-find` is wired so Telescope can use `fdfind` in Debian-based images.

For Git-over-SSH, mount SSH material under `/tmp/.ssh` or run the container with a user that can read your mounted private keys.

## Included plugins

- `catppuccin/nvim` - colorscheme (`latte`, transparent background)
- `nvim-mini/mini.icons` - icon provider for UI plugins
- `nvim-mini/mini.align` - lightweight interactive alignment for structured text
- `nvim-mini/mini.pairs` - lightweight autopairs
- `nvim-mini/mini.surround` - lightweight surround editing
- `folke/which-key.nvim` - keybinding hints
- `folke/ts-comments.nvim` - tree-sitter aware comment support for built-in `gc`
- `nvim-neo-tree/neo-tree.nvim` - file tree
- `lewis6991/gitsigns.nvim` - Git gutter signs and hunk actions
- `nvim-telescope/telescope.nvim` - file and text search
- `nvim-lua/plenary.nvim` - Telescope helper dependency
- `MunifTanjim/nui.nvim` - Neo-tree UI dependency

Useful mappings:

- `<leader>e` - toggle Neo-tree
- `<leader>o` - focus Neo-tree
- `<leader>ff` - find files
- `<leader>fg` - live grep
- `<leader>?` - show global keymaps with which-key
- `ga` - align text with `mini.align`
- `gsa` / `gsd` / `gsr` - add, delete, or replace surroundings
- `gsf` / `gsh` / `gsn` - find, highlight, or adjust surround scope
- `<leader>hs` - stage hunk or selected lines
- `<leader>hS` - stage current buffer
- `<C-_>` - toggle comments with built-in `gc`

Small built-in QoL defaults:

- extra horizontal context via `sidescrolloff=8`
- Neo-tree shows dotfiles, gitignored files, and ignored files instead of collapsing them into `N hidden`

## Intentionally excluded

This image does not try to be a full IDE. It intentionally does not add:

- LSP servers
- Tree-sitter grammars beyond what Debian ships with Neovim itself
- formatters or linters
- language-specific toolchains
- the full personal Neovim configuration from the dotfiles repo

If a feature increases image weight or maintenance burden without helping the core edit-in-a-container workflow, it stays out.

## Build and update model

- config lives in `config/nvim/` and is copied to `/etc/xdg/nvim`
- plugins are installed during the image build with `Lazy! sync`
- plugin `.git` directories are removed after sync to avoid shipping unused metadata
- runtime never installs or updates plugins
- changing plugin versions means editing `config/nvim/init.lua` and rebuilding the image

This keeps runtime behavior deterministic and avoids network access from production pods or ephemeral debug containers.

## Size trade-offs

The image is currently about `151 MiB` on a local `amd64` build.

Largest runtime chunks:

- `/usr/lib/git-core` - about `25 MiB`
- `/usr/share/nvim` - about `24 MiB`
- `/usr/share/terminfo` - about `12 MiB`
- `/usr/local/share/nvim` - about `9.9 MiB`

The obvious candidate for future trimming is `git-core`, but it stays for now.

Why:

- removing it still leaves many basic local commands working (`git diff`, `git blame`, `git show`, `git status`, `git worktree`)
- but it turns the image into a partial Git client
- for example, `git submodule` disappears without `git-core`
- `git-core` also carries helper programs used by non-local Git flows

For this image, predictable Git behavior is worth more than saving a few extra megabytes.

The image still contains about `2.7 MiB` of manpages and about `380 KiB` of docs from the Debian Hardened base image. Those files are in a lower base layer, so deleting them in a later `RUN rm -rf ...` step would not materially shrink the final pulled image.

## Maintenance notes

- `telescope.nvim` is pinned to `0.1.8` because Debian Trixie currently ships Neovim `0.10.4`, while newer Telescope releases require Neovim `0.11+`
- Git templates are copied into the runtime image so `git init` works without template warnings
- SSH support intentionally includes `ssh` and `ssh-keyscan`, but not `scp`, `sftp`, or `ssh-keygen`, because Git-over-SSH is the target use case
- if you add new runtime tools, remember to copy both the executable and any required symlink targets or shared libraries into the runtime stage

## Primary use case

This image is primarily meant for:

- opening project directories with `docker run`
- editing files inside Kubernetes workloads through ephemeral debug containers
- backing the `nvim_pod` helper from the dotfiles repo

It is not meant to replace a full local workstation Neovim setup.
