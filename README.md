# kokatsu's dotfiles

[![CI](https://github.com/kokatsu/dotfiles/actions/workflows/check.yml/badge.svg)](https://github.com/kokatsu/dotfiles/actions/workflows/check.yml)
[![NixOS](https://img.shields.io/badge/NixOS-5277C3?style=flat&logo=nixos&logoColor=white)](https://nixos.org)
[![Home Manager](https://img.shields.io/badge/Home_Manager-5277C3?style=flat&logo=nixos&logoColor=white)](https://github.com/nix-community/home-manager)
[![Checked with Biome](https://img.shields.io/badge/Checked_with-Biome-60a5fa?style=flat&logo=biome)](https://biomejs.dev)

Dotfiles repository for managing shell and tool configurations across macOS and Linux systems using **Nix + Home Manager** with Flakes.

## Features

- 🔄 **Declarative & Reproducible** - All configurations managed through Nix Flakes
- 🖥️ **Multi-platform** - Supports Linux (x86_64, aarch64) and macOS ARM (Apple Silicon)
- 📦 **Unified Package Management** - All CLI tools installed via Home Manager
- 🔗 **Automated Symlinks** - Dotfiles automatically linked to `~/.config/`

## Setup

### Prerequisites

- macOS (arm64) or Linux (x86_64 / aarch64)
- curl (for Nix installer)

### Installation

```bash
# Install Nix (using Determinate Systems installer)
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install

# Clone the repository
git clone https://github.com/kokatsu/dotfiles.git ~/dotfiles
cd ~/dotfiles

# Build and activate Home Manager configuration
DOTFILES_DIR="$PWD" nix run home-manager -- switch --flake . --impure
```

## Usage

### Apply Configuration Changes

```bash
# User environment (packages / dotfiles) on both Linux and macOS.
# Set this to the actual repository path on each PC.
DOTFILES_DIR="$HOME/dotfiles" home-manager switch --flake "$HOME/dotfiles" --impure

# macOS system settings + Homebrew (quit Chrome first: casks get upgraded in place)
sudo HOSTNAME=$(hostname -s) DOTFILES_DIR="$HOME/dotfiles" darwin-rebuild switch --flake "$HOME/dotfiles" --impure
```

### Update Packages

```bash
nix flake update
DOTFILES_DIR="$HOME/dotfiles" home-manager switch --flake "$HOME/dotfiles" --impure
```

### Development

```bash
nix develop        # Enter development shell with every linter / formatter
just check         # Format check, lint, typos, script tests, and flake evaluation
just fmt           # Format everything (Nix, Lua, shell, TOML, YAML, JSON, TypeScript)
just               # List all recipes
```

Lefthook runs a subset of these on commit and push (formatters, linters, gitleaks, commitlint); the script tests and flake evaluation only run through `just check` and CI.

## Directory Structure

```text
.
├── flake.nix          # Flake outputs and Home Manager/nix-darwin builders
├── flake.lock         # Locked dependencies for reproducibility
├── justfile           # Task runner: checks, formatters, tests
├── nix/
│   ├── home/          # Home Manager modules (packages, files, programs, services)
│   ├── darwin/        # macOS system and Homebrew configuration
│   └── overlays/      # Custom packages and upstream workarounds
├── bin/               # User scripts, linked to ~/.local/bin/scripts and on PATH
├── scripts/           # Test and helper scripts used by just and CI
├── karabiner-config/  # Karabiner-Elements rules written with karabiner.ts
└── .config/           # Dotfile sources linked by Home Manager
    ├── zsh/           # Zsh shell configuration
    ├── nvim/          # Neovim configuration
    ├── git/           # Git configuration
    ├── wezterm/       # WezTerm terminal configuration
    ├── claude/        # Claude Code settings, hooks, and skills
    └── ...            # Other tool configurations
```

## License

MIT
