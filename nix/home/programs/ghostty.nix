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
        "HackGen35 Console"
      ];
      font-size = 14;
      adjust-cell-height = "10%";
      cursor-style = "bar";
      cursor-style-blink = true;
      background-opacity = 0.75;
      background-image-opacity = 0.3;
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
      clipboard-trim-trailing-spaces = true;
      clipboard-paste-protection = true;
      keybind = [
        "super+shift+c=copy_to_clipboard"
        "super+v=paste_from_clipboard"
        "ctrl+s=new_split:right"
        "ctrl+shift+s=new_split:down"
        "super+t=new_tab"
        "ctrl+t=new_tab"
        "super+shift+t=new_tab"
        "ctrl+tab=next_tab"
        "ctrl+shift+tab=previous_tab"
        "ctrl+left_bracket=move_tab:-1"
        "ctrl+right_bracket=move_tab:1"
        "ctrl+n=new_window"
        "super+f=toggle_maximize"
        "ctrl+f=toggle_maximize"
        "ctrl+z=toggle_split_zoom"
        "ctrl+w=close_surface"
        "super+alt+left=goto_split:left"
        "super+alt+right=goto_split:right"
        "super+alt+up=goto_split:top"
        "super+alt+down=goto_split:bottom"
        "ctrl+shift+left=resize_split:left,10"
        "ctrl+shift+right=resize_split:right,10"
        "ctrl+shift+up=resize_split:up,10"
        "ctrl+shift+down=resize_split:down,10"
        "ctrl+1=goto_tab:1"
        "ctrl+2=goto_tab:2"
        "ctrl+3=goto_tab:3"
        "ctrl+4=goto_tab:4"
        "ctrl+5=goto_tab:5"
        "ctrl+6=goto_tab:6"
        "ctrl+7=goto_tab:7"
        "ctrl+8=goto_tab:8"
        "ctrl+9=last_tab"
        "alt+left=text:\\x1b[1;3D"
        "alt+right=text:\\x1b[1;3C"
        "ctrl+left=text:\\x1b[1;5D"
        "ctrl+right=text:\\x1b[1;5C"
        "alt+backspace=text:\\x17"
        "ctrl+shift+l=inspector:toggle"
        "global:ctrl+grave_accent=toggle_quick_terminal"
        "super+shift+up=jump_to_prompt:-1"
        "super+shift+down=jump_to_prompt:1"
        "super+home=scroll_to_top"
        "super+end=scroll_to_bottom"
        "super+page_up=scroll_page_up"
        "super+page_down=scroll_page_down"
        "ctrl+shift+e=equalize_splits"
        "super+equal=increase_font_size:1"
        "super+minus=decrease_font_size:1"
        "super+zero=reset_font_size"
        "super+shift+s=write_screen_file:open"
        "super+alt+s=write_scrollback_file:open"
        "super+k=clear_screen"
      ];
      # Ghostty に同梱されたテーマのファイル名 (例: Catppuccin Mocha)。
      theme = (config.catppuccinLib.flavorNames config.catppuccin.flavor).spaced;
    };
  };
}
