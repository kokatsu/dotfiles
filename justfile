# Dotfiles task runner

lua_dirs := ".config/nvim .config/wezterm"
sh_files := ".config/claude/file-suggestion.sh .config/claude/hooks/run-deno-hook.sh .config/tmux/scripts/*.sh scripts/test-hash-patterns.sh"
deno_dirs := "karabiner-config scripts .config/claude/hooks"
deno_files := ".config/zeno/config.ts .config/claude/scripts/cc-metrics.ts"

# List available recipes
default:
    @just --list

# Run all checks
check: fmt-check lint typos

# Run all formatters
fmt: lua-fmt nix-fmt biome-fmt deno-fmt shfmt

# Check all formatting (no write)
fmt-check: lua-fmt-check nix-fmt-check biome-fmt-check deno-fmt-check shfmt-check

# Run all linters
lint: lua-lint shellcheck deno-lint deno-check biome-lint editorconfig

# Format Lua files
lua-fmt:
    stylua {{ lua_dirs }}

# Check Lua formatting (no write)
lua-fmt-check:
    stylua --check {{ lua_dirs }}

# Lint Lua files with selene
lua-lint:
    @for dir in {{ lua_dirs }}; do \
      echo "selene: $dir"; \
      (cd "$dir" && selene .); \
    done

# Format Nix files
nix-fmt:
    alejandra -q .

# Check Nix formatting (no write)
nix-fmt-check:
    alejandra -c .

# Format TypeScript with biome
biome-fmt:
    biome format --write .

# Check TypeScript formatting with biome (no write)
biome-fmt-check:
    biome format .

# Lint TypeScript with biome
biome-lint:
    biome lint .

# Format Deno TypeScript files
deno-fmt:
    @for dir in {{ deno_dirs }}; do \
      echo "deno fmt: $dir"; \
      deno fmt "$dir"; \
    done
    @for file in {{ deno_files }}; do \
      echo "deno fmt: $file"; \
      deno fmt "$file"; \
    done

# Check Deno TypeScript formatting (no write)
deno-fmt-check:
    @for dir in {{ deno_dirs }}; do \
      echo "deno fmt --check: $dir"; \
      deno fmt --check "$dir"; \
    done
    @for file in {{ deno_files }}; do \
      echo "deno fmt --check: $file"; \
      deno fmt --check "$file"; \
    done

# Type-check Deno TypeScript files
deno-check:
    @for dir in {{ deno_dirs }}; do \
      echo "deno check: $dir"; \
      (cd "$dir" && find . -name '*.ts' -exec deno check {} +); \
    done
    @for file in {{ deno_files }}; do \
      echo "deno check: $file"; \
      deno check "$file"; \
    done

# Lint TypeScript with deno
deno-lint:
    @for dir in {{ deno_dirs }}; do \
      echo "deno lint: $dir"; \
      deno lint "$dir"; \
    done
    @for file in {{ deno_files }}; do \
      echo "deno lint: $file"; \
      deno lint "$file"; \
    done

# Lint shell scripts
shellcheck:
    shellcheck {{ sh_files }}

# Format shell scripts
shfmt:
    shfmt -w {{ sh_files }}

# Check shell script formatting (no write)
shfmt-check:
    shfmt -d {{ sh_files }}

# Check EditorConfig compliance
editorconfig:
    editorconfig-checker

# Run typos spell checker
typos:
    typos

# Fix typos automatically
typos-fix:
    typos -w

# Test Neovim custom plugins (smoke test)
nvim-test:
    nvim --headless --clean -l scripts/test-nvim-config.lua
