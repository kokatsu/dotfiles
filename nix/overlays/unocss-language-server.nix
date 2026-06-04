# unocss-language-server flake の package を dotfiles 側 pkgs に注入
{inputs}: {
  unocss-language-server = _final: prev: {
    unocss-language-server = inputs.unocss-language-server.packages.${prev.stdenv.hostPlatform.system}.default;
  };
}
