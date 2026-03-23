import { defineConfig, type Snippet } from "jsr:@yuki-yano/zeno@^0.4.1";

const isDarwin = Deno.build.os === "darwin";
const isLinux = Deno.build.os === "linux";

export default defineConfig(({ env }) => {
  const isWSL = !!env.WSL_DISTRO_NAME;

  const snippets: Snippet[] = [
    // -------------------------------------------------------------------------
    // Tools
    // -------------------------------------------------------------------------
    { name: "bat", keyword: "bag", snippet: "bat --style grid" },
    { name: "fd", keyword: "fd", snippet: "fd --hidden" },
    { name: "eza", keyword: "e", snippet: "eza --icons --git" },
    { name: "eza -a", keyword: "ea", snippet: "eza -a --icons --git" },
    {
      name: "eza -aahl",
      keyword: "ee",
      snippet: "eza -aahl --icons --git --time-style='+%Y-%m-%d %H:%M:%S'",
    },
    { name: "lazydocker", keyword: "lzd", snippet: "lazydocker" },
    {
      name: "git-graph",
      keyword: "gg",
      snippet:
        "git-graph --model catppuccin-mocha --style bold --color always --current --max-count 50 --format '%H%d %s' --highlight-head 'bold,black,bg:bright_yellow'",
    },
    { name: "lazygit", keyword: "lg", snippet: "lazygit" },
    { name: "neovim", keyword: "vi", snippet: "nvim" },
    {
      name: "rg (exclude uuid)",
      keyword: "rgu",
      snippet:
        "rg -P '^(?!.*[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}).*\\K{{pattern}}'",
    },
    { name: "yazi", keyword: "y", snippet: "yazi" },

    // -------------------------------------------------------------------------
    // Git
    // -------------------------------------------------------------------------
    {
      name: "git status",
      keyword: "gs",
      snippet: "git status --short --branch",
    },
    { name: "git add", keyword: "ga", snippet: "git add" },
    { name: "git commit", keyword: "gc", snippet: "git commit" },
    {
      name: "git commit -m",
      keyword: "gcm",
      snippet: "git commit -m '{{message}}'",
    },
    {
      name: "git commit --amend",
      keyword: "gca",
      snippet: "git commit --amend",
    },
    { name: "git push", keyword: "gp", snippet: "git push" },
    { name: "git pull", keyword: "gpl", snippet: "git pull" },
    { name: "git diff", keyword: "gd", snippet: "git diff" },
    { name: "git checkout", keyword: "gco", snippet: "git checkout" },
    { name: "git switch", keyword: "gsw", snippet: "git switch" },
    { name: "git branch", keyword: "gb", snippet: "git branch" },
    {
      name: "git log --oneline",
      keyword: "gl",
      snippet: "git log --oneline",
    },
    { name: "git stash", keyword: "gst", snippet: "git stash" },

    // -------------------------------------------------------------------------
    // Utility (global snippets)
    // -------------------------------------------------------------------------
    {
      name: "null",
      keyword: "N",
      snippet: ">/dev/null 2>&1",
      context: { lbuffer: ".+\\s" },
    },
    {
      name: "exclude uuid",
      keyword: "nuid",
      snippet:
        "| rg -v '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'",
      context: { lbuffer: ".+\\s" },
    },
  ];

  // ---------------------------------------------------------------------------
  // OS-specific snippets
  // ---------------------------------------------------------------------------
  if (isLinux) {
    snippets.push({
      name: "clear & fastfetch",
      keyword: "c",
      snippet: "clear && fastfetch",
    });
  }

  if (isWSL) {
    snippets.push({ name: "copy (WSL)", keyword: "copy", snippet: "clip.exe" });
  }

  if (isDarwin) {
    snippets.push({
      name: "darwin-rebuild",
      keyword: "rebuild",
      snippet:
        "sudo HOSTNAME=$(hostname -s) darwin-rebuild switch --flake ~/workspace/dotfiles --impure",
    });
  }

  return { snippets };
});
