using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;

namespace ImeWatch;

/// <summary>
/// WezTerm が置くマーカーを拾って、WezTerm の日本語 IME を閉じる常駐。
///
/// herdr は WSL 側で動くので Windows の IME に手が届かない。WSL 内の exe を
/// wsl.exe 越しに起こす経路は約 0.2 秒かかり、prefix の次のキーがその内側で食われる。
///
/// このアセンブリは apphost (exe) を作らない。既存の dotnet をホストにして
/// `dotnet ImeWatch.dll &lt;mode&gt;` で起動し、実行ファイルを配置しない。
/// </summary>
internal static class Program
{
    /// IME を閉じてよい前景ウィンドウの持ち主。これ以外が前景なら何もしない。
    /// マーカーを置いてから常駐が動くまでの間に Alt+Tab されると、無関係な
    /// アプリの IME を閉じてしまう
    private const string TargetProcess = "wezterm-gui";

    /// 常駐を 1 つに限るための名前付き Mutex。IME はセッション単位なので Local\ で足りる
    private const string InstanceMutexName = @"Local\ime-watch";

    /// 前景ウィンドウがハングしていても常駐まで巻き添えにしないための上限。
    /// IME は前景アプリのスレッドが処理するので、相手が止まると送信も返らない
    private const int SendTimeoutMs = 200;

    /// 取りこぼしたイベントを拾い直す間隔。待機中の CPU を使わないよう、
    /// 通常はファイル監視で起こされる
    private static readonly TimeSpan IdleWait = TimeSpan.FromSeconds(30);

    /// 実測のレイテンシは 10 ミリ秒前後なので通常の要求は引っかからず、これだけ
    /// 経っていれば守るべき次のキーはとうに処理されている
    private static readonly TimeSpan RequestMaxAge = TimeSpan.FromSeconds(1);

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
        WriteIndented = true,
    };

    private static int Main(string[] args)
    {
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
            "off" => Off(),
            "running" => Running(),
            _ => Usage(mode),
        };
    }

    private static int Usage(string mode)
    {
        Console.Error.WriteLine($"unknown mode: {mode}");
        Console.Error.WriteLine("usage: dotnet ImeWatch.dll [watch|off|running]");
        return 2;
    }

    // --- モード ---

    /// 常駐して off.request を待つ
    private static int Watch()
    {
        using var instance = TryAcquireInstance();
        if (instance is null)
        {
            Console.Error.WriteLine("ime-watch: 既に常駐プロセスがあります");
            return 0;
        }

        Directory.CreateDirectory(StateDir);

        // 管理コマンドが「常駐がいるか」を推測ではなく PID で判定できるようにする。
        // Windows は PID を使い回すので、起動時刻も添えて同一プロセスかを確かめられるようにする
        File.WriteAllText(DaemonPidFile, DaemonIdentity());

        // 常駐が止まっている間に積まれた要求は捨てる。後から IME を閉じても
        // その時点の前景は要求時とは限らない
        TryDelete(OffRequestFile);
        TryDelete(OffWorkFile);

        // 前の常駐が残した status.json を今の常駐のものと取り違えないよう、
        // 要求を 1 つも処理していない状態を先に書く
        var stats = new Stats();
        TryWriteStatus(stats);

        // dotnet.exe はコンソールホストなので、常駐時はコンソールを手放す
        FreeConsole();

        try
        {
            return Loop(stats);
        }
        finally
        {
            // 落ちた場合は残るが、PID の生存確認で無効と分かる
            TryDelete(DaemonPidFile);
        }
    }

    /// 常駐を介さずその場で IME を閉じる。動作確認と、常駐なしでの単発利用に使う
    private static int Off()
    {
        var result = CloseIme();
        Console.WriteLine(result.Error ?? "ok");
        return result.Ok ? 0 : 1;
    }

    private static int Running() => IsDaemonRunning() ? 0 : 1;

    // --- 常駐の本体 ---

    private static int Loop(Stats stats)
    {
        // マーカーはファイル監視で拾う。定期的に起きて存在確認するより待機中の CPU が減り、
        // 反応も速い。イベントを取りこぼしても IdleWait ごとの巡回で拾い直す
        using var signal = new AutoResetEvent(false);
        using var requests = new FileSystemWatcher(StateDir, "*.request") { EnableRaisingEvents = true };
        requests.Created += (_, _) => signal.Set();
        requests.Changed += (_, _) => signal.Set();
        requests.Renamed += (_, _) => signal.Set();

        while (true)
        {
            try
            {
                if (ConsumeMarker(StopRequestFile))
                {
                    return 0;
                }

                HandleOffRequest(stats);
            }
            catch (Exception ex)
            {
                // 失敗しても常駐は続ける。入力のたびに呼ばれるので、握りつぶさず状態に残す
                stats.Record(null, Describe(ex));
                TryWriteStatus(stats);
            }

            signal.WaitOne(IdleWait);
        }
    }

    /// 要求は rename で自分のものにしてから処理する。処理中に置かれた次の要求を
    /// 巻き込まないため。
    private static void HandleOffRequest(Stats stats)
    {
        if (!File.Exists(OffRequestFile))
        {
            return;
        }

        File.Move(OffRequestFile, OffWorkFile, overwrite: true);

        try
        {
            var requestedAt = File.GetLastWriteTimeUtc(OffWorkFile);

            // 要求は押した瞬間の前景に結び付く。File.Move や起動時の掃除が失敗して
            // 古い要求が残っても、後の操作に当てない。時計が戻ったときの負の経過も捨てる
            var age = PreciseUtcNow() - requestedAt;
            var stale = age < TimeSpan.Zero || age > RequestMaxAge;
            var result = stale ? new ImeResult(false, "stale request") : CloseIme();

            // prefix の次のキーが間に合うかはこの窓で決まる。捨てた要求の経過時間や、
            // 前景が違って何もしなかった時間を混ぜると窓を表さなくなる
            var latencyMs = result.Ok ? (PreciseUtcNow() - requestedAt).TotalMilliseconds : (double?)null;
            stats.Record(latencyMs, result.Error);
        }
        finally
        {
            TryDelete(OffWorkFile);
        }

        TryWriteStatus(stats);
    }

    // --- IME ---

    /// 前景ウィンドウの IME を閉じる。
    ///
    /// 既定 IME ウィンドウは前景アプリのスレッドが持つので、送信はそのスレッドが
    /// メッセージを処理するまで返らない。API の戻り値ではなく状態を読み直して成否を決める。
    private static ImeResult CloseIme()
    {
        var hwnd = GetForegroundWindow();
        if (hwnd == nint.Zero)
        {
            return new ImeResult(false, "no foreground window");
        }

        var owner = ForegroundProcessName(hwnd);
        if (!string.Equals(owner, TargetProcess, StringComparison.OrdinalIgnoreCase))
        {
            return new ImeResult(false, $"foreground is {owner ?? "unknown"}");
        }

        var ime = ImmGetDefaultIMEWnd(hwnd);
        if (ime == nint.Zero)
        {
            return new ImeResult(false, "no default IME window");
        }

        if (SendMessageTimeout(ime, WmImeControl, ImcSetOpenStatus, nint.Zero, SmtoAbortIfHung, SendTimeoutMs, out _) == nint.Zero)
        {
            return new ImeResult(false, "IMC_SETOPENSTATUS timed out or was not delivered");
        }

        if (SendMessageTimeout(ime, WmImeControl, ImcGetOpenStatus, nint.Zero, SmtoAbortIfHung, SendTimeoutMs, out var open) == nint.Zero)
        {
            return new ImeResult(false, "IMC_GETOPENSTATUS timed out or was not delivered");
        }

        return open == nint.Zero ? new ImeResult(true, null) : new ImeResult(false, "still open");
    }

    /// 解決できなければ null。null は「WezTerm ではない」ではなく「まだ分からない」。
    ///
    /// Process.GetProcessById はプロセス一覧の走査を伴い、IME を閉じる前に数ミリ秒を足す。
    /// ここはレースの窓の内側なので、ハンドルから直接引く。
    private static string? ForegroundProcessName(nint hwnd)
    {
        _ = GetWindowThreadProcessId(hwnd, out var pid);
        if (pid == 0)
        {
            return null;
        }

        var handle = OpenProcess(ProcessQueryLimitedInformation, false, pid);
        if (handle == nint.Zero)
        {
            return null;
        }

        try
        {
            var buffer = new StringBuilder(260);
            var size = buffer.Capacity;
            return QueryFullProcessImageName(handle, 0, buffer, ref size)
                ? Path.GetFileNameWithoutExtension(buffer.ToString())
                : null;
        }
        finally
        {
            CloseHandle(handle);
        }
    }

    // --- 状態 ---

    private static string StateDir =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".cache", "ime-watch");

    private static string StatusFile => Path.Combine(StateDir, "status.json");

    private static string OffRequestFile => Path.Combine(StateDir, "off.request");

    private static string OffWorkFile => Path.Combine(StateDir, "off.request.processing");

    private static string StopRequestFile => Path.Combine(StateDir, "stop.request");

    /// 常駐が自分の PID を書く。管理コマンドの生死判定に使う
    private static string DaemonPidFile => Path.Combine(StateDir, "daemon.pid");

    /// "&lt;PID&gt;:&lt;起動時刻&gt;"。異常終了で PID ファイルが残り、その PID を別プロセスが
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

    private static bool ConsumeMarker(string path)
    {
        if (!File.Exists(path))
        {
            return false;
        }

        File.Delete(path);
        return true;
    }

    /// 状態の書き出しは入力の成否と無関係なので、失敗しても IME 側の処理は続ける
    private static void TryWriteStatus(Stats stats)
    {
        try
        {
            // 読み手が半端な JSON を読まないように、一時ファイル経由で置き換える
            var temp = $"{StatusFile}.{Environment.ProcessId}.tmp";
            File.WriteAllText(temp, JsonSerializer.Serialize(stats.Snapshot(), JsonOptions));
            File.Move(temp, StatusFile, overwrite: true);
        }
        catch
        {
            // 握りつぶす
        }
    }

    /// DateTime.UtcNow の分解能は既定でおよそ 15 ミリ秒あり、ミリ秒規模の
    /// レイテンシ計測には粗すぎる
    private static DateTime PreciseUtcNow()
    {
        GetSystemTimePreciseAsFileTime(out var fileTime);
        return DateTime.FromFileTimeUtc(fileTime);
    }

    private static long Now() => DateTimeOffset.UtcNow.ToUnixTimeSeconds();

    private static string Describe(Exception ex) => $"{ex.GetType().Name}: {ex.Message}";

    /// Mutex を取れたら返す。既に常駐がいれば null
    private static Mutex? TryAcquireInstance()
    {
        var mutex = new Mutex(initiallyOwned: false, InstanceMutexName);
        try
        {
            if (mutex.WaitOne(TimeSpan.Zero))
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

    private sealed class Stats
    {
        private int handled;
        private int failed;
        private double lastMs;
        private double maxMs;
        private string? lastFailure;

        public void Record(double? latencyMs, string? error)
        {
            handled++;
            if (error is not null)
            {
                failed++;
                lastFailure = error;
            }

            if (latencyMs is { } ms)
            {
                lastMs = ms;
                maxMs = Math.Max(maxMs, ms);
            }
        }

        public Status Snapshot() => new(handled, failed, Round(lastMs), Round(maxMs), lastFailure, Now());

        private static double Round(double ms) => Math.Round(ms, 3);
    }

    private sealed record Status(
        int Handled,
        int Failed,
        double LastLatencyMs,
        double MaxLatencyMs,
        string? LastFailure,
        long LastUpdated);

    private readonly record struct ImeResult(bool Ok, string? Error);

    // --- Win32 ---

    private const uint WmImeControl = 0x0283;
    private static readonly nint ImcGetOpenStatus = 5;
    private static readonly nint ImcSetOpenStatus = 6;
    private const uint SmtoAbortIfHung = 0x0002;
    private const uint ProcessQueryLimitedInformation = 0x1000;

    // LibraryImport は AllowUnsafeBlocks を要求するので DllImport を使う
    [DllImport("user32.dll")]
    private static extern nint GetForegroundWindow();

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern nint OpenProcess(uint access, [MarshalAs(UnmanagedType.Bool)] bool inheritHandle, uint processId);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool QueryFullProcessImageName(nint process, uint flags, StringBuilder name, ref int size);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CloseHandle(nint handle);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(nint hwnd, out uint processId);

    [DllImport("imm32.dll")]
    private static extern nint ImmGetDefaultIMEWnd(nint hwnd);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern nint SendMessageTimeout(
        nint hwnd,
        uint message,
        nint wParam,
        nint lParam,
        uint flags,
        uint timeoutMs,
        out nint result);

    [DllImport("kernel32.dll")]
    private static extern void GetSystemTimePreciseAsFileTime(out long fileTime);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool FreeConsole();
}
