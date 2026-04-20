# Karabiner-Elements Configuration

[karabiner.ts](https://github.com/evan-liu/karabiner.ts) を使用した
Karabiner-Elements の設定管理。

## 使い方

`karabiner.ts` を編集したら `home-manager switch` (macOS なら
`darwin-rebuild switch`) で `~/.config/karabiner/karabiner.json`
に自動反映される。 activation script が deno 実行と初回スタブ作成を担当する
([nix/home/activation.nix](../nix/home/activation.nix) の
`buildKarabinerConfig`)。

## ドライラン

適用せずに生成 JSON を確認したい場合:

```bash
deno task dry-run
```

## 設定内容

| ルール                               | 説明                                         |
| ------------------------------------ | -------------------------------------------- |
| Swap Control and Command             | 左Control ↔ 左Command を入れ替え             |
| Terminal: Command+Tab to Control+Tab | WezTerm/Ghostty で Command+Tab → Control+Tab |
| Option+Tab to Raycast Switch Windows | Option+Tab で Raycast のウィンドウ切り替え   |
