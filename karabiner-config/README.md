# Karabiner-Elements Configuration

[karabiner.ts](https://github.com/evan-liu/karabiner.ts) を使用した
Karabiner-Elements の設定管理。

## 使い方

`karabiner.ts` を編集したら `home-manager switch` で
`~/.config/karabiner/karabiner.json` に自動反映される (macOS も同じ)。
activation script が deno 実行と初回スタブ作成を担当する
([nix/home/programs/karabiner.nix](../nix/home/programs/karabiner.nix) の
`buildKarabinerConfig`)。

## ドライラン

適用せずに生成 JSON を確認したい場合:

```bash
just karabiner-dry-run
```

## 設定内容

| ルール                                      | 説明                                                                                                  |
| ------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| simple_modifications                        | 左 Control ↔ 左 Command を入れ替え (ターミナル以外で物理 Ctrl を Cmd として使う)                      |
| Terminal: Command to Control (for CLI apps) | ターミナルアプリでは英数字・記号・矢印・数字キーの Command+key と Command+Shift+key を Control に戻す |
| Chrome: Command+Tab to Control+Tab          | Chrome で Command+Tab / Command+Shift+Tab をタブ切り替え (Control+Tab) にする                         |
| Disable Command+Tab app switcher            | macOS の Command+Tab アプリ切り替えを無効化 (Raycast に置き換え)                                      |
| Option+Tab to Raycast Switch Windows        | Option+Tab で Raycast のウィンドウ切り替え                                                            |
