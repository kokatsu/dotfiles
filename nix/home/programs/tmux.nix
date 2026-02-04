{pkgs, ...}: {
  programs.tmux = {
    enable = true;
    terminal = "tmux-256color";
    mouse = true;
    baseIndex = 1;
    historyLimit = 10000;
    escapeTime = 10;
    keyMode = "vi";

    plugins = with pkgs.tmuxPlugins; [
      {
        plugin = catppuccin;
        extraConfig = ''
          # Catppuccin theme options (must be set before plugin loads)
          set -g @catppuccin_flavor 'mocha'
          set -g @catppuccin_window_status_style 'rounded'
          set -g @catppuccin_window_number_color "#89b4fa"
          set -g @catppuccin_window_current_number_color "#89b4fa"
          set -g @catppuccin_pane_color "#89b4fa"
          set -g @catppuccin_pane_border_style "fg=#89b4fa"
          set -g @catppuccin_pane_active_border_style "fg=#89b4fa"
          set -g @catppuccin_session_color "#89b4fa"
        '';
      }
    ];

    extraConfig = ''
      # ==============================================================================
      # tmux configuration - Migrated from Zellij
      # ==============================================================================

      # ------------------------------------------------------------------------------
      # General Settings
      # ------------------------------------------------------------------------------

      # WezTermのOSCシーケンスをパススルーする
      set -g allow-passthrough on

      # True color support
      set -ga terminal-overrides ",xterm-256color:Tc"

      # Extended keys support (for Ctrl+Shift, Alt+Shift combinations)
      set -s extended-keys on
      set -as terminal-features 'xterm*:extkeys'

      # Start panes at 1, not 0 (windows handled by baseIndex)
      setw -g pane-base-index 1

      # Renumber windows when one is closed
      set -g renumber-windows on

      # Destroy session when last client detaches (e.g., closing WezTerm tab)
      set -g destroy-unattached on

      # Focus events (for vim autoread)
      set -g focus-events on

      # Status bar position
      set -g status-position bottom

      # ------------------------------------------------------------------------------
      # Key Bindings
      # ------------------------------------------------------------------------------

      # Prefix key: Ctrl+b (default)
      set -g prefix C-b

      # Reload config
      bind r source-file ~/.config/tmux/tmux.conf \; display "Config reloaded!"

      # ------------------------------------------------------------------------------
      # Pane Navigation (Alt + Arrow keys without prefix)
      # ------------------------------------------------------------------------------

      bind -n M-Left select-pane -L
      bind -n M-Down select-pane -D
      bind -n M-Up select-pane -U
      bind -n M-Right select-pane -R

      # ------------------------------------------------------------------------------
      # Pane Operations (WezTerm style, without prefix)
      # ------------------------------------------------------------------------------

      # Split panes (Ctrl+s for horizontal, Ctrl+Shift+s for vertical)
      # Note: Requires `stty -ixon` in shell config to disable flow control
      bind -n C-s split-window -h -c "#{pane_current_path}"
      bind -n C-S split-window -v -c "#{pane_current_path}"

      # Close pane (Alt+w)
      bind -n M-w kill-pane

      # Zoom pane (Ctrl+z)
      bind -n C-z resize-pane -Z

      # Rotate panes (Alt+Shift+l/r)
      bind -n M-L rotate-window -D
      bind -n M-R rotate-window -U

      # ------------------------------------------------------------------------------
      # Pane Resize (Alt + +/-/= without prefix)
      # Zellij: Alt +/- -> Resize
      # ------------------------------------------------------------------------------

      bind -n M-= resize-pane -U 2
      bind -n M-- resize-pane -D 2
      bind -n M-+ resize-pane -U 2

      # ------------------------------------------------------------------------------
      # Pane Resize (Alt + Shift + Arrow without prefix)
      # WezTerm Ctrl+Shift+Arrow -> tmux Alt+Shift+Arrow
      # ------------------------------------------------------------------------------

      bind -n M-S-Left resize-pane -L 2
      bind -n M-S-Right resize-pane -R 2
      bind -n M-S-Up resize-pane -U 2
      bind -n M-S-Down resize-pane -D 2

      # ------------------------------------------------------------------------------
      # New Pane (Alt + n without prefix)
      # Zellij: Alt n -> NewPane
      # ------------------------------------------------------------------------------

      bind -n M-n split-window -h -c "#{pane_current_path}"

      # ------------------------------------------------------------------------------
      # Window/Tab Navigation (Alt + i/o without prefix)
      # Zellij: Alt i/o -> MoveTab left/right
      # ------------------------------------------------------------------------------

      bind -n M-i swap-window -t -1 \; previous-window
      bind -n M-o swap-window -t +1 \; next-window

      # ------------------------------------------------------------------------------
      # Prefix Mode: Pane Operations (prefix + p -> pane mode)
      # Zellij: Ctrl p -> pane mode
      # ------------------------------------------------------------------------------

      # Split panes
      bind '"' split-window -v -c "#{pane_current_path}"  # Zellij: d (down)
      bind % split-window -h -c "#{pane_current_path}"    # Zellij: r (right)
      bind d split-window -v -c "#{pane_current_path}"    # Zellij style: d (down)
      bind v split-window -h -c "#{pane_current_path}"    # Alternative: v (vertical split = right)

      # Navigate panes with hjkl (after prefix)
      bind h select-pane -L
      bind j select-pane -D
      bind k select-pane -U
      bind l select-pane -R

      # Close pane
      bind x kill-pane  # Zellij: x -> CloseFocus

      # Zoom pane (fullscreen toggle)
      bind f resize-pane -Z  # Zellij: f -> ToggleFocusFullscreen
      bind z resize-pane -Z  # Alternative

      # Swap panes
      bind p select-pane -t :.+  # Zellij: p -> SwitchFocus

      # ------------------------------------------------------------------------------
      # Prefix Mode: Window/Tab Operations (prefix + t -> tab mode)
      # Zellij: Ctrl t -> tab mode
      # ------------------------------------------------------------------------------

      # New window
      bind c new-window -c "#{pane_current_path}"  # Zellij: n -> NewTab
      bind n new-window -c "#{pane_current_path}"  # Zellij style

      # Navigate windows
      bind -r C-h previous-window  # Zellij: h -> GoToPreviousTab
      bind -r C-l next-window      # Zellij: l -> GoToNextTab

      # Go to window by number (Zellij: 1-9 -> GoToTab)
      bind 1 select-window -t :1
      bind 2 select-window -t :2
      bind 3 select-window -t :3
      bind 4 select-window -t :4
      bind 5 select-window -t :5
      bind 6 select-window -t :6
      bind 7 select-window -t :7
      bind 8 select-window -t :8
      bind 9 select-window -t :9

      # Rename window
      bind , command-prompt -I "#W" "rename-window '%%'"  # Zellij: r -> TabNameInput

      # Close window
      bind X kill-window  # Zellij: x -> CloseTab (uppercase to avoid conflict with pane close)

      # Last window toggle
      bind Tab last-window  # Zellij: tab -> ToggleTab

      # ------------------------------------------------------------------------------
      # Prefix Mode: Resize Operations
      # Zellij: Ctrl n -> resize mode
      # ------------------------------------------------------------------------------

      bind -r H resize-pane -L 5  # Zellij: h -> Resize Increase left
      bind -r J resize-pane -D 5  # Zellij: j -> Resize Increase down
      bind -r K resize-pane -U 5  # Zellij: k -> Resize Increase up
      bind -r L resize-pane -R 5  # Zellij: l -> Resize Increase right

      # ------------------------------------------------------------------------------
      # Prefix Mode: Copy/Scroll Mode
      # Zellij: Ctrl s -> scroll mode
      # ------------------------------------------------------------------------------

      bind [ copy-mode  # Zellij: Ctrl s -> scroll mode
      bind s copy-mode  # Zellij style

      # Vi-style copy mode (keyMode handles mode-keys vi)
      bind -T copy-mode-vi v send-keys -X begin-selection
      bind -T copy-mode-vi y send-keys -X copy-selection-and-cancel
      bind -T copy-mode-vi Escape send-keys -X cancel

      # Scroll with j/k in copy mode
      bind -T copy-mode-vi j send-keys -X cursor-down
      bind -T copy-mode-vi k send-keys -X cursor-up
      bind -T copy-mode-vi d send-keys -X halfpage-down  # Zellij: d
      bind -T copy-mode-vi u send-keys -X halfpage-up    # Zellij: u
      bind -T copy-mode-vi C-f send-keys -X page-down    # Zellij: Ctrl f
      bind -T copy-mode-vi C-b send-keys -X page-up      # Zellij: Ctrl b

      # Search in copy mode
      bind -T copy-mode-vi / command-prompt -p "(search down)" "send -X search-forward \"%%%\""
      bind -T copy-mode-vi ? command-prompt -p "(search up)" "send -X search-backward \"%%%\""
      bind -T copy-mode-vi n send-keys -X search-again
      bind -T copy-mode-vi N send-keys -X search-reverse

      # ------------------------------------------------------------------------------
      # Session Operations
      # Zellij: Ctrl o -> session mode
      # ------------------------------------------------------------------------------

      bind D detach-client  # Zellij: d -> Detach
      bind w choose-tree -Zs  # Zellij: w -> session-manager

      # ------------------------------------------------------------------------------
      # Layouts (Alt + ; / ' / 3 / \ without prefix)
      # Zellij custom layouts
      # ------------------------------------------------------------------------------

      # Layout: left | right-top/right-bottom (Alt+;)
      bind -n 'M-;' split-window -h -c "#{pane_current_path}" \; split-window -v -c "#{pane_current_path}" \; select-pane -L

      # Layout: top / bottom-left|bottom-right (Alt+')
      bind -n "M-'" split-window -v -c "#{pane_current_path}" \; split-window -h -c "#{pane_current_path}" \; select-pane -U

      # Layout: 3 columns (Alt+3)
      bind -n M-3 split-window -h -c "#{pane_current_path}" \; split-window -h -c "#{pane_current_path}" \; select-layout even-horizontal

      # Select layout (Alt+\)
      bind -n 'M-\' choose-tree -Zw

      # Preset layouts with prefix + Space
      bind Space next-layout  # Cycle through layouts

      # ------------------------------------------------------------------------------
      # Claude Code: Prompt Edit (Alt+e)
      # Zellij: Alt e -> floating neovim for prompt editing
      # ------------------------------------------------------------------------------

      bind -n M-e display-popup -E -w 80% -h 80% "$XDG_CONFIG_HOME/tmux/scripts/claude-prompt-edit.sh"

      # ------------------------------------------------------------------------------
      # Appearance Overrides (after catppuccin loads)
      # ------------------------------------------------------------------------------

      # Override pane border colors (both blue)
      set -g pane-border-style "fg=#89b4fa"
      set -g pane-active-border-style "fg=#89b4fa"

      # Override status line colors (all blue instead of green)
      set -g status-style "bg=#1e1e2e,fg=#cdd6f4"
      set -g status-left "#[fg=#1e1e2e,bg=#89b4fa,bold] #S #[fg=#89b4fa,bg=#1e1e2e]"
      set -g status-left-length 100
      set -g status-right "#[fg=#89b4fa,bg=#1e1e2e]#[fg=#1e1e2e,bg=#89b4fa] %H:%M "
      set -g status-right-length 100
      set -g window-status-format "#[fg=#cdd6f4,bg=#1e1e2e] #W "
      set -g window-status-current-format "#[fg=#1e1e2e,bg=#89b4fa,bold] #W #[fg=#89b4fa,bg=#1e1e2e]"
      set -g window-status-separator ""
    '';
  };

  # Script for Claude Code prompt editing
  home.file.".config/tmux/scripts/claude-prompt-edit.sh" = {
    source = ../../../.config/tmux/scripts/claude-prompt-edit.sh;
    executable = true;
  };
}
