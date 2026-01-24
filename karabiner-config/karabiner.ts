/**
 * Karabiner-Elements configuration
 * @see https://github.com/evan-liu/karabiner.ts
 *
 * Build: deno run --allow-env --allow-read --allow-write karabiner.ts
 */
import { ifApp, map, rule, writeToProfile } from "karabiner.ts";

// Terminal applications bundle identifiers
const terminalApps = ifApp([
  "^com\\.github\\.wez\\.wezterm$",
  "^com\\.mitchellh\\.ghostty$",
]);

writeToProfile("Default", [
  // Swap left_control and left_command
  rule("Swap Control and Command").manipulators([
    map("left_control").to("left_command"),
    map("left_command").to("left_control"),
  ]),

  // Terminal apps: Command+Tab to Control+Tab (for tab switching in terminal multiplexers)
  rule("Terminal: Command+Tab to Control+Tab", terminalApps).manipulators([
    map("tab", "command").to("tab", "control"),
    map("tab", ["command", "shift"]).to("tab", ["control", "shift"]),
  ]),

  // Option+Tab to Raycast Switch Windows
  rule("Option+Tab to Raycast Switch Windows").manipulators([
    map("tab", "option").to$(
      "open raycast://extensions/raycast/navigation/switch-windows",
    ),
  ]),
]);
