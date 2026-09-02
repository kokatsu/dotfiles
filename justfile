# Dotfiles task runner

lua_dirs := ".config/nvim .config/wezterm"
deno_dirs := "karabiner-config scripts"
deno_files := ".config/zeno/config.ts .config/claude/hooks/herdr-cache-token.ts"

# List available recipes
default:
    @just --list

# Run all checks
check: check-static nix-eval

# Run all checks except flake evaluation (CI entry point; nix-eval is covered by `nix flake check`)
check-static: fmt-check lint typos banned-commands-test herdr-peer-guard-test herdr-peer-test

# Run all formatters
fmt: lua-fmt nix-fmt biome-fmt deno-fmt shfmt toml-fmt yaml-fmt

# Check all formatting (no write)
fmt-check: lua-fmt-check nix-fmt-check biome-fmt-check deno-fmt-check shfmt-check toml-fmt-check yaml-fmt-check

# Run all linters
lint: nix-lint nix-dead-code lua-lint shellcheck deno-lint deno-check biome-lint markdownlint toml-check editorconfig gitleaks-smoke-test

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

# Lint Nix files
nix-lint:
    statix check .

# Find unused Nix declarations
nix-dead-code:
    deadnix --fail .

# Evaluate flake outputs and checks without building them
nix-eval:
    nix flake check "path:$PWD" --no-build --impure --no-update-lock-file

# Format TypeScript with biome
biome-fmt:
    biome format --write .

# Check TypeScript formatting with biome (no write)
biome-fmt-check:
    biome format .

# Lint TypeScript with biome
biome-lint:
    biome lint .

# Run a deno subcommand over all configured Deno dirs and files
_deno-each cmd:
    @for dir in {{ deno_dirs }}; do \
      echo "deno {{ cmd }}: $dir"; \
      deno {{ cmd }} "$dir"; \
    done
    @for file in {{ deno_files }}; do \
      echo "deno {{ cmd }}: $file"; \
      deno {{ cmd }} "$file"; \
    done

# Format Deno TypeScript files
deno-fmt:
    @just _deno-each fmt

# Check Deno TypeScript formatting (no write)
deno-fmt-check:
    @just _deno-each "fmt --check"

# Lint TypeScript with deno
deno-lint:
    @just _deno-each lint

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

# List git-tracked shell scripts (shfmt -f detects them by extension or shebang)
# 手書きのリストだと拡張子なしの bin/* や新規ディレクトリのスクリプトを取りこぼすため動的に列挙する。
# 除外: *.zsh は shfmt/shellcheck 非対応 (lefthook の zsh-lint が `zsh -n` で見る)、
# wezterm-integration.sh は WezTerm 由来の vendored ファイル。
_sh-files:
    @git ls-files -z | xargs -0 shfmt -f \
      | grep -v -e '\.zsh$' -e '^\.config/zsh/wezterm-integration\.sh$'

# Lint shell scripts
shellcheck:
    @just _sh-files | xargs shellcheck

# Format shell scripts
shfmt:
    @just _sh-files | xargs shfmt -w

# Check shell script formatting (no write)
shfmt-check:
    @just _sh-files | xargs shfmt -d

# Lint Markdown files (除外は .markdownlintignore が担う)
markdownlint:
    @git ls-files -z '*.md' | xargs -0 markdownlint

# Format TOML files
toml-fmt:
    @git ls-files -z '*.toml' | xargs -0 taplo format

# Check TOML formatting (no write)
toml-fmt-check:
    @git ls-files -z '*.toml' | xargs -0 taplo format --check

# Validate TOML documents
toml-check:
    @git ls-files -z '*.toml' | xargs -0 taplo check

# Verify built-in Gitleaks rules remain active through the repository config.
# Split the synthetic PAT so scanning this file itself does not flag the canary.
gitleaks-smoke-test:
    @canary='ghp_0123456789abcdef''0123456789abcdef0123'; \
      result_code=0; \
      printf 'token = "%s"\n' "$canary" \
        | gitleaks stdin --config .gitleaks.toml --no-banner --redact >/dev/null 2>&1 \
        || result_code=$?; \
      if [ "$result_code" -ne 1 ]; then \
        echo "gitleaks smoke test failed: expected leak exit code 1, got $result_code" >&2; \
        exit 1; \
      fi

# Format YAML files
yaml-fmt:
    @git ls-files -z '*.yml' '*.yaml' | xargs -0 yamlfmt

# Check YAML formatting (no write)
yaml-fmt-check:
    @git ls-files -z '*.yml' '*.yaml' | xargs -0 yamlfmt -lint

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

# Verify pr.yml hash-update sed patterns match overlay structure
hash-patterns-test:
    bash scripts/test-hash-patterns.sh

# Verify the banned-commands hook blocks shallow git fetch/pull without false positives
banned-commands-test:
    bash scripts/test-banned-commands.sh

# Verify raw Herdr input commands cannot bypass the shared peer guard
herdr-peer-guard-test:
    bash scripts/test-herdr-peer-command-guard.sh

# Verify peer resolution and session bootstrap behavior
herdr-peer-test:
    bash scripts/test-herdr-peer.sh

# Verify Renovate regex patterns match overlay files
renovate-patterns-test:
    deno run --allow-read scripts/test-renovate-patterns.ts

# Build karabiner.json from karabiner.ts
karabiner-build:
    cd karabiner-config && deno run --allow-env --allow-read --allow-write ./karabiner.ts

# Dry-run karabiner.json generation (no write)
karabiner-dry-run:
    cd karabiner-config && deno run --allow-env --allow-read --allow-write ./karabiner.ts --dry-run
