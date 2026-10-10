{inputs}: let
  binaryReleases = import ./binary-releases.nix;
  npmPackages = import ./npm-packages.nix;
  buildFixes = import ./build-fixes.nix;
  sourceBuilds = import ./source-builds.nix;
  ccStatusline = import ./cc-statusline.nix {inherit inputs;};
  agentGuard = import ./agent-guard.nix;
  reportAgentSession = import ./report-agent-session.nix;
  herdrCacheToken = import ./herdr-cache-token.nix;
  codexAutoTitle = import ./codex-auto-title.nix;
  herdr = import ./herdr.nix {inherit inputs;};
  unocssLanguageServer = import ./unocss-language-server.nix {inherit inputs;};
in
  binaryReleases // npmPackages // buildFixes // sourceBuilds // ccStatusline // agentGuard // reportAgentSession // herdrCacheToken // codexAutoTitle // herdr // unocssLanguageServer
