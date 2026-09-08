using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using Windows.UI.Notifications;
using Windows.UI.Notifications.Management;

namespace SlackWatch;

/// <summary>
/// Windows の通知センターにある Slack のトーストを数え、WezTerm が読む status.json を書く。
///
/// このアセンブリは apphost (exe) を作らない。既存の dotnet をホストにして
/// `dotnet SlackWatch.dll &lt;mode&gt;` で起動し、実行ファイルを配置しない。
/// </summary>
internal static class Program
{
    /// Slack Desktop (Squirrel インストーラ) の AppUserModelId。
    /// 再インストールで変わりうるので環境変数で上書きできる
    private const string DefaultAppId = "com.squirrel.slack.slack";

    /// Windows がアプリごとに通知センターへ残す既定の上限。
    /// これに達したら実際の未読はもっと多い可能性がある
    private const int ActionCenterCap = 20;

    /// status.json の書き手を 1 つに限るための名前付き Mutex。
    /// 通知センターはセッション単位なので Local\ で足りる
    private const string InstanceMutexName = @"Local\slack-watch";

    /// 短命な once / clear どうしがロックを取り合ったときに待つ時間。
    /// 常駐の有無は待ち時間ではなく PID ファイルで判断する
    private static readonly TimeSpan WriterWait = TimeSpan.FromSeconds(30);

    private static readonly string AppId =
        Environment.GetEnvironmentVariable("SLACK_WATCH_APP_ID") ?? DefaultAppId;

    /// 通知を数え直す間隔 (秒)。読み手が「更新が止まった」と判断する境界を
    /// この値から導けるよう、status.json にも載せる
    private static readonly int PollInterval =
        int.TryParse(Environment.GetEnvironmentVariable("SLACK_WATCH_INTERVAL"), out var configured) && configured > 0
            ? configured
            : 30;

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
        WriteIndented = true,
    };

    private static int Main(string[] args)
    {
        // 既定はコンソールのコードページ (日本語環境なら CP932) になる。
        // 読み手は WSL の UTF-8 端末なので、通知タイトルもメッセージも化ける
        try
        {
            Console.OutputEncoding = Encoding.UTF8;
        }
        catch
        {
            // コンソールがない場合は無視してよい
        }

        var mode = args.Length > 0 ? args[0] : "watch";
        return mode switch
        {
            "watch" => Watch(),
            "once" => Once(),
            "clear" => Clear(),
            "running" => Running(),
            "probe" => Probe(),
            "titles" => Titles(),
            _ => Usage(mode),
        };
    }

    private static int Usage(string mode)
    {
        Console.Error.WriteLine($"unknown mode: {mode}");
        Console.Error.WriteLine("usage: dotnet SlackWatch.dll [watch|once|clear|running|probe|titles]");
        return 2;
    }

    // --- モード ---

    /// 常駐して定期的に status.json を更新し、clear.request を見つけたら通知を消す
    private static int Watch()
    {
        using var instance = TryAcquireWriter(TimeSpan.Zero);
        if (instance is null)
        {
            Console.Error.WriteLine("slack-watch: 既に常駐プロセスがあります");
            return 0;
        }

        // 管理コマンドが「常駐がいるか」を推測ではなく PID で判定できるようにする。
        // Windows は PID を使い回すので、起動時刻も添えて同一プロセスかを確かめられるようにする
        Directory.CreateDirectory(StatusDir);
        File.WriteAllText(DaemonPidFile, DaemonIdentity());

        // dotnet.exe はコンソールホストなので、常駐時はコンソールを手放す
        FreeConsole();

        // 初回はここで許可を確立する。以降の巡回は Collect が GetAccessStatus で確認する
        EnsureAccess();

        try
        {
            return Loop(TimeSpan.FromSeconds(PollInterval));
        }
        finally
        {
            // 落ちた場合は残るが、PID の生存確認で無効と分かる
            TryDelete(DaemonPidFile);
        }
    }

    private static int Loop(TimeSpan interval)
    {
        // 重いのは通知の取得だけなので、そこだけ interval を空ける。
        // 要求マーカーはファイル監視で拾う。定期的に起きて存在確認するより待機中の CPU が減り、
        // 反応も速い。イベントを取りこぼしても interval ごとの巡回で拾い直す
        using var signal = new AutoResetEvent(false);
        using var requests = new FileSystemWatcher(StatusDir, "*.request") { EnableRaisingEvents = true };
        requests.Created += (_, _) => signal.Set();
        requests.Changed += (_, _) => signal.Set();
        requests.Renamed += (_, _) => signal.Set();

        var nextPoll = DateTime.UtcNow;

        while (true)
        {
            try
            {
                if (ConsumeMarker(StopRequestFile))
                {
                    return 0;
                }

                if (HandleClearRequest() || DateTime.UtcNow >= nextPoll)
                {
                    WriteStatus(Collect());
                    nextPoll = DateTime.UtcNow + interval;
                }
            }
            catch (Exception ex)
            {
                // 失敗しても常駐は続ける。次の巡回まで待つのは、休みなく再試行しないため
                nextPoll = DateTime.UtcNow + interval;
                try
                {
                    WriteStatus(new Status(0, false, null, Now(), PollInterval, Describe(ex)));
                }
                catch
                {
                    // 握りつぶす
                }
            }

            var wait = nextPoll - DateTime.UtcNow;
            if (wait > TimeSpan.Zero)
            {
                signal.WaitOne(wait);
            }
        }
    }

    /// 1 回だけ収集して status.json を書く
    private static int Once()
    {
        if (IsDaemonRunning())
        {
            Console.Error.WriteLine("slack-watch: 常駐プロセスが status.json を更新中です");
            return 0;
        }

        using var instance = TryAcquireWriter(WriterWait);
        if (instance is null)
        {
            Console.Error.WriteLine("slack-watch: 別のプロセスが status.json を更新中です");
            return 1;
        }

        EnsureAccess();

        try
        {
            var status = Collect();
            WriteStatus(status);
            Console.WriteLine($"unread={status.UnreadCount} capped={status.Capped} -> {StatusFile}");
            return 0;
        }
        catch (Exception ex)
        {
            WriteStatus(new Status(0, false, null, Now(), PollInterval, Describe(ex)));
            Console.Error.WriteLine(Describe(ex));
            return 1;
        }
    }

    /// 通知センターから Slack のトーストを消して status.json を 0 にする
    private static int Clear()
    {
        // 常駐がいるならそれが唯一の書き手なので、要求だけ置いて任せる。
        // ロックが取れないだけの相手 (短命な once / clear) に委譲すると誰も処理しない
        if (IsDaemonRunning())
        {
            Directory.CreateDirectory(StatusDir);
            WriteMarker(ClearRequestFile);
            Console.WriteLine("requested");
            return 0;
        }

        using var instance = TryAcquireWriter(WriterWait);
        if (instance is null)
        {
            Console.Error.WriteLine("slack-watch: 別のプロセスが status.json を更新中です");
            return 1;
        }

        EnsureAccess();

        // 未許可のまま消すと 0 件成功に見えてしまう
        if (!AccessAllowed())
        {
            Console.Error.WriteLine("slack-watch: 通知へのアクセスが許可されていません");
            return 1;
        }

        try
        {
            var removed = RemoveSlackNotifications();
            WriteStatus(Collect());
            Console.WriteLine($"removed={removed}");
            return 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine(Describe(ex));
            return 1;
        }
    }

    /// 常駐が生きていれば 0、いなければ 1。
    /// PID の使い回しを見分けるには保存した起動時刻との照合が要るので、
    /// シェル側で作り直さず判定をここに寄せる
    private static int Running() => IsDaemonRunning() ? 0 : 1;

    /// 動作確認用。本文は出さず、件数と binding の形だけを出す
    private static int Probe()
    {
        var listener = UserNotificationListener.Current;
        Console.WriteLine("accessStatus=" + Access(listener));

        var all = Toasts(listener);
        Console.WriteLine($"total={all.Count} cap={ActionCenterCap}");
        foreach (var group in all.GroupBy(n => TryAppId(n) ?? "<unknown>").OrderByDescending(g => g.Count()))
        {
            Console.WriteLine($"APP {group.Key} count={group.Count()}");
        }

        foreach (var n in all.Where(n => string.Equals(TryAppId(n), AppId, StringComparison.OrdinalIgnoreCase)))
        {
            var texts = TextsOf(n);
            var lengths = string.Join(",", texts.Select(t => t.Length));
            Console.WriteLine($"SLACK id={n.Id} created={n.CreationTime:s} elements={texts.Count} lengths=[{lengths}]");
        }

        Console.WriteLine("--- NotificationChanged を 20 秒購読 ---");
        var fired = 0;
        try
        {
            listener.NotificationChanged += (_, _) => Interlocked.Increment(ref fired);
            Thread.Sleep(TimeSpan.FromSeconds(20));
            Console.WriteLine($"subscribe=ok events={fired}");
        }
        catch (Exception ex)
        {
            Console.WriteLine("subscribe=failed " + Describe(ex));
        }

        return 0;
    }

    /// Slack トーストの 1 行目 (タイトル) だけを出す。
    /// メンション / DM / 通常投稿をタイトルで判別できるかを目視するためのもの
    private static int Titles()
    {
        var slack = SlackToasts(UserNotificationListener.Current);

        // 無出力だと「壊れている」のか「クリア済みで残っていない」のか分からない
        if (slack.Count == 0)
        {
            Console.Error.WriteLine("slack-watch: 通知センターに Slack の通知がありません");
            return 0;
        }

        foreach (var n in slack)
        {
            var texts = TextsOf(n);
            Console.WriteLine($"{n.CreationTime:HH:mm}  {(texts.Count > 0 ? texts[0] : "<no text>")}");
        }

        return 0;
    }

    // --- 収集 ---

    private static Status Collect()
    {
        var listener = UserNotificationListener.Current;

        var access = listener.GetAccessStatus();
        if (access != UserNotificationListenerAccessStatus.Allowed)
        {
            return new Status(0, false, null, Now(), PollInterval, $"notification access: {access}");
        }

        var slack = SlackToasts(listener);
        var latest = slack.Count > 0 ? slack.Max(n => n.CreationTime) : (DateTimeOffset?)null;

        return new Status(
            UnreadCount: slack.Count,
            Capped: slack.Count >= ActionCenterCap,
            LatestAt: latest?.ToUnixTimeSeconds(),
            LastUpdated: Now(),
            PollInterval: PollInterval,
            Error: null);
    }

    /// notAfter を渡すと、それより後に届いた通知は残す
    private static int RemoveSlackNotifications(DateTimeOffset? notAfter = null)
    {
        var listener = UserNotificationListener.Current;
        var removed = 0;
        foreach (var n in SlackToasts(listener).Where(n => notAfter is null || n.CreationTime <= notAfter))
        {
            listener.RemoveNotification(n.Id);
            removed++;
        }

        return removed;
    }

    private static IReadOnlyList<UserNotification> Toasts(UserNotificationListener listener) =>
        listener.GetNotificationsAsync(NotificationKinds.Toast).AsTask().GetAwaiter().GetResult();

    /// 通知 ID から「Slack のものか」を覚えておく。
    /// AppInfo の解決はアプリ情報の問い合わせを伴い、毎巡回で全通知分やると
    /// 常駐の CPU 時間の大半を占める。ID と発信元アプリの対応は変わらないので使い回せる
    private static Dictionary<uint, bool> slackByNotificationId = [];

    private static List<UserNotification> SlackToasts(UserNotificationListener listener)
    {
        var all = Toasts(listener);
        var seen = new Dictionary<uint, bool>(all.Count);
        var slack = new List<UserNotification>();

        foreach (var n in all)
        {
            if (!slackByNotificationId.TryGetValue(n.Id, out var isSlack))
            {
                var appId = TryAppId(n);
                if (appId is null)
                {
                    // 解決できなかったものは覚えない。false として覚えると、
                    // その通知が消えるまで数え直しもクリアも対象外になり続ける
                    continue;
                }

                isSlack = string.Equals(appId, AppId, StringComparison.OrdinalIgnoreCase);
            }

            seen[n.Id] = isSlack;
            if (isSlack)
            {
                slack.Add(n);
            }
        }

        // 通知センターから消えた分は覚えておかない
        slackByNotificationId = seen;
        return slack;
    }

    private static string Access(UserNotificationListener listener) =>
        listener.RequestAccessAsync().AsTask().GetAwaiter().GetResult().ToString();

    /// 許可が取り消されると、通知の取得は例外ではなく空リストになりうる。
    /// 「0 件取れた」と「取れなかった」を取り違えないよう、消す前と数える前に必ず見る
    private static bool AccessAllowed() =>
        UserNotificationListener.Current.GetAccessStatus() == UserNotificationListenerAccessStatus.Allowed;

    /// 通知へのアクセスを確立する。失敗しても続行し、状態は Collect が status.json に載せる
    private static void EnsureAccess()
    {
        try
        {
            Access(UserNotificationListener.Current);
        }
        catch
        {
            // 握りつぶす
        }
    }

    /// 解決できなければ null。null は「Slack ではない」ではなく「まだ分からない」
    private static string? TryAppId(UserNotification n)
    {
        try
        {
            return n.AppInfo?.AppUserModelId;
        }
        catch
        {
            // アンインストール済みアプリの通知などは AppInfo の解決に失敗する
            return null;
        }
    }

    private static IReadOnlyList<string> TextsOf(UserNotification n)
    {
        var binding = n.Notification.Visual.GetBinding(KnownNotificationBindings.ToastGeneric);
        if (binding is null)
        {
            return [];
        }

        return binding.GetTextElements().Select(t => t.Text ?? string.Empty).ToList();
    }

    // --- 出力 ---

    private static string StatusDir =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".cache", "slack-watch");

    private static string StatusFile => Path.Combine(StatusDir, "status.json");

    private static string ClearRequestFile => Path.Combine(StatusDir, "clear.request");

    private static string StopRequestFile => Path.Combine(StatusDir, "stop.request");

    /// 常駐が自分の PID を書く。管理コマンドと clear の委譲判断に使う
    private static string DaemonPidFile => Path.Combine(StatusDir, "daemon.pid");

    /// "<PID>:<起動時刻>"。異常終了で PID ファイルが残り、その PID を別プロセスが
    /// 拾った場合に、それを常駐と取り違えないための識別子
    private static string DaemonIdentity()
    {
        using var self = Process.GetCurrentProcess();
        return $"{Environment.ProcessId}:{self.StartTime.ToFileTimeUtc()}";
    }

    /// 常駐が生きているか。PID が生きているだけでは足りず、起動時刻まで一致する必要がある
    private static bool IsDaemonRunning()
    {
        if (!File.Exists(DaemonPidFile))
        {
            return false;
        }

        var parts = File.ReadAllText(DaemonPidFile).Trim().Split(':');
        if (parts.Length != 2 || !int.TryParse(parts[0], out var pid) || !long.TryParse(parts[1], out var startedAt))
        {
            return false;
        }

        try
        {
            using var process = Process.GetProcessById(pid);
            return !process.HasExited && process.StartTime.ToFileTimeUtc() == startedAt;
        }
        catch (ArgumentException)
        {
            // 既に終了している
            return false;
        }
        catch (InvalidOperationException)
        {
            // 確認中に終了した
            return false;
        }
    }

    private static void TryDelete(string path)
    {
        try
        {
            File.Delete(path);
        }
        catch
        {
            // 消せなくても続行する
        }
    }

    /// WezTerm のキーバインドや bin/slack-watch が置くマーカーを消費する。
    /// dotnet ホスト経由で起動するため PID を辿りにくく、停止もマーカーで行う
    private static bool ConsumeMarker(string path)
    {
        if (!File.Exists(path))
        {
            return false;
        }

        File.Delete(path);
        return true;
    }

    /// クリア要求を処理する。
    ///
    /// 要求は rename で自分のものにしてから処理する。時刻を比べて消す方式だと、
    /// 比較と削除の間に置かれた新しい要求を巻き込む。rename なら要求の受け取りが不可分になり、
    /// 処理中に置かれた要求は次の巡回に残る。失敗しても作業ファイルが残るので再試行される。
    /// 常駐はファイル監視で即座に反応する。書いている最中のファイルを消されないよう、
    /// 別名で作ってから rename で置く
    private static void WriteMarker(string path)
    {
        var temp = path + ".tmp";
        File.WriteAllText(temp, string.Empty);
        File.Move(temp, path, overwrite: true);
    }

    /// 処理したら真。呼び出し側はそのとき status.json を即座に更新する
    private static bool HandleClearRequest()
    {
        var work = ClearRequestFile + ".processing";

        if (!File.Exists(work))
        {
            if (!File.Exists(ClearRequestFile))
            {
                return false;
            }

            File.Move(ClearRequestFile, work, overwrite: true);
        }

        // 未許可のまま 0 件消せたことにして要求を捨てない。要求は次の巡回に残る
        if (!AccessAllowed())
        {
            return false;
        }

        // 要求より後に届いた通知は消さない。常駐が止まっている間に置かれた要求でも、
        // 消えるのは要求した時点で見えていた分だけになる
        RemoveSlackNotifications(new DateTimeOffset(File.GetLastWriteTimeUtc(work), TimeSpan.Zero));
        File.Delete(work);
        return true;
    }

    /// status.json の書き手になれたら Mutex を返す。既に常駐がいれば null
    private static Mutex? TryAcquireWriter(TimeSpan timeout)
    {
        var mutex = new Mutex(initiallyOwned: false, InstanceMutexName);
        try
        {
            if (mutex.WaitOne(timeout))
            {
                return mutex;
            }
        }
        catch (AbandonedMutexException)
        {
            // 前の常駐が解放せずに終了しただけ。所有権はこちらに移っている
            return mutex;
        }

        mutex.Dispose();
        return null;
    }

    private static void WriteStatus(Status status)
    {
        Directory.CreateDirectory(StatusDir);

        // 読み手 (WezTerm) が半端な JSON を読まないように、一時ファイル経由で置き換える。
        // 名前にプロセス ID を入れて、別プロセスの一時ファイルと衝突させない
        var temp = $"{StatusFile}.{Environment.ProcessId}.tmp";
        File.WriteAllText(temp, JsonSerializer.Serialize(status, JsonOptions));
        File.Move(temp, StatusFile, overwrite: true);
    }

    private static long Now() => DateTimeOffset.UtcNow.ToUnixTimeSeconds();

    private static string Describe(Exception ex) => $"{ex.GetType().Name}: {ex.Message}";

    private sealed record Status(
        int UnreadCount,
        bool Capped,
        long? LatestAt,
        long LastUpdated,
        int PollInterval,
        string? Error);

    // LibraryImport は AllowUnsafeBlocks を要求するので DllImport を使う
    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool FreeConsole();
}
