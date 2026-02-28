const std = @import("std");
const mem = std.mem;
const fs = std.fs;
const posix = std.posix;

// ============================================================
// Constants
// ============================================================

const color_red = "\x1b[0;31m";
const color_green = "\x1b[0;32m";
const color_yellow = "\x1b[1;33m";
const color_blue = "\x1b[0;34m";
const color_reset = "\x1b[0m";

const categories = [_][]const u8{
    "[\xe3\x82\xbf\xe3\x82\xb9\xe3\x82\xaf] \xe4\xbd\x9c\xe6\xa5\xad\xe9\x96\x8b\xe5\xa7\x8b\xe3\x83\xbb\xe5\xae\x8c\xe4\xba\x86", // [タスク] 作業開始・完了
    "[\xe8\xaa\xbf\xe6\x9f\xbb] \xe8\xaa\xbf\xe6\x9f\xbb\xe3\x83\xbb\xe5\x88\x86\xe6\x9e\x90\xe4\xbd\x9c\xe6\xa5\xad", // [調査] 調査・分析作業
    "[\xe5\xad\xa6\xe3\x81\xb3] \xe6\x96\xb0\xe3\x81\x97\xe3\x81\x84\xe7\x9f\xa5\xe8\xa6\x8b\xe3\x80\x81\xe6\xb0\x97\xe3\x81\xa5\xe3\x81\x8d", // [学び] 新しい知見、気づき
    "[\xe5\x95\x8f\xe9\xa1\x8c] \xe3\x83\x90\xe3\x82\xb0\xe3\x80\x81\xe8\xaa\xb2\xe9\xa1\x8c\xe3\x81\xae\xe7\x99\xba\xe8\xa6\x8b", // [問題] バグ、課題の発見
    "[\xe8\xa7\xa3\xe6\xb1\xba] \xe5\x95\x8f\xe9\xa1\x8c\xe3\x81\xae\xe8\xa7\xa3\xe6\xb1\xba", // [解決] 問題の解決
    "[\xe6\x8c\xaf\xe3\x82\x8a\xe8\xbf\x94\xe3\x82\x8a] \xe6\x97\xa5\xe5\xa0\xb1\xe3\x80\x81\xe9\x80\xb1\xe5\xa0\xb1\xe3\x81\xaa\xe3\x81\xa9", // [振り返り] 日報、週報など
    "[\xe4\xbc\x9a\xe8\xad\xb0] \xe3\x83\x9f\xe3\x83\xbc\xe3\x83\x86\xe3\x82\xa3\xe3\x83\xb3\xe3\x82\xb0", // [会議] ミーティング
    "[\xe3\x83\xac\xe3\x83\x93\xe3\x83\xa5\xe3\x83\xbc] \xe3\x82\xb3\xe3\x83\xbc\xe3\x83\x89\xe3\x83\xac\xe3\x83\x93\xe3\x83\xa5\xe3\x83\xbc", // [レビュー] コードレビュー
    "[\xe3\x83\x87\xe3\x83\x97\xe3\x83\xad\xe3\x82\xa4] \xe3\x83\xaa\xe3\x83\xaa\xe3\x83\xbc\xe3\x82\xb9\xe9\x96\xa2\xe9\x80\xa3", // [デプロイ] リリース関連
    "[\xe3\x82\xa2\xe3\x82\xa4\xe3\x83\x87\xe3\x82\xa2] \xe4\xbb\x8a\xe5\xbe\x8c\xe3\x81\xae\xe6\x94\xb9\xe5\x96\x84\xe6\xa1\x88", // [アイデア] 今後の改善案
    "[LLM\xe6\xb4\xbb\xe7\x94\xa8] Claude Code\xe7\xad\x89\xe3\x81\xae\xe6\xb4\xbb\xe7\x94\xa8", // [LLM活用] Claude Code等の活用
    "[\xe6\x89\x8b\xe6\x88\xbb\xe3\x82\x8a] \xe4\xbf\xae\xe6\xad\xa3\xe3\x83\xbb\xe3\x82\x84\xe3\x82\x8a\xe7\x9b\xb4\xe3\x81\x97", // [手戻り] 修正・やり直し
};

const importance_markers = [_][]const u8{
    "\xe3\x81\xaa\xe3\x81\x97", // なし
    "\xe2\xad\x90 \xe9\x87\x8d\xe8\xa6\x81 - \xe5\xbe\x8c\xe3\x81\xa7\xe6\x8c\xaf\xe3\x82\x8a\xe8\xbf\x94\xe3\x82\x8a\xe3\x81\x9f\xe3\x81\x84\xe9\x87\x8d\xe8\xa6\x81\xe3\x81\xaa\xe5\x87\xba\xe6\x9d\xa5\xe4\xba\x8b", // ⭐ 重要 - 後で振り返りたい重要な出来事
    "\xf0\x9f\x94\xa5 \xe7\xb7\x8a\xe6\x80\xa5 - \xe3\x81\x99\xe3\x81\x90\xe3\x81\xab\xe5\xaf\xbe\xe5\xbf\x9c\xe3\x81\x8c\xe5\xbf\x85\xe8\xa6\x81\xe3\x81\xaa\xe5\x95\x8f\xe9\xa1\x8c", // 🔥 緊急 - すぐに対応が必要な問題
    "\xf0\x9f\x92\xa1 \xe3\x82\xa2\xe3\x82\xa4\xe3\x83\x87\xe3\x82\xa2 - \xe8\x89\xaf\xe3\x81\x84\xe3\x82\xa2\xe3\x82\xa4\xe3\x83\x87\xe3\x82\xa2\xe3\x80\x81\xe3\x81\xb2\xe3\x82\x89\xe3\x82\x81\xe3\x81\x8d", // 💡 アイデア - 良いアイデア、ひらめき
    "\xe2\x9c\x85 \xe5\xae\x8c\xe4\xba\x86 - \xe5\xa4\xa7\xe3\x81\x8d\xe3\x81\xaa\xe6\x88\x90\xe6\x9e\x9c\xe3\x80\x81\xe9\x81\x94\xe6\x88\x90", // ✅ 完了 - 大きな成果、達成
};

const summary_template =
    \\
    \\---
    \\
    \\## 📝 本日のサマリー
    \\
    \\### 完了したこと
    \\- [ ]
    \\
    \\### 学んだこと・気づき
    \\-
    \\
    \\### 明日やること
    \\- [ ]
    \\
    \\### 感情・コンディション
    \\😐 普通 / 集中度: /10
    \\
;

// ============================================================
// Command parsing
// ============================================================

const Command = union(enum) {
    open_editor,
    quick: []const u8,
    interactive,
    positional: []const u8,
    multiline,
    template,
    help,
};

fn parseArgs(allocator: std.mem.Allocator, args: []const []const u8) Command {
    if (args.len == 0) return .open_editor;

    const first = args[0];

    if (mem.eql(u8, first, "-h") or mem.eql(u8, first, "--help")) return .help;
    if (mem.eql(u8, first, "-i") or mem.eql(u8, first, "--interactive")) return .interactive;
    if (mem.eql(u8, first, "-t") or mem.eql(u8, first, "--template")) return .template;
    if (mem.eql(u8, first, "-m") or mem.eql(u8, first, "--multiline")) return .multiline;

    if (mem.eql(u8, first, "-q") or mem.eql(u8, first, "--quick")) {
        if (args.len < 2) fatal("\xe3\x83\xa1\xe3\x83\xa2\xe5\x86\x85\xe5\xae\xb9\xe3\x82\x92\xe6\x8c\x87\xe5\xae\x9a\xe3\x81\x97\xe3\x81\xa6\xe3\x81\x8f\xe3\x81\xa0\xe3\x81\x95\xe3\x81\x84"); // メモ内容を指定してください
        return .{ .quick = joinArgs(allocator, args[1..]) };
    }

    if (first.len > 0 and first[0] == '-') {
        fatal("\xe4\xb8\x8d\xe6\x98\x8e\xe3\x81\xaa\xe3\x82\xaa\xe3\x83\x97\xe3\x82\xb7\xe3\x83\xa7\xe3\x83\xb3\xe3\x81\xa7\xe3\x81\x99\xe3\x80\x82daily -h \xe3\x81\xa7\xe3\x83\x98\xe3\x83\xab\xe3\x83\x97\xe3\x82\x92\xe8\xa1\xa8\xe7\xa4\xba"); // 不明なオプションです。daily -h でヘルプを表示
    }

    return .{ .positional = joinArgs(allocator, args) };
}

fn joinArgs(allocator: std.mem.Allocator, args: []const []const u8) []const u8 {
    var total: usize = 0;
    for (args, 0..) |arg, i| {
        if (i > 0) total += 1;
        total += arg.len;
    }
    const buf = allocator.alloc(u8, total) catch fatal("out of memory");
    var pos: usize = 0;
    for (args, 0..) |arg, i| {
        if (i > 0) {
            buf[pos] = ' ';
            pos += 1;
        }
        @memcpy(buf[pos..][0..arg.len], arg);
        pos += arg.len;
    }
    return buf;
}

// ============================================================
// Output helpers
// ============================================================

fn writeStderr(msg: []const u8) void {
    const f = fs.File{ .handle = posix.STDERR_FILENO };
    f.writeAll(msg) catch {};
}

fn writeStdout(msg: []const u8) void {
    const f = fs.File{ .handle = posix.STDOUT_FILENO };
    f.writeAll(msg) catch {};
}

fn fatal(msg: []const u8) noreturn {
    writeStderr(color_red);
    writeStderr("\xe3\x82\xa8\xe3\x83\xa9\xe3\x83\xbc: "); // エラー:
    writeStderr(msg);
    writeStderr(color_reset);
    writeStderr("\n");
    std.process.exit(1);
}

fn success(msg: []const u8) void {
    writeStderr(color_green);
    writeStderr("\xe2\x9c\x93 "); // ✓
    writeStderr(msg);
    writeStderr(color_reset);
    writeStderr("\n");
}

fn info(msg: []const u8) void {
    writeStderr(color_blue);
    writeStderr("\xe2\x84\xb9 "); // ℹ
    writeStderr(msg);
    writeStderr(color_reset);
    writeStderr("\n");
}

fn showHelp() void {
    writeStdout(
        color_green ++ "daily" ++ color_reset ++ " - \xe6\x97\xa5\xe8\xa8\x98\xe3\x81\xab\xe3\x83\xa1\xe3\x83\xa2\xe3\x82\x92\xe8\xbf\xbd\xe5\x8a\xa0\xe3\x81\x99\xe3\x82\x8b\xe3\x83\x84\xe3\x83\xbc\xe3\x83\xab\n" ++ // daily - 日記にメモを追加するツール
            "\n" ++
            color_yellow ++ "\xe4\xbd\xbf\xe3\x81\x84\xe6\x96\xb9:" ++ color_reset ++ "\n" ++ // 使い方:
            "  daily                  \xe3\x82\xa8\xe3\x83\x87\xe3\x82\xa3\xe3\x82\xbf\xe3\x81\xa7\xe6\x97\xa5\xe8\xa8\x98\xe3\x82\x92\xe9\x96\x8b\xe3\x81\x8f\n" ++ // エディタで日記を開く
            "  daily -i               \xe5\xaf\xbe\xe8\xa9\xb1\xe3\x83\xa2\xe3\x83\xbc\xe3\x83\x89\xef\xbc\x88\xe3\x82\xab\xe3\x83\x86\xe3\x82\xb4\xe3\x83\xaa\xe3\x83\xbc\xe3\x83\xbb\xe9\x87\x8d\xe8\xa6\x81\xe5\xba\xa6\xe9\x81\xb8\xe6\x8a\x9e\xe3\x81\x82\xe3\x82\x8a\xef\xbc\x89\n" ++ // 対話モード（カテゴリー・重要度選択あり）
            "  daily \"\xe3\x83\xa1\xe3\x83\xa2\xe5\x86\x85\xe5\xae\xb9\"        \xe7\xb0\xa1\xe6\x98\x93\xe3\x83\xa2\xe3\x83\xbc\xe3\x83\x89\xef\xbc\x88\xe3\x82\xab\xe3\x83\x86\xe3\x82\xb4\xe3\x83\xaa\xe3\x83\xbc\xe3\x83\xbb\xe9\x87\x8d\xe8\xa6\x81\xe5\xba\xa6\xe9\x81\xb8\xe6\x8a\x9e\xe3\x81\x82\xe3\x82\x8a\xef\xbc\x89\n" ++ // 簡易モード（カテゴリー・重要度選択あり）
            "  daily -q \"\xe3\x83\xa1\xe3\x83\xa2\xe5\x86\x85\xe5\xae\xb9\"     \xe3\x82\xaf\xe3\x82\xa4\xe3\x83\x83\xe3\x82\xaf\xe3\x83\xa2\xe3\x83\xbc\xe3\x83\x89\xef\xbc\x88\xe3\x82\xab\xe3\x83\x86\xe3\x82\xb4\xe3\x83\xaa\xe3\x83\xbc\xe9\x81\xb8\xe6\x8a\x9e\xe3\x81\xaa\xe3\x81\x97\xef\xbc\x89\n" ++ // クイックモード（カテゴリー選択なし）
            "  daily -m               \xe3\x82\xa8\xe3\x83\x87\xe3\x82\xa3\xe3\x82\xbf\xe3\x81\xa7\xe8\xa4\x87\xe6\x95\xb0\xe8\xa1\x8c\xe3\x83\xa1\xe3\x83\xa2\xe3\x82\x92\xe4\xbd\x9c\xe6\x88\x90\n" ++ // エディタで複数行メモを作成
            "  daily -t               \xe6\x97\xa5\xe6\xac\xa1\xe3\x82\xb5\xe3\x83\x9e\xe3\x83\xaa\xe3\x83\xbc\xe3\x83\x86\xe3\x83\xb3\xe3\x83\x97\xe3\x83\xac\xe3\x83\xbc\xe3\x83\x88\xe3\x82\x92\xe8\xbf\xbd\xe5\x8a\xa0\n" ++ // 日次サマリーテンプレートを追加
            "  daily -h, --help       \xe3\x81\x93\xe3\x81\xae\xe3\x83\x98\xe3\x83\xab\xe3\x83\x97\xe3\x82\x92\xe8\xa1\xa8\xe7\xa4\xba\n", // このヘルプを表示
    );
}

// ============================================================
// TZif parser (from cc-statusline)
// ============================================================

fn getUtcOffsetSeconds(allocator: std.mem.Allocator, now_s: i64) i32 {
    if (posix.getenv("TZ")) |tz_raw| {
        const tz = if (tz_raw.len > 0 and tz_raw[0] == ':') tz_raw[1..] else tz_raw;
        if (tz.len == 0 or mem.eql(u8, tz, "UTC") or mem.eql(u8, tz, "UTC0")) return 0;

        if (tz.len > 0 and tz[0] == '/') {
            if (readTzifOffset(allocator, tz, now_s)) |off| return off;
        }

        var path_buf: [256]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buf, "/usr/share/zoneinfo/{s}", .{tz}) catch null;
        if (path) |p| {
            if (readTzifOffset(allocator, p, now_s)) |off| return off;
        }
    }

    if (readTzifOffset(allocator, "/etc/localtime", now_s)) |off| return off;
    return 0;
}

fn readTzifOffset(allocator: std.mem.Allocator, path: []const u8, now_s: i64) ?i32 {
    const f = fs.openFileAbsolute(path, .{}) catch return null;
    defer f.close();
    const data = f.readToEndAlloc(allocator, 1024 * 1024) catch return null;
    defer allocator.free(data);
    return parseTzif(data, now_s);
}

fn readBigI32(b: *const [4]u8) i32 {
    return @bitCast(mem.readInt(u32, b, .big));
}

fn readBigU32(b: *const [4]u8) u32 {
    return mem.readInt(u32, b, .big);
}

fn readBigI64(b: *const [8]u8) i64 {
    return @bitCast(mem.readInt(u64, b, .big));
}

fn parseTzif(data: []const u8, now_s: i64) ?i32 {
    if (data.len < 44) return null;
    if (!mem.eql(u8, data[0..4], "TZif")) return null;

    const version = data[4];

    const v1_isutcnt = readBigU32(data[20..24]);
    const v1_isstdcnt = readBigU32(data[24..28]);
    const v1_leapcnt = readBigU32(data[28..32]);
    const v1_timecnt = readBigU32(data[32..36]);
    const v1_typecnt = readBigU32(data[36..40]);
    const v1_charcnt = readBigU32(data[40..44]);

    if (version == '2' or version == '3') {
        const v1_data_size = v1_timecnt * 5 + v1_typecnt * 6 + v1_charcnt + v1_leapcnt * 8 + v1_isstdcnt + v1_isutcnt;
        const v2_offset = 44 + v1_data_size;
        if (v2_offset + 44 > data.len) return null;
        if (!mem.eql(u8, data[v2_offset..][0..4], "TZif")) return null;

        const v2_timecnt = readBigU32(data[v2_offset + 32 ..][0..4]);
        const v2_typecnt = readBigU32(data[v2_offset + 36 ..][0..4]);
        return parseTzifData(data[v2_offset + 44 ..], v2_timecnt, v2_typecnt, now_s, true);
    }

    return parseTzifData(data[44..], v1_timecnt, v1_typecnt, now_s, false);
}

fn parseTzifData(data: []const u8, timecnt: u32, typecnt: u32, now_s: i64, is_64bit: bool) ?i32 {
    if (typecnt == 0) return null;
    const time_size: u32 = if (is_64bit) 8 else 4;
    const times_end = timecnt * time_size;
    const indices_end = times_end + timecnt;
    const types_offset = indices_end;

    if (data.len < types_offset + typecnt * 6) return null;

    var type_idx: u8 = 0;
    if (timecnt > 0) {
        var lo: u32 = 0;
        var hi: u32 = timecnt;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            const t = readTransitionTime(data, mid, is_64bit);
            if (t <= now_s) {
                lo = mid + 1;
            } else {
                hi = mid;
            }
        }
        if (lo > 0) {
            type_idx = data[times_end + lo - 1];
        } else {
            type_idx = findFirstNonDstType(data[types_offset..], typecnt);
        }
    }

    if (type_idx >= typecnt) return null;
    const type_off = types_offset + @as(u32, type_idx) * 6;
    if (type_off + 4 > data.len) return null;
    return readBigI32(data[type_off..][0..4]);
}

fn readTransitionTime(data: []const u8, idx: u32, is_64bit: bool) i64 {
    if (is_64bit) {
        const off = idx * 8;
        return readBigI64(data[off..][0..8]);
    } else {
        const off = idx * 4;
        return @as(i64, readBigI32(data[off..][0..4]));
    }
}

fn findFirstNonDstType(types_data: []const u8, typecnt: u32) u8 {
    var i: u8 = 0;
    while (i < typecnt) : (i += 1) {
        const off = @as(u32, i) * 6;
        if (off + 5 <= types_data.len and types_data[off + 4] == 0) return i;
    }
    return 0;
}

// ============================================================
// Local time
// ============================================================

const LocalTime = struct {
    year: u16,
    month: u8,
    day: u8,
    hour: u8,
    minute: u8,
    second: u8,
};

fn getLocalTime(allocator: std.mem.Allocator) LocalTime {
    const now_s = std.time.timestamp();
    const offset = getUtcOffsetSeconds(allocator, now_s);
    const local_s = now_s + @as(i64, offset);
    return epochToLocal(local_s);
}

fn epochToLocal(epoch_s: i64) LocalTime {
    var days = @divFloor(epoch_s, 86400);
    var rem = @mod(epoch_s, 86400);

    const hour: u8 = @intCast(@divFloor(rem, 3600));
    rem = @mod(rem, 3600);
    const minute: u8 = @intCast(@divFloor(rem, 60));
    const second: u8 = @intCast(@mod(rem, 60));

    // Civil date from days since 1970-01-01 (Howard Hinnant algorithm)
    days += 719468;
    const era: i64 = @divFloor(if (days >= 0) days else days - 146096, 146097);
    const doe: u32 = @intCast(days - era * 146097);
    const yoe: u32 = @intCast(@divFloor(doe -| @as(u32, @intCast(@divFloor(doe, 1460))) +| @as(u32, @intCast(@divFloor(doe, 36524))) -| @as(u32, @intCast(@divFloor(doe, 146096))), 365));
    const y: i64 = @as(i64, yoe) + era * 400;
    const doy: u32 = doe - (365 * yoe + yoe / 4 - yoe / 100);
    const mp: u32 = (5 * doy + 2) / 153;
    const d: u8 = @intCast(doy - (153 * mp + 2) / 5 + 1);
    const m_raw: u32 = if (mp < 10) mp + 3 else mp - 9;
    const m: u8 = @intCast(m_raw);
    const year_adj: i64 = if (m <= 2) y + 1 else y;

    return .{
        .year = @intCast(year_adj),
        .month = m,
        .day = d,
        .hour = hour,
        .minute = minute,
        .second = second,
    };
}

// ============================================================
// Git / file operations
// ============================================================

fn getRepoRoot(allocator: std.mem.Allocator) []const u8 {
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "git", "rev-parse", "--show-toplevel" },
    }) catch fatal("git\xe3\x82\xb3\xe3\x83\x9e\xe3\x83\xb3\xe3\x83\x89\xe3\x81\xae\xe5\xae\x9f\xe8\xa1\x8c\xe3\x81\xab\xe5\xa4\xb1\xe6\x95\x97\xe3\x81\x97\xe3\x81\xbe\xe3\x81\x97\xe3\x81\x9f"); // gitコマンドの実行に失敗しました
    switch (result.term) {
        .Exited => |code| if (code != 0) {
            fatal("Git\xe3\x83\xaa\xe3\x83\x9d\xe3\x82\xb8\xe3\x83\x88\xe3\x83\xaa\xe3\x81\x8c\xe8\xa6\x8b\xe3\x81\xa4\xe3\x81\x8b\xe3\x82\x8a\xe3\x81\xbe\xe3\x81\x9b\xe3\x82\x93"); // Gitリポジトリが見つかりません
        },
        else => fatal("Git\xe3\x83\xaa\xe3\x83\x9d\xe3\x82\xb8\xe3\x83\x88\xe3\x83\xaa\xe3\x81\x8c\xe8\xa6\x8b\xe3\x81\xa4\xe3\x81\x8b\xe3\x82\x8a\xe3\x81\xbe\xe3\x81\x9b\xe3\x82\x93"), // Gitリポジトリが見つかりません
    }
    return mem.trimRight(u8, result.stdout, "\n");
}

fn getDailyFilePath(allocator: std.mem.Allocator, lt: LocalTime) []const u8 {
    const repo_root = getRepoRoot(allocator);

    const dir_path = std.fmt.allocPrint(allocator, "{s}/.kokatsu/daily/{d:0>4}/{d:0>2}", .{ repo_root, lt.year, lt.month }) catch fatal("out of memory");
    const file_path = std.fmt.allocPrint(allocator, "{s}/{d:0>4}-{d:0>2}-{d:0>2}.md", .{ dir_path, lt.year, lt.month, lt.day }) catch fatal("out of memory");

    // Create directory recursively
    fs.cwd().makePath(dir_path) catch
        fatal("\xe3\x83\x87\xe3\x82\xa3\xe3\x83\xac\xe3\x82\xaf\xe3\x83\x88\xe3\x83\xaa\xe3\x81\xae\xe4\xbd\x9c\xe6\x88\x90\xe3\x81\xab\xe5\xa4\xb1\xe6\x95\x97\xe3\x81\x97\xe3\x81\xbe\xe3\x81\x97\xe3\x81\x9f"); // ディレクトリの作成に失敗しました

    // Create file with header if it doesn't exist
    const file = fs.openFileAbsolute(file_path, .{ .mode = .read_only }) catch |e| switch (e) {
        error.FileNotFound => {
            const header = std.fmt.allocPrint(allocator, "# {d:0>4}-{d:0>2}-{d:0>2}\n", .{ lt.year, lt.month, lt.day }) catch fatal("out of memory");
            const new_file = fs.createFileAbsolute(file_path, .{}) catch fatal("\xe3\x83\x95\xe3\x82\xa1\xe3\x82\xa4\xe3\x83\xab\xe3\x81\xae\xe4\xbd\x9c\xe6\x88\x90\xe3\x81\xab\xe5\xa4\xb1\xe6\x95\x97\xe3\x81\x97\xe3\x81\xbe\xe3\x81\x97\xe3\x81\x9f"); // ファイルの作成に失敗しました
            new_file.writeAll(header) catch {};
            new_file.close();
            return file_path;
        },
        else => fatal("\xe3\x83\x95\xe3\x82\xa1\xe3\x82\xa4\xe3\x83\xab\xe3\x82\xa2\xe3\x82\xaf\xe3\x82\xbb\xe3\x82\xb9\xe3\x82\xa8\xe3\x83\xa9\xe3\x83\xbc"), // ファイルアクセスエラー
    };
    file.close();
    return file_path;
}

// ============================================================
// fzf integration
// ============================================================

fn selectWithFzf(allocator: std.mem.Allocator, items: []const []const u8, prompt_text: []const u8, header: []const u8) ?[]const u8 {
    var child = std.process.Child.init(&.{ "fzf", "--height=40%", "--border=rounded", prompt_text, header, "--color=header:italic:underline,prompt:bold" }, allocator);
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Inherit;

    child.spawn() catch fatal("fzf\xe3\x81\xae\xe8\xb5\xb7\xe5\x8b\x95\xe3\x81\xab\xe5\xa4\xb1\xe6\x95\x97\xe3\x81\x97\xe3\x81\xbe\xe3\x81\x97\xe3\x81\x9f"); // fzfの起動に失敗しました

    // Write items to stdin
    const stdin_file = child.stdin.?;
    for (items, 0..) |item, i| {
        if (i > 0) stdin_file.writeAll("\n") catch {};
        stdin_file.writeAll(item) catch {};
    }
    // Close stdin to signal EOF
    child.stdin.?.close();
    child.stdin = null;

    // Read stdout
    const stdout_data = child.stdout.?.readToEndAlloc(allocator, 4096) catch return null;

    const term = child.wait() catch return null;
    switch (term) {
        .Exited => |code| if (code != 0) return null,
        else => return null,
    }

    const trimmed = mem.trimRight(u8, stdout_data, "\n\r");
    if (trimmed.len == 0) return null;
    return trimmed;
}

fn selectCategory(allocator: std.mem.Allocator) []const u8 {
    const selected = selectWithFzf(
        allocator,
        &categories,
        "--prompt=\xf0\x9f\x93\x8c \xe3\x82\xab\xe3\x83\x86\xe3\x82\xb4\xe3\x83\xaa\xe3\x83\xbc\xe3\x82\x92\xe9\x81\xb8\xe6\x8a\x9e: ", // 📌 カテゴリーを選択:
        "--header=Ctrl-C \xe3\x81\xa7\xe3\x82\xb9\xe3\x82\xad\xe3\x83\x83\xe3\x83\x97", // Ctrl-C でスキップ
    ) orelse return "";

    // Extract [tag] portion
    if (mem.indexOfScalar(u8, selected, ']')) |end| {
        if (selected[0] == '[') {
            return selected[0 .. end + 1];
        }
    }
    return "";
}

fn selectImportance(allocator: std.mem.Allocator) []const u8 {
    const selected = selectWithFzf(
        allocator,
        &importance_markers,
        "--prompt=\xf0\x9f\x8e\xaf \xe9\x87\x8d\xe8\xa6\x81\xe5\xba\xa6: ", // 🎯 重要度:
        "--header=\xe9\x87\x8d\xe8\xa6\x81\xe5\xba\xa6\xe3\x83\x9e\xe3\x83\xbc\xe3\x82\xab\xe3\x83\xbc\xe3\x82\x92\xe9\x81\xb8\xe6\x8a\x9e", // 重要度マーカーを選択
    ) orelse return "";

    // "なし" check
    if (mem.eql(u8, selected, importance_markers[0])) return "";

    // Extract emoji (bytes up to first space 0x20)
    if (mem.indexOfScalar(u8, selected, ' ')) |space_idx| {
        return selected[0..space_idx];
    }
    return selected;
}

// ============================================================
// Memo operations
// ============================================================

fn addMemo(allocator: std.mem.Allocator, category: []const u8, content: []const u8, importance: []const u8) void {
    const lt = getLocalTime(allocator);
    const daily_file = getDailyFilePath(allocator, lt);

    const timestamp = std.fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}", .{ lt.year, lt.month, lt.day, lt.hour, lt.minute, lt.second }) catch fatal("out of memory");

    // Build entry using allocPrint
    const imp_part = if (importance.len > 0) std.fmt.allocPrint(allocator, "{s} ", .{importance}) catch fatal("out of memory") else "";
    const cat_part = if (category.len > 0) std.fmt.allocPrint(allocator, "{s} ", .{category}) catch fatal("out of memory") else "";
    const entry = std.fmt.allocPrint(allocator, "\n## {s}\n{s}{s}{s}\n", .{ timestamp, imp_part, cat_part, content }) catch fatal("out of memory");

    // Append to file
    const file = fs.openFileAbsolute(daily_file, .{ .mode = .write_only }) catch fatal("\xe3\x83\x95\xe3\x82\xa1\xe3\x82\xa4\xe3\x83\xab\xe3\x82\x92\xe9\x96\x8b\xe3\x81\x91\xe3\x81\xbe\xe3\x81\x9b\xe3\x82\x93"); // ファイルを開けません
    defer file.close();
    file.seekFromEnd(0) catch {};
    file.writeAll(entry) catch fatal("\xe6\x9b\xb8\xe3\x81\x8d\xe8\xbe\xbc\xe3\x81\xbf\xe3\x81\xab\xe5\xa4\xb1\xe6\x95\x97\xe3\x81\x97\xe3\x81\xbe\xe3\x81\x97\xe3\x81\x9f"); // 書き込みに失敗しました

    const msg = std.fmt.allocPrint(allocator, "\xe3\x83\xa1\xe3\x83\xa2\xe3\x82\x92\xe8\xbf\xbd\xe5\x8a\xa0\xe3\x81\x97\xe3\x81\xbe\xe3\x81\x97\xe3\x81\x9f: {s}", .{daily_file}) catch return; // メモを追加しました:
    success(msg);

    const preview = std.fmt.allocPrint(allocator, "\xe5\x86\x85\xe5\xae\xb9: {s}{s}{s}", .{ imp_part, cat_part, content }) catch return; // 内容:
    info(preview);
}

fn spawnEditor(allocator: std.mem.Allocator, file_path: []const u8) void {
    const editor = posix.getenv("EDITOR") orelse "nvim";
    var child = std.process.Child.init(&.{ editor, file_path }, allocator);
    child.stdin_behavior = .Inherit;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    child.spawn() catch fatal("\xe3\x82\xa8\xe3\x83\x87\xe3\x82\xa3\xe3\x82\xbf\xe3\x81\xae\xe8\xb5\xb7\xe5\x8b\x95\xe3\x81\xab\xe5\xa4\xb1\xe6\x95\x97\xe3\x81\x97\xe3\x81\xbe\xe3\x81\x97\xe3\x81\x9f"); // エディタの起動に失敗しました
    _ = child.wait() catch {};
}

fn openEditor(allocator: std.mem.Allocator) void {
    const lt = getLocalTime(allocator);
    const daily_file = getDailyFilePath(allocator, lt);
    spawnEditor(allocator, daily_file);
}

fn addSummaryTemplate(allocator: std.mem.Allocator) void {
    const lt = getLocalTime(allocator);
    const daily_file = getDailyFilePath(allocator, lt);

    const file = fs.openFileAbsolute(daily_file, .{ .mode = .write_only }) catch fatal("\xe3\x83\x95\xe3\x82\xa1\xe3\x82\xa4\xe3\x83\xab\xe3\x82\x92\xe9\x96\x8b\xe3\x81\x91\xe3\x81\xbe\xe3\x81\x9b\xe3\x82\x93"); // ファイルを開けません
    defer file.close();
    file.seekFromEnd(0) catch {};
    file.writeAll(summary_template) catch fatal("\xe6\x9b\xb8\xe3\x81\x8d\xe8\xbe\xbc\xe3\x81\xbf\xe3\x81\xab\xe5\xa4\xb1\xe6\x95\x97\xe3\x81\x97\xe3\x81\xbe\xe3\x81\x97\xe3\x81\x9f"); // 書き込みに失敗しました

    const msg = std.fmt.allocPrint(allocator, "\xe6\x97\xa5\xe6\xac\xa1\xe3\x82\xb5\xe3\x83\x9e\xe3\x83\xaa\xe3\x83\xbc\xe3\x83\x86\xe3\x83\xb3\xe3\x83\x97\xe3\x83\xac\xe3\x83\xbc\xe3\x83\x88\xe3\x82\x92\xe8\xbf\xbd\xe5\x8a\xa0\xe3\x81\x97\xe3\x81\xbe\xe3\x81\x97\xe3\x81\x9f: {s}", .{daily_file}) catch return; // 日次サマリーテンプレートを追加しました:
    success(msg);
}

// ============================================================
// Multiline mode
// ============================================================

fn multilineMode(allocator: std.mem.Allocator) void {
    const category = selectCategory(allocator);
    const importance = selectImportance(allocator);

    // Create temp file with PID + timestamp for uniqueness
    const pid = posix.getpid();
    const ts = std.time.timestamp();
    const tmp_path = std.fmt.allocPrint(allocator, "/tmp/daily-{d}-{d}.md", .{ pid, ts }) catch fatal("out of memory");

    // Write template
    const tmp_file = fs.createFileAbsolute(tmp_path, .{}) catch fatal("\xe4\xb8\x80\xe6\x99\x82\xe3\x83\x95\xe3\x82\xa1\xe3\x82\xa4\xe3\x83\xab\xe3\x81\xae\xe4\xbd\x9c\xe6\x88\x90\xe3\x81\xab\xe5\xa4\xb1\xe6\x95\x97"); // 一時ファイルの作成に失敗
    tmp_file.writeAll("# \xe4\xb8\x8b\xe8\xa8\x98\xe3\x81\xab\xe3\x83\xa1\xe3\x83\xa2\xe5\x86\x85\xe5\xae\xb9\xe3\x82\x92\xe8\xa8\x98\xe5\x85\xa5\xe3\x81\x97\xe3\x81\xa6\xe3\x81\x8f\xe3\x81\xa0\xe3\x81\x95\xe3\x81\x84\n# \xe3\x81\x93\xe3\x81\xae\xe8\xa1\x8c\xe3\x81\xa8\xe4\xb8\x8a\xe3\x81\xae\xe8\xa1\x8c\xe3\x81\xaf\xe5\x89\x8a\xe9\x99\xa4\xe3\x81\x95\xe3\x82\x8c\xe3\x81\xbe\xe3\x81\x99\n\n\n") catch {}; // 下記にメモ内容を記入してください / この行と上の行は削除されます
    tmp_file.close();
    defer fs.deleteFileAbsolute(tmp_path) catch {};

    spawnEditor(allocator, tmp_path);

    // Read file, filter comment lines
    const raw_content = blk: {
        const f = fs.openFileAbsolute(tmp_path, .{}) catch fatal("\xe4\xb8\x80\xe6\x99\x82\xe3\x83\x95\xe3\x82\xa1\xe3\x82\xa4\xe3\x83\xab\xe3\x81\xae\xe8\xaa\xad\xe3\x81\xbf\xe8\xbe\xbc\xe3\x81\xbf\xe3\x81\xab\xe5\xa4\xb1\xe6\x95\x97"); // 一時ファイルの読み込みに失敗
        defer f.close();
        break :blk f.readToEndAlloc(allocator, 1024 * 1024) catch fatal("out of memory");
    };

    // Skip template header (# comment lines at the top), then collect content
    var lines: std.ArrayList([]const u8) = .{ .items = &.{}, .capacity = 0 };
    var iter = mem.splitScalar(u8, raw_content, '\n');
    var past_header = false;
    while (iter.next()) |line| {
        const trimmed = mem.trimLeft(u8, line, " \t");
        if (!past_header) {
            if (trimmed.len == 0 or trimmed[0] == '#') continue;
            past_header = true;
        }
        if (trimmed.len == 0) continue;
        lines.append(allocator, line) catch {};
    }

    if (lines.items.len == 0) {
        fatal("\xe3\x83\xa1\xe3\x83\xa2\xe5\x86\x85\xe5\xae\xb9\xe3\x81\x8c\xe7\xa9\xba\xe3\x81\xa7\xe3\x81\x99"); // メモ内容が空です
    }

    // Join lines
    var total_len: usize = 0;
    for (lines.items, 0..) |line, i| {
        if (i > 0) total_len += 1;
        total_len += line.len;
    }
    const content_buf = allocator.alloc(u8, total_len) catch fatal("out of memory");
    var pos: usize = 0;
    for (lines.items, 0..) |line, i| {
        if (i > 0) {
            content_buf[pos] = '\n';
            pos += 1;
        }
        @memcpy(content_buf[pos..][0..line.len], line);
        pos += line.len;
    }

    addMemo(allocator, category, content_buf, importance);
}

// ============================================================
// Interactive mode
// ============================================================

fn interactiveMode(allocator: std.mem.Allocator) void {
    info("\xe5\xaf\xbe\xe8\xa9\xb1\xe3\x83\xa2\xe3\x83\xbc\xe3\x83\x89\xe3\x81\xa7\xe3\x83\xa1\xe3\x83\xa2\xe3\x82\x92\xe8\xbf\xbd\xe5\x8a\xa0\xe3\x81\x97\xe3\x81\xbe\xe3\x81\x99"); // 対話モードでメモを追加します

    const category = selectCategory(allocator);
    const importance = selectImportance(allocator);

    // Read content from stdin
    writeStdout(color_yellow ++ "\xe3\x83\xa1\xe3\x83\xa2\xe5\x86\x85\xe5\xae\xb9: " ++ color_reset); // メモ内容:

    const stdin_file = fs.File{ .handle = posix.STDIN_FILENO };
    var buf: [4096]u8 = undefined;
    const n = stdin_file.read(&buf) catch fatal("\xe5\x85\xa5\xe5\x8a\x9b\xe3\x81\xae\xe8\xaa\xad\xe3\x81\xbf\xe5\x8f\x96\xe3\x82\x8a\xe3\x81\xab\xe5\xa4\xb1\xe6\x95\x97"); // 入力の読み取りに失敗
    const content = mem.trimRight(u8, buf[0..n], "\n\r");

    if (content.len == 0) {
        fatal("\xe3\x83\xa1\xe3\x83\xa2\xe5\x86\x85\xe5\xae\xb9\xe3\x81\x8c\xe7\xa9\xba\xe3\x81\xa7\xe3\x81\x99"); // メモ内容が空です
    }

    addMemo(allocator, category, content, importance);
}

// ============================================================
// Entry point
// ============================================================

pub fn main() void {
    mainImpl() catch |err| {
        writeStderr(color_red);
        writeStderr("\xe3\x82\xa8\xe3\x83\xa9\xe3\x83\xbc: "); // エラー:
        writeStderr(@errorName(err));
        writeStderr(color_reset);
        writeStderr("\n");
        std.process.exit(1);
    };
}

fn mainImpl() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    const cmd = parseArgs(allocator, args[1..]);

    switch (cmd) {
        .help => showHelp(),
        .open_editor => openEditor(allocator),
        .quick => |text| addMemo(allocator, "", text, ""),
        .interactive => interactiveMode(allocator),
        .positional => |text| {
            const category = selectCategory(allocator);
            const importance = selectImportance(allocator);
            addMemo(allocator, category, text, importance);
        },
        .multiline => multilineMode(allocator),
        .template => addSummaryTemplate(allocator),
    }
}
