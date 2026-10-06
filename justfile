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
check-static: (_run-all "fmt-check lint typos " + test_recipes)

test_recipes := "banned-commands-test codex-auto-title-test codex-guard-test gh-api-guard-test gh-api-method-test managed-paths-test herdr-peer-test herdr-macos-notify-test herdr-scripts-test reliability-test hash-patterns-test renovate-patterns-test regex-dialect-test ai-writing-hook-test textlint-response-config-test nvim-test wezterm-links-test"

# Run every test recipe
test: (_run-all test_recipes)

# just stops at the first failed dependency, which would hide every later result
_run-all recipes:
    #!/usr/bin/env bash
    set -uo pipefail
    failed=()
    for recipe in {{ recipes }}; do
      just "$recipe" || failed+=("$recipe")
    done
    if ((${#failed[@]})); then
      printf '\nfailed: %s\n' "${failed[*]}" >&2
      exit 1
    fi

# Test automatic Codex thread naming without starting a model turn
codex-auto-title-test:
    deno test scripts/test-codex-auto-title.ts
    bash scripts/test-codex-auto.sh

# Run all formatters
fmt: lua-fmt nix-fmt biome-fmt deno-fmt go-fmt shfmt toml-fmt yaml-fmt

# Check all formatting (no write)。biome は format と lint をまとめて `biome-ci` (lint 側) で見る
fmt-check: lua-fmt-check nix-fmt-check deno-fmt-check go-fmt-check shfmt-check toml-fmt-check yaml-fmt-check

# Run all linters
lint: nix-lint nix-dead-code lua-lint shellcheck zsh-lint deno-lint deno-check go-vet biome-ci markdownlint toml-check editorconfig gitleaks-smoke-test gitleaks-scan

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
# scripts/test-nvim-config.lua と scripts/test-wezterm-links.lua は vim グローバルを使うので nvim の設定で検査する
# .config/yazi/init.lua はリポジトリ直下の selene.toml で検査する (Yazi のグローバルはファイル側で許可)
lua-lint:
    @for dir in {{ lua_dirs }}; do \
      echo "selene: $dir"; \
      (cd "$dir" && selene .) || exit $?; \
    done
    @echo "selene: scripts/test-nvim-config.lua"
    @selene --config .config/nvim/selene.toml scripts/test-nvim-config.lua
    @echo "selene: scripts/test-wezterm-links.lua"
    @selene --config .config/nvim/selene.toml scripts/test-wezterm-links.lua
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

# Format Go files
go-fmt:
    gofmt -w tools

# Check Go formatting (no write)。gofmt -l は差分があっても exit 0 なので出力の有無で判定する
go-fmt-check:
    @out=$(gofmt -l tools); if [ -n "$out" ]; then echo "$out"; exit 1; fi

# Vet Go packages
go-vet:
    cd tools/agent-guard && go vet ./...

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
# mod は Claude Code 内でしか解決しない "claude-code" を import するため除き、`claude plugin test` で見る
deno-check:
    @for dir in {{ deno_dirs }}; do \
      echo "deno check: $dir"; \
      (cd "$dir" && git ls-files -z '*.ts' | xargs -0 deno check) || exit $?; \
    done
    @for file in {{ deno_files }}; do \
      case "$file" in .config/claude/mods/*) continue ;; esac; \
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
    @git ls-files -z '*.zsh' .config/zsh/.zshrc | xargs -0 -n1 zsh -n

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

# Scan the full git history for secrets. Lefthook only sees staged files and
# origin/main..HEAD and is bypassed by --no-verify, so CI must do the whole walk.
gitleaks-scan:
    gitleaks git --config .gitleaks.toml --no-banner --redact

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

# Exercise the real open-uri callback and shell argument boundary
wezterm-links-test:
    nvim --headless --clean -l scripts/test-wezterm-links.lua

# Verify pr.yml hash-update sed patterns match overlay structure, and the detect script against fixtures
# Deno は LD_* があると対象を限定した --allow-run での子プロセス起動を拒否する。Home Manager が Linux で
# LD_LIBRARY_PATH を、nix develop が macOS で LD_DYLD_PATH を設定する
hash-patterns-test:
    env -u LD_LIBRARY_PATH -u LD_DYLD_PATH bash scripts/test-hash-patterns.sh
    env -u LD_LIBRARY_PATH -u LD_DYLD_PATH bash scripts/test-detect-hash-updates.sh

# Verify the banned-commands hook (agent-guard) verdicts and its fail-closed behavior
banned-commands-test:
    cd tools/agent-guard && go test ./...
    bash scripts/test-banned-commands.sh

# Verify the Codex Bash hook (agent-guard codex) blocks raw Herdr input and banned commands
codex-guard-test:
    bash scripts/test-codex-command-guard.sh

# Verify the AI writing hook blocks, passes, and bails out on the right inputs
ai-writing-hook-test:
    bash scripts/test-ai-writing-hook.sh

# Verify which textlint rules the AI writing hook enforces and how they treat decisive inputs
textlint-response-config-test:
    bash scripts/test-textlint-response-config.sh

# Verify `gh api` is auto-allowed only when it is provably read-only
gh-api-guard-test:
    deno test --no-prompt --allow-read=scripts/gh-api-guard-cases.tsv --allow-run="$(command -v shfmt)" scripts/test-gh-api-guard.ts -- "$(command -v shfmt)"
    bash scripts/test-gh-api-guard.sh

# Verify the Codex `gh api` hook denies only real invocations without an explicit method
gh-api-method-test:
    bash scripts/test-gh-api-method-required.sh

# Verify edits are refused only when the path resolves into /nix/store
managed-paths-test:
    bash scripts/test-check-managed-paths.sh

# Measure the POSIX ERE / Go regexp gap in banned-commands.json for this OS and locale
regex-dialect-check:
    bash scripts/check-regex-dialect.sh

# Verify the dialect gap against the OS locale data (変換器そのものは banned-commands-test の go test が見る)
# nix の stdenv-darwin は PATH_LOCALE を nixpkgs のロケールデータへ向け、文字クラスが
# OS 標準と変わる。フックが動くのは devshell の外なので、OS 標準のデータで測る。
regex-dialect-test:
    env -u PATH_LOCALE bash scripts/check-regex-dialect.sh

# Verify peer resolution and session bootstrap behavior
herdr-peer-test:
    bash scripts/test-herdr-peer.sh

# Verify notification clicks select their own pane and dismissals leave focus alone
herdr-macos-notify-test:
    bash scripts/test-herdr-macos-notify.sh

# Verify layout scripts restore panes on failure and pane scripts surface errors
herdr-scripts-test:
    bash scripts/test-herdr-scripts.sh

# Verify check failures, concurrent feed updates, and activation retries
# Deno は LD_* があると対象を限定した --allow-run での子プロセス起動を拒否する。Home Manager が Linux で
# LD_LIBRARY_PATH を、nix develop が macOS で LD_DYLD_PATH を設定する
reliability-test:
    env -u LD_LIBRARY_PATH -u LD_DYLD_PATH deno test --no-prompt --allow-run="$(command -v yq),$(command -v deno)" scripts/test-feed-entries.ts -- "$(command -v yq)" "$(command -v deno)"
    env -u LD_LIBRARY_PATH -u LD_DYLD_PATH deno test --no-prompt --allow-run="$(command -v yq),$(command -v deno)" scripts/test-feed-opml.ts -- "$(command -v yq)" "$(command -v deno)"
    bash scripts/test-check-failures.sh
    bash scripts/test-codex-config-activation.sh
    bash scripts/test-feed-status.sh
    bash scripts/test-feed-watch.sh
    bash scripts/test-daily.sh
    bash scripts/test-wallpaper.sh
    bash scripts/test-sync-flake-inputs.sh

# Verify Renovate regex patterns match overlay files
renovate-patterns-test:
    deno run --allow-read scripts/test-renovate-patterns.ts

# Build karabiner.json from karabiner.ts
karabiner-build:
    cd karabiner-config && deno run --allow-env --allow-read --allow-write --allow-sys=homedir ./karabiner.ts

# Dry-run karabiner.json generation (no write)
karabiner-dry-run:
    cd karabiner-config && deno run --allow-env --allow-read --allow-write --allow-sys=homedir ./karabiner.ts --dry-run
