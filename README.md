# kokatsu's dotfiles

[![CI](https://github.com/kokatsu/dotfiles/actions/workflows/check.yml/badge.svg)](https://github.com/kokatsu/dotfiles/actions/workflows/check.yml)
[![NixOS](https://img.shields.io/badge/NixOS-5277C3?style=flat&logo=nixos&logoColor=white)](https://nixos.org)
[![Home Manager](https://img.shields.io/badge/Home_Manager-5277C3?style=flat&logo=nixos&logoColor=white)](https://github.com/nix-community/home-manager)
[![Checked with Biome](https://img.shields.io/badge/Checked_with-Biome-60a5fa?style=flat&logo=biome)](https://biomejs.dev)

Dotfiles repository for managing shell and tool configurations across macOS and Linux systems using **Nix + Home Manager** with Flakes.

## Features

- 🔄 **Declarative & Reproducible** - All configurations managed through Nix Flakes
- 🖥️ **Multi-platform** - Supports Linux (x86_64), macOS ARM (Apple Silicon), and macOS Intel
- 📦 **Unified Package Management** - All CLI tools installed via Home Manager
- 🔗 **Automated Symlinks** - Dotfiles automatically linked to `~/.config/`

## Setup

### Prerequisites

- macOS (arm64/x86_64) or Linux (x86_64)
- curl (for Nix installer)

### Installation

```bash
# Install Nix (using Determinate Systems installer)
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install

# Clone the repository
git clone https://github.com/kokatsu/dotfiles.git ~/dotfiles
cd ~/dotfiles

# Build and activate Home Manager configuration
nix run home-manager -- switch --flake . --impure
```

## Usage

### Apply Configuration Changes

```bash
# Home Manager only
home-manager switch --flake ~/dotfiles --impure

# macOS (nix-darwin)
sudo HOSTNAME=$(hostname -s) darwin-rebuild switch --flake ~/dotfiles --impure
```

### Update Packages

```bash
nix flake update
home-manager switch --flake ~/dotfiles --impure
```

### Development

```bash
nix develop        # Enter development shell
nix flake check    # Check flake configuration
nix fmt            # Format Nix files
```

## Directory Structure

```text
.
├── flake.nix          # Nix flake definition with Home Manager integration
├── flake.lock         # Locked dependencies for reproducibility
├── home.nix           # Home Manager configuration (packages, dotfiles)
└── .config/           # Dotfile configurations
    ├── zsh/           # Zsh shell configuration
    ├── nvim/          # Neovim configuration
    ├── git/           # Git configuration
    ├── wezterm/       # WezTerm terminal configuration
    └── ...            # Other tool configurations
```

## License

MIT
