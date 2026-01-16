# ansi-preview.yazi

Preview files containing ANSI escape codes with colors rendered in Yazi.

![preview](.github/preview.png)

## Installation

```sh
ya pkg add kokatsu/ansi-preview
```

Or manually clone to your plugins directory:

```sh
git clone https://github.com/kokatsu/ansi-preview.yazi.git ~/.config/yazi/plugins/ansi-preview.yazi
```

## Setup

Add the following to your `~/.config/yazi/yazi.toml`:

```toml
[[plugin.prepend_previewers]]
url = "*.ans"
run = "ansi-preview"

[[plugin.prepend_previewers]]
url = "*.ansi"
run = "ansi-preview"
```

You can add more file extensions as needed:

```toml
[[plugin.prepend_previewers]]
url = "*.log"
run = "ansi-preview"
```

## How It Works

This plugin uses `ui.Text.parse()` to parse ANSI escape sequences and render them with proper colors and styles in Yazi's preview pane.

Supported ANSI features:
- Foreground/background colors (standard and 256-color)
- Bold, italic, underline, strikethrough
- Reverse video

## License

This plugin is MIT-licensed. For more information check the [LICENSE](LICENSE) file.
