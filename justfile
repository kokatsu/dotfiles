# Dotfiles task runner

lua_dirs := ".config/nvim .config/wezterm"
deno_dirs := "karabiner-config scripts"
# deno_dirs の外にある .ts は全て単体の Deno スクリプトなので、手書きせず git から列挙する
deno_files := `git ls-files '*.ts' | grep -vE '^(karabiner-config|scripts)/' | tr '\n' ' '`

# List available recipes
default:
    @just --list

# Run all checks
check: check-static nix-eval

# Run all checks except flake evaluation (CI entry point; nix-eval is covered by `nix flake check`)
check-static: fmt-check lint typos banned-commands-test codex-auto-title-test herdr-peer-guard-test herdr-peer-test reliability-test hash-patterns-test renovate-patterns-test nvim-test

# Test automatic Codex thread naming without starting a model turn
codex-auto-title-test:
    deno test scripts/test-codex-auto-title.ts
    bash scripts/test-codex-auto.sh

# Run all formatters
fmt: lua-fmt nix-fmt biome-fmt deno-fmt shfmt toml-fmt yaml-fmt

# Check all formatting (no write)。biome は format と lint をまとめて `biome-ci` (lint 側) で見る
fmt-check: lua-fmt-check nix-fmt-check deno-fmt-check shfmt-check toml-fmt-check yaml-fmt-check

# Run all linters
lint: nix-lint nix-dead-code lua-lint shellcheck zsh-lint deno-lint deno-check biome-ci markdownlint toml-check editorconfig gitleaks-smoke-test

# List git-tracked Lua files (vendored yazi plugins are excluded)
# lua_dirs だけだと .config/yazi/init.lua や scripts/*.lua を取りこぼすため動的に列挙する。
_lua-files:
    @git ls-files '*.lua' | grep -v '^\.config/yazi/plugins/'

# Format Lua files
lua-fmt:
    @just _lua-files | xargs stylua

# Check Lua formatting (no write)
lua-fmt-check:
    @just _lua-files | xargs stylua --check

# Lint Lua files with selene
# lua_dirs 以外の Lua も見る: scripts/test-nvim-config.lua は vim グローバルを使うので
# nvim の設定、.config/yazi/init.lua は素の Lua なのでリポジトリ直下の selene.toml で検査する
lua-lint:
    @for dir in {{ lua_dirs }}; do \
      echo "selene: $dir"; \
      (cd "$dir" && selene .) || exit $?; \
    done
    @echo "selene: scripts/test-nvim-config.lua"
    @selene --config .config/nvim/selene.toml scripts/test-nvim-config.lua
    @echo "selene: .config/yazi/init.lua"
    @selene .config/yazi/init.lua

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

# Format JSON with biome (リポジトリの .ts は全て Deno 管理で biome の対象外)
biome-fmt:
    biome format --write .

# Check formatting, lint, and assists with biome (lefthook の `biome check` と同じ範囲)
biome-ci:
    biome ci .

# Run a deno subcommand over all configured Deno dirs and files
_deno-each cmd:
    @for dir in {{ deno_dirs }}; do \
      echo "deno {{ cmd }}: $dir"; \
      deno {{ cmd }} "$dir" || exit $?; \
    done
    @for file in {{ deno_files }}; do \
      echo "deno {{ cmd }}: $file"; \
      deno {{ cmd }} "$file" || exit $?; \
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

# Type-check Deno TypeScript files (git 管理下のものだけ。find だと untracked も拾う)
deno-check:
    @for dir in {{ deno_dirs }}; do \
      echo "deno check: $dir"; \
      (cd "$dir" && git ls-files -z '*.ts' | xargs -0 deno check) || exit $?; \
    done
    @for file in {{ deno_files }}; do \
      echo "deno check: $file"; \
      deno check "$file" || exit $?; \
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
    @just _sh-files | xargs shellcheck -x

# Syntax-check Zsh startup files (shellcheck / shfmt は zsh を解釈しない)
zsh-lint:
    @git ls-files -z '*.zsh' .config/zsh/.zshrc .config/zsh/.zimrc | xargs -0 -n1 zsh -n

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

# Verify pr.yml hash-update sed patterns match overlay structure, and the detect script against fixtures
hash-patterns-test:
    bash scripts/test-hash-patterns.sh
    bash scripts/test-detect-hash-updates.sh

# Verify the banned-commands hook blocks shallow git fetch/pull without false positives
banned-commands-test:
    bash scripts/test-banned-commands.sh

# Verify raw Herdr input commands cannot bypass the shared peer guard
herdr-peer-guard-test:
    bash scripts/test-herdr-peer-command-guard.sh

# Verify peer resolution and session bootstrap behavior
herdr-peer-test:
    bash scripts/test-herdr-peer.sh

# Verify check failures, concurrent feed updates, and activation retries
reliability-test:
    bash scripts/test-check-failures.sh
    bash scripts/test-feed-status.sh
    bash scripts/test-zimfw-activation.sh
    bash scripts/test-daily.sh

# Verify Renovate regex patterns match overlay files
renovate-patterns-test:
    deno run --allow-read scripts/test-renovate-patterns.ts

# Build karabiner.json from karabiner.ts
karabiner-build:
    cd karabiner-config && deno run --allow-env --allow-read --allow-write ./karabiner.ts

# Dry-run karabiner.json generation (no write)
karabiner-dry-run:
    cd karabiner-config && deno run --allow-env --allow-read --allow-write ./karabiner.ts --dry-run
