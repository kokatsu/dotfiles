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
  "^com\\.apple\\.Terminal$",
  "^com\\.googlecode\\.iterm2$",
]);

// Chrome bundle identifier
const chromeApp = ifApp("^com\\.google\\.Chrome$");

// Generate Command+key to Control+key mappings for terminal apps
// Since simple_modifications swaps Ctrl↔Cmd globally,
// we need to convert Command (physical Ctrl) back to Control in terminal apps
const keyList = [
  // Alphabet keys
  "a",
  "b",
  "c",
  "d",
  "e",
  "f",
  "g",
  "h",
  "i",
  "j",
  "k",
  "l",
  "m",
  "n",
  "o",
  "p",
  "q",
  "r",
  "s",
  "t",
  "u",
  "v",
  "w",
  "x",
  "y",
  "z",
  // Common special keys
  "spacebar",
  "return_or_enter",
  "escape",
  "delete_or_backspace",
  "tab",
  "open_bracket",
  "close_bracket",
  "backslash",
  "semicolon",
  "quote",
  "grave_accent_and_tilde",
  "comma",
  "period",
  "slash",
  "hyphen",
  "equal_sign",
  // Arrow keys
  "up_arrow",
  "down_arrow",
  "left_arrow",
  "right_arrow",
  // Number keys
  "1",
  "2",
  "3",
  "4",
  "5",
  "6",
  "7",
  "8",
  "9",
  "0",
] as const;

writeToProfile(
  "Default",
  [
    // Terminal apps: Convert Command+key to Control+key
    // This restores physical Ctrl behavior in terminal apps
    rule("Terminal: Command to Control (for CLI apps)", terminalApps)
      .manipulators([
        // Basic Command+key → Control+key
        ...keyList.map((key) => map(key, "command").to(key, "control")),
        // Command+Shift+key → Control+Shift+key
        ...keyList.map((key) =>
          map(key, ["command", "shift"]).to(key, ["control", "shift"])
        ),
      ]),

    // Chrome: Command+Tab to Control+Tab (tab switching)
    rule("Chrome: Command+Tab to Control+Tab", chromeApp).manipulators([
      map("tab", "command").to("tab", "control"),
      map("tab", ["command", "shift"]).to("tab", ["control", "shift"]),
    ]),

    // Disable Command+Tab app switcher globally
    rule("Disable Command+Tab app switcher").manipulators([
      map("tab", "command").toVar("__disabled__", 1),
      map("tab", ["command", "shift"]).toVar("__disabled__", 1),
    ]),

    // Option+Tab to Raycast Switch Windows
    rule("Option+Tab to Raycast Switch Windows").manipulators([
      map("tab", "option").to$(
        "open raycast://extensions/raycast/navigation/switch-windows",
      ),
    ]),
  ],
  {},
  {
    // Swap left_control and left_command using simple_modifications
    // This provides Cmd-like experience with physical Ctrl in non-terminal apps
    simple_modifications: [
      map("left_control").to("left_command"),
      map("left_command").to("left_control"),
    ],
  },
);
