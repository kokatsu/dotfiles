# slack-watch

Windows の通知センターに残っている Slack のトースト通知を数え、WezTerm のステータスバーに未読バッジとして出すための常駐リスナー。

Slack API を使わず、Windows が保持している通知そのものを読む。トークンの発行も Slack App の作成も要らない。

## 仕組み

```text
Slack Desktop --(トースト通知)--> Windows 通知センター
                                        |
                    UserNotificationListener (このアプリ)
                                        |
                  %USERPROFILE%\.cache\slack-watch\status.json
                                        |
                        WezTerm の update-status (format.lua)
```

`status.json` の形式:

```json
{
  "unread_count": 20,
  "capped": true,
  "latest_at": 1788854997,
  "last_updated": 1788855693,
  "poll_interval": 30,
  "error": null
}
```

`capped` は通知センターのアプリごとの保持上限 (既定 20 件) に達したことを表す。バッジは `20+` のように表示される。

`error` が入っているとき、WezTerm は件数ではなく `!` を出す。`last_updated` が古くなったときは `?` を出す。その境界は `poll_interval` の 3 倍 (最低 60 秒) なので、間隔を延ばしても誤って停止扱いにはならない。取得失敗とリスナー停止を「未読 0」と取り違えないための区別。

## exe を作らない理由

`UseAppHost=false` を指定し、`SlackWatch.exe` を生成しない。起動には既存の `dotnet.exe` をホストとして使い、実行ファイルを 1 つも配置しない。

```console
"C:\Program Files\dotnet\dotnet.exe" "...\bin\SlackWatch.dll" watch
```

自動起動も同じ方針で、`HKCU\Software\Microsoft\Windows\CurrentVersion\Run` に `dotnet.exe` を直接指す値を書く。`schtasks /SC ONLOGON` と違って管理者権限が要らず、スタートアップフォルダにスクリプトファイルを置く必要もない。

## セットアップ

WSL 側から次を実行する。

```bash
slack-watch install   # Windows 側へ publish し、ログオン時に起動するタスクを登録
slack-watch start     # 起動
slack-watch status    # status.json を表示して動作確認
```

WezTerm 側のバッジと `Alt + k` は `.config/wezterm/*.lua` を Windows へコピーしてから有効になるので、初回は `home-manager switch --flake . --impure` も実行する。

必要なのは .NET SDK (Windows 側) だけ。証明書も sparse package も管理者権限も要らない。

## 既読クリア

WezTerm から `Alt + k`。`%USERPROFILE%\.cache\slack-watch\clear.request` を置くと、リスナーが次の巡回で Slack のトーストを通知センターから削除する。

シェルからは `slack-watch clear`。

**通知センターからも消える**点に注意。Slack アプリ側の既読状態は変わらない (Windows の通知を消すだけで、Slack のメッセージは未読のまま残る)。

## モード

| コマンド | 内容 |
| --- | --- |
| `watch` | 常駐。既定 30 秒ごとに `status.json` を更新する。要求マーカーはファイル監視で拾うので即座に反応する |
| `once` | 1 回だけ収集して `status.json` を書く |
| `clear` | 通知センターから Slack のトーストを消す |
| `running` | 常駐が生きていれば終了コード 0、いなければ 1 |
| `probe` | 動作確認。件数と binding の形だけを出す (本文は出さない) |
| `titles` | Slack トーストのタイトル行だけを出す。メンションと通常投稿を判別できるかの確認用 |

`status.json` の書き手は名前付き Mutex (`Local\slack-watch`) で 1 プロセスに限っている。2 つ目の `watch` はその場で終了する。

常駐がいるかどうかは、ロックが取れないことではなく `daemon.pid` の PID が生きているかで判断する。ロックが取れないだけの相手 (短命な `once` や直接実行の `clear`) に要求を委譲すると、誰も処理しないまま残るため。常駐がいれば `once` は何もせず終了し、`clear` は要求マーカーを置いて任せる。いなければどちらもロックを取って自分で処理する。

`bin/slack-watch` の `start` / `stop` も同じ PID を見る。`stop` は加えて `status.json` の更新が止まったことも確認してから完了とする。

## 環境変数

| 変数 | 既定値 | 内容 |
| --- | --- | --- |
| `SLACK_WATCH_APP_ID` | `com.squirrel.slack.slack` | 対象の AppUserModelId。Slack の再インストールで変わったときに使う |
| `SLACK_WATCH_INTERVAL` | `30` | 通知を数え直す間隔 (秒) |

WSL の環境変数は、`WSLENV` に載せないと Windows 側のプロセスへ渡らない。`bin/slack-watch` はこの 2 つを載せてから起動する。ログオン時の自動起動は Windows が直接 `dotnet.exe` を起動するため WSL を経由せず、常に既定値で動く。恒久的に変えるなら Windows のユーザー環境変数に設定する。

## 制約

- 通知を数え直す処理は 1 回あたり 100 ms 前後の CPU を使う。待機中はファイル監視で寝ているのでほぼ 0 だが、`SLACK_WATCH_INTERVAL` を詰めるとその分だけ常時 CPU を消費する (30 秒で 1 コアの約 0.6%、10 秒で約 1.1%)
- 通知センターはアプリごとに既定 20 件しか保持しない。それを超えた分は数えられないので、`capped` が真のときは実際の未読がもっと多い
- `UserNotificationListener.NotificationChanged` は package identity のないプロセスでは購読できない (`COMException`)。そのためイベント駆動ではなくポーリングしている
- メンションと通常投稿の区別は通知の中身に依存する。アプリ名でしか絞り込んでいないので、メンションと DM だけを出したい場合は Slack 側の通知設定で絞る必要がある
- Mutex は `Local\` なので Windows のセッション単位。同じユーザーで複数セッションを使うと、それぞれが常駐を持てて同じ `status.json` を書く。単一セッション前提の設計
- `status.json` には通知本文を書かない。件数と時刻、それに失敗したときの例外メッセージだけを出す
- `titles` と `probe` は診断用で、実際の通知を扱う。`titles` はタイトルを標準出力に出し、`probe` は本文の文字数だけを出す
