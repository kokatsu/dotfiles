{config, ...}: {
  programs.ghostty = {
    enable = true;
    # macOS は Homebrew、WSL はホスト側のターミナルを使う。ここでは設定だけを管理。
    package = null;
    systemd.enable = false;
    enableBashIntegration = false;
    enableFishIntegration = false;
    enableZshIntegration = false;
    settings = {
      font-family = [
        "UDEV Gothic 35NFLG"
        "Firge35Nerd Console"
        "HackGen35 Console NF"
      ];
      font-size = 14;
      adjust-cell-height = "10%";
      cursor-style = "bar";
      cursor-style-blink = true;
      background-opacity = 0.75;
      background-image-opacity = 0.3;
      window-padding-x = 20;
      window-padding-y = 5;
      window-padding-balance = true;
      window-theme = "ghostty";
      macos-titlebar-style = "tabs";
      macos-window-buttons = "hidden";
      window-save-state = "always";
      window-inherit-working-directory = true;
      window-inherit-font-size = true;
      confirm-close-surface = false;
      quick-terminal-position = "top";
      quick-terminal-screen = "mouse";
      quick-terminal-animation-duration = 0.1;
      shell-integration = "detect";
      shell-integration-features = "cursor,sudo,title";
      scrollback-limit = 10000;
      mouse-hide-while-typing = true;
      copy-on-select = true;
      # 残った選択が次の Ctrl+c もコピーに変え、SIGINT が届かなくなる
      selection-clear-on-copy = true;
      clipboard-trim-trailing-spaces = true;
      clipboard-paste-protection = true;
      # WezTerm の unified_keys (.config/wezterm/keybinds.lua) に合わせる。Karabiner は
      # ターミナルで物理 Ctrl を Ctrl のまま届け、物理 Cmd も Ctrl に変えるので、super は
      # 英数字キーでは届かない。ペインとタブは herdr が持つので、Ctrl 単独のキーは
      # シェルとエディタに残す。
      keybind = [
        # 選択があればコピーし、なければ Ctrl+c をそのまま送る
        "performable:ctrl+c=copy_to_clipboard"
        "ctrl+shift+c=text:\\x03"
        "ctrl+v=paste_from_clipboard"
        "ctrl+shift+n=new_window"
        "ctrl+left=text:\\x1bb"
        "ctrl+right=text:\\x1bf"
        "ctrl+backspace=text:\\x17"
        "ctrl+semicolon=increase_font_size:1"
        "ctrl+minus=decrease_font_size:1"
        "ctrl+shift+semicolon=reset_font_size"
        # 検索欄を開き、選択があればそれを検索語にする
        "ctrl+shift+f=start_search"
        "chain=search_selection"
        "ctrl+shift+p=toggle_command_palette"
        "ctrl+shift+l=inspector:toggle"
        "global:ctrl+grave_accent=toggle_quick_terminal"
      ];
      # Ghostty に同梱されたテーマのファイル名 (例: Catppuccin Mocha)。
      theme = (config.catppuccinLib.flavorNames config.catppuccin.flavor).spaced;
    };
  };
}
