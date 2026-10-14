{inputs}: let
  binaryReleases = import ./binary-releases.nix;
  npmPackages = import ./npm-packages.nix;
  buildFixes = import ./build-fixes.nix;
  sourceBuilds = import ./source-builds.nix;
  neovimPlugins = import ./neovim-plugins.nix {inherit inputs;};
  zeno = import ./zeno.nix {inherit inputs;};
  karabinerConfig = import ./karabiner-config.nix;
  rubyLsp = import ./ruby-lsp.nix;
  ccStatusline = import ./cc-statusline.nix {inherit inputs;};
  agentHooks = import ./agent-hooks.nix;
  herdr = import ./herdr.nix {inherit inputs;};
  unocssLanguageServer = import ./unocss-language-server.nix {inherit inputs;};
in
  binaryReleases // npmPackages // buildFixes // sourceBuilds // neovimPlugins // zeno // karabinerConfig // rubyLsp // ccStatusline // agentHooks // herdr // unocssLanguageServer
