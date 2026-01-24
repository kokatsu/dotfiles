# Karabiner-Elements Configuration

[karabiner.ts](https://github.com/evan-liu/karabiner.ts) を使用した
Karabiner-Elements の設定管理。

## 使い方

```bash
# 設定をビルドして適用
deno task build

# ドライラン（JSON を確認）
deno task dry-run
```

## 初回セットアップ

`~/.config/karabiner/karabiner.json` が存在しない場合、以下を実行:

```bash
mkdir -p ~/.config/karabiner
cat > ~/.config/karabiner/karabiner.json << 'EOF'
{
  "global": {},
  "profiles": [{ "name": "Default", "selected": true }]
}
EOF
deno task build
```

## 設定内容

| ルール                               | 説明                                         |
| ------------------------------------ | -------------------------------------------- |
| Swap Control and Command             | 左Control ↔ 左Command を入れ替え             |
| Terminal: Command+Tab to Control+Tab | WezTerm/Ghostty で Command+Tab → Control+Tab |
| Option+Tab to Raycast Switch Windows | Option+Tab で Raycast のウィンドウ切り替え   |
