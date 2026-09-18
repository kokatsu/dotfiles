# ime-watch

WezTerm の日本語 IME を、マーカーファイル 1 つで閉じるための常駐リスナー。herdr の prefix (`Ctrl + Space`) を押したときに WezTerm が要求を置く。

## なぜ常駐が要るのか

herdr は WSL 側で動くので、`experimental.switch_ascii_input_source_in_prefix` は Windows の IME に届かない。代わりに Windows 側で動く WezTerm が肩代わりするが、WezTerm から IME を閉じるには次の制約がある。

- WezTerm の設定 Lua に Windows の IME を操作する API はない
- `wsl.exe` を挟む経路は約 0.2 秒かかり、prefix の次のキーがその内側で IME に食われる

WezTerm はマーカーファイルを 1 つ置くだけにして、IME の操作は常駐に任せる。マーカーの作成はプロセス起動を伴わないので、WezTerm 側の費用は無視できる。

```text
WezTerm (Ctrl+Space) --(off.request)--> %USERPROFILE%\.cache\ime-watch\
                                                |
                                    FileSystemWatcher (このアプリ)
                                                |
                          ImmGetDefaultIMEWnd + WM_IME_CONTROL
```

## 待ち合わせない理由

WezTerm 側は IME が閉じるのを待たずに prefix を送る。callback をビジーループで止めても、止めている間に押されたキーは IME 変換を免れないことを実機で確認したため、待っても後続キーの保護にはならない。

その代わりレースは残る。マーカーを置いてから IME が閉じるまでの間に次のキーが届けば、そのキーは変換される。`status.json` の `last_latency_ms` と `max_latency_ms` がその窓の実測値になる。

## `status.json`

```json
{
  "handled": 42,
  "failed": 0,
  "last_latency_ms": 2.913,
  "max_latency_ms": 11.204,
  "last_failure": null,
  "last_updated": 1789740000
}
```

`handled` は処理した要求の数、`failed` はそのうち IME を閉じられなかった数。`last_failure` は直近の失敗理由で、その後に成功しても消えない。

常駐は起動時にゼロの状態を先に書く。前の常駐が残したファイルを今の常駐のものと取り違えないため。

レイテンシは IME を閉じられた要求だけを、要求ファイルの書き込み時刻から閉じ終えるまでで測る。捨てた要求や前景が違って何もしなかった要求を混ぜると、レースの窓を表さなくなる。`DateTime.UtcNow` は分解能がおよそ 15 ミリ秒あって粗いため、`GetSystemTimePreciseAsFileTime` を使う。

## exe を作らない理由

`UseAppHost=false` を指定し、`ImeWatch.exe` を生成しない。起動には既存の `dotnet.exe` をホストとして使い、実行ファイルを 1 つも配置しない。

```console
"C:\Program Files\dotnet\dotnet.exe" "...\bin\ImeWatch.dll" watch
```

自動起動も同じ方針で、`HKCU\Software\Microsoft\Windows\CurrentVersion\Run` に `dotnet.exe` を直接指す値を書く。

## セットアップ

WSL 側から次を実行する。

```bash
ime-watch install   # Windows 側へ publish し、ログオン時に起動する設定を入れる
ime-watch start     # 起動
ime-watch off       # 常駐を介さず IME を閉じてみる (動作確認)
ime-watch status    # status.json を表示する
```

WezTerm 側のキーバインドは `.config/wezterm/*.lua` を Windows へコピーしてから有効になるので、初回は `home-manager switch --flake . --impure` も実行する。

## モード

| コマンド | 内容 |
| --- | --- |
| `watch` | 常駐。`off.request` をファイル監視で待つ |
| `off` | その場で前景ウィンドウの IME を閉じる |
| `running` | 常駐が生きていれば終了コード 0、いなければ 1 |

常駐は名前付き Mutex (`Local\ime-watch`) で 1 プロセスに限っている。2 つ目の `watch` はその場で終了する。

生死の判断はロックが取れないことではなく `daemon.pid` の PID が生きているかで行う。Windows は PID を使い回すので、起動時刻まで一致することを確かめる。

## 制約

- 前景ウィンドウが `wezterm-gui` でなければ何もしない。マーカーを置いてから常駐が動くまでの間に Alt+Tab されると、無関係なアプリの IME を閉じてしまうため
- IME を閉じる経路は IMM32 の `WM_IME_CONTROL` / `IMC_SETOPENSTATUS`。Windows 11 の Microsoft IME でも効くことは実機で確認済みだが、API の戻り値ではなく `IMC_GETOPENSTATUS` を読み直して成否を決めている
- 既定 IME ウィンドウは前景アプリのスレッドが持つので、送信はそのスレッドがメッセージを処理するまで返らない。相手がハングしたときに常駐まで止まらないよう `SendMessageTimeout` を使う
- prefix モードの終了を WezTerm は検知できないので、IME は閉じたまま残る
- 常駐が止まっていてもマーカーが残るだけで、prefix そのものは herdr に届く。止まっている間に積まれた要求は、起動時に捨てる (要求時の前景と起動時の前景は別物のため)
- 掃除に失敗して古い要求が残ることに備え、1 秒より古い要求は IME に当てずに `stale request` として捨てる
- prefix を別のキーに変えるときは `nix/home/programs/herdr.nix` の `keys.prefix` と `.config/wezterm/keybinds.lua` のバインドを揃える。片方だけ変えても要求が出なくなるだけで、エラーにはならない
- Mutex は `Local\` なので Windows のセッション単位
