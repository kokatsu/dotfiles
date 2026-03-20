const std = @import("std");
const mem = std.mem;
const Writer = std.io.Writer;

// ============================================================
// Constants
// ============================================================

pub const bar_width: u8 = 10;
pub const default_branch_max: usize = 24;

// ============================================================
// Theme
// ============================================================

pub const Theme = struct {
    model: []const u8,
    green: []const u8,
    yellow: []const u8,
    red: []const u8,
    dim: []const u8,
    reset: []const u8 = "\x1b[0m",
    bar_filled: []const u8 = "\xe2\x96\x88", // █ U+2588
    bar_transition: []const u8 = "\xe2\x96\x93", // ▓ U+2593
    bar_empty: []const u8 = "\xe2\x96\x91", // ░ U+2591
};

pub const theme_default = Theme{
    .model = "\x1b[36m",
    .green = "\x1b[32m",
    .yellow = "\x1b[33m",
    .red = "\x1b[31m",
    .dim = "\x1b[2m",
};

pub const theme_catppuccin_mocha = Theme{
    .model = "\x1b[38;2;137;180;250m", // Blue (#89b4fa)
    .green = "\x1b[38;2;166;227;161m", // Green (#a6e3a1)
    .yellow = "\x1b[38;2;249;226;175m", // Yellow (#f9e2af)
    .red = "\x1b[38;2;243;139;168m", // Red (#f38ba8)
    .dim = "\x1b[38;2;108;112;134m", // Overlay0 (#6c7086)
};

pub fn initTheme() Theme {
    var theme = if (std.posix.getenv("CC_STATUSLINE_THEME")) |name| blk: {
        if (mem.eql(u8, name, "catppuccin-mocha")) break :blk theme_catppuccin_mocha;
        break :blk theme_default;
    } else theme_default;

    if (std.posix.getenv("CC_STATUSLINE_COLOR_MODEL")) |v| theme.model = v;
    if (std.posix.getenv("CC_STATUSLINE_COLOR_GREEN")) |v| theme.green = v;
    if (std.posix.getenv("CC_STATUSLINE_COLOR_YELLOW")) |v| theme.yellow = v;
    if (std.posix.getenv("CC_STATUSLINE_COLOR_RED")) |v| theme.red = v;
    if (std.posix.getenv("CC_STATUSLINE_COLOR_DIM")) |v| theme.dim = v;
    if (std.posix.getenv("CC_STATUSLINE_BAR_FILLED")) |v| theme.bar_filled = v;
    if (std.posix.getenv("CC_STATUSLINE_BAR_TRANSITION")) |v| theme.bar_transition = v;
    if (std.posix.getenv("CC_STATUSLINE_BAR_EMPTY")) |v| theme.bar_empty = v;

    return theme;
}

// ============================================================
// Types
// ============================================================

pub const RateLimitWindow = struct {
    used_percentage: f64,
    resets_at_ms: ?i64 = null,
};

pub const BlockInfo = struct {
    start_ms: i64,
    end_ms: i64,
    cost: f64,
    burn_rate_per_hr: f64,
};

pub const ScanResult = struct {
    today_cost: f64 = 0,
    block: ?BlockInfo = null,
};

pub const StdinInfo = struct {
    model_id: ?[]const u8 = null,
    model_name: ?[]const u8 = null,
    session_cost: ?f64 = null,
    session_duration_ms: ?i64 = null,
    context_pct: ?f64 = null,
    context_tokens: ?i64 = null,
    lines_added: ?i64 = null,
    lines_removed: ?i64 = null,
    session_id: ?[]const u8 = null,
    transcript_path: ?[]const u8 = null,
    cwd: ?[]const u8 = null,
    rate_limit_5h: ?RateLimitWindow = null,
    rate_limit_7d: ?RateLimitWindow = null,
};

// ============================================================
// Formatting Functions
// ============================================================

pub fn formatCurrency(buf: []u8, value: f64) []const u8 {
    if (value < 0) return "$0.00";
    if (value > 0 and value < 0.01) {
        return std.fmt.bufPrint(buf, "${d:.4}", .{value}) catch "$?.??";
    }
    return std.fmt.bufPrint(buf, "${d:.2}", .{value}) catch "$?.??";
}

pub fn contextColor(theme: Theme, pct: f64) []const u8 {
    if (pct < 50.0) return theme.green;
    if (pct < 75.0) return theme.yellow;
    return theme.red;
}

pub fn buildProgressBar(buf: []u8, pct: f64, width: u8, bar_filled: []const u8, bar_transition: []const u8, bar_empty: []const u8) []const u8 {
    const clamped = @max(@as(f64, 0), @min(@as(f64, 100), pct));
    const width_f: f64 = @floatFromInt(width);
    const filled_f = clamped * width_f / 100.0;
    const filled: u8 = @intCast(@min(@as(u64, @intFromFloat(filled_f)), @as(u64, width)));
    const frac = filled_f - @as(f64, @floatFromInt(filled));
    const has_transition = frac > 0 and filled < width;
    const empty = width - filled - if (has_transition) @as(u8, 1) else @as(u8, 0);
    var pos: usize = 0;
    var i: u8 = 0;
    while (i < filled) : (i += 1) {
        if (pos + bar_filled.len > buf.len) break;
        @memcpy(buf[pos..][0..bar_filled.len], bar_filled);
        pos += bar_filled.len;
    }
    if (has_transition) {
        if (pos + bar_transition.len <= buf.len) {
            @memcpy(buf[pos..][0..bar_transition.len], bar_transition);
            pos += bar_transition.len;
        }
    }
    i = 0;
    while (i < empty) : (i += 1) {
        if (pos + bar_empty.len > buf.len) break;
        @memcpy(buf[pos..][0..bar_empty.len], bar_empty);
        pos += bar_empty.len;
    }
    return buf[0..pos];
}

pub fn formatIntComma(buf: []u8, value: i64) []const u8 {
    var tmp: [32]u8 = undefined;
    const digits = std.fmt.bufPrint(&tmp, "{d}", .{value}) catch return "?";
    const len = digits.len;
    if (len <= 3) return std.fmt.bufPrint(buf, "{s}", .{digits}) catch "?";

    var pos: usize = 0;
    const first_group = len % 3;
    if (first_group > 0) {
        for (digits[0..first_group]) |ch| {
            if (pos >= buf.len) return "?";
            buf[pos] = ch;
            pos += 1;
        }
    }
    var j: usize = first_group;
    while (j < len) {
        if (pos > 0) {
            if (pos >= buf.len) return "?";
            buf[pos] = ',';
            pos += 1;
        }
        for (digits[j..][0..3]) |ch| {
            if (pos >= buf.len) return "?";
            buf[pos] = ch;
            pos += 1;
        }
        j += 3;
    }
    return buf[0..pos];
}

pub fn formatResetDuration(buf: []u8, remaining_ms: i64) []const u8 {
    if (remaining_ms <= 0) return "now";
    const total_min = @divFloor(remaining_ms, @as(i64, 60000));
    const total_hours = @divFloor(total_min, @as(i64, 60));
    const mins = total_min - total_hours * 60;
    if (total_hours >= 24) {
        const days = @divFloor(total_hours, @as(i64, 24));
        const hours = total_hours - days * 24;
        return std.fmt.bufPrint(buf, "{d}d {d}h", .{ days, hours }) catch "??";
    }
    if (total_hours > 0) {
        return std.fmt.bufPrint(buf, "{d}h {d}m", .{ total_hours, mins }) catch "??";
    }
    return std.fmt.bufPrint(buf, "{d}m", .{mins}) catch "??";
}

pub fn truncateBranch(buf: *[256]u8, branch: []const u8, max_len: usize) []const u8 {
    if (max_len < 4 or branch.len <= max_len) return branch;
    const cut = max_len - 1;
    @memcpy(buf[0..cut], branch[0..cut]);
    @memcpy(buf[cut..][0..3], "\xe2\x80\xa6"); // U+2026 …
    return buf[0 .. cut + 3];
}

pub fn getBranchMax() usize {
    if (std.posix.getenv("CC_STATUSLINE_BRANCH_MAX")) |val| {
        const v = std.fmt.parseInt(i64, val, 10) catch return default_branch_max;
        if (v >= 4) return @intCast(v);
    }
    return default_branch_max;
}

// ============================================================
// Output
// ============================================================

pub fn printOutput(w: *Writer, theme: Theme, stdin_info: StdinInfo, scan: ?ScanResult, now_ms: i64, git_branch: ?[]const u8) !void {
    // === Line 1: Model + Branch + Context ===
    const model_name = stdin_info.model_name orelse "Unknown";
    try w.print("\xf0\x9f\xa4\x96 {s}{s}{s}", .{ theme.model, model_name, theme.reset });

    // Git branch
    if (git_branch) |branch| {
        var trunc_buf: [256]u8 = undefined;
        const display_branch = truncateBranch(&trunc_buf, branch, getBranchMax());
        try w.print(" {s}|{s} \xf0\x9f\x8c\xbf {s}{s}{s}", .{ theme.dim, theme.reset, theme.green, display_branch, theme.reset });
    }

    // Context
    if (stdin_info.context_pct) |pct| {
        const color = contextColor(theme, pct);
        var bar_buf: [128]u8 = undefined;
        const bar = buildProgressBar(&bar_buf, pct, bar_width, theme.bar_filled, theme.bar_transition, theme.bar_empty);
        try w.print(" {s}|{s} \xf0\x9f\xa7\xa0 {s}{s}{s} {s}{d:.0}%{s}", .{ theme.dim, theme.reset, color, bar, theme.reset, color, pct, theme.reset });
    } else {
        try w.print(" {s}|{s} \xf0\x9f\xa7\xa0 N/A", .{ theme.dim, theme.reset });
    }

    try w.writeAll("\n");

    // === Line 2: Cost + Block ===
    var today_buf: [32]u8 = undefined;
    if (scan) |s| {
        try w.print("\xf0\x9f\x92\xb0 {s}{s}{s} today", .{ theme.yellow, formatCurrency(&today_buf, s.today_cost), theme.reset });
    } else {
        try w.writeAll("\xf0\x9f\x92\xb0 N/A today");
    }

    if (scan) |s| {
        if (s.block) |block| {
            var block_buf: [32]u8 = undefined;
            try w.print(" {s}|{s} \xf0\x9f\x93\x8a {s}{s}{s} block", .{
                theme.dim,
                theme.reset,
                theme.yellow,
                formatCurrency(&block_buf, block.cost),
                theme.reset,
            });
            var rate_buf: [32]u8 = undefined;
            try w.print(" \xf0\x9f\x94\xa5 {s}{s}{s} {s}/h{s}", .{ theme.yellow, formatCurrency(&rate_buf, block.burn_rate_per_hr), theme.reset, theme.dim, theme.reset });
        }
    }

    try w.writeAll("\n");

    // === Line 3: Rate Limits (5h + 7d) ===
    const has_rate_limits = stdin_info.rate_limit_5h != null or stdin_info.rate_limit_7d != null;
    if (has_rate_limits) {
        // 🕔 5h ████████░░ 42% 2h 30m | 📅 7d ██████████ 86% 3d 12h
        try w.print("\xf0\x9f\x95\x94 ", .{}); // 🕔

        if (stdin_info.rate_limit_5h) |rl5| {
            const color = contextColor(theme, rl5.used_percentage);
            var bar_buf: [128]u8 = undefined;
            const bar = buildProgressBar(&bar_buf, rl5.used_percentage, bar_width, theme.bar_filled, theme.bar_transition, theme.bar_empty);
            try w.print("{s}5h{s} {s}{s}{s} {s}{d:.0}%{s}", .{
                theme.dim,           theme.reset,
                color,               bar,
                theme.reset,         color,
                rl5.used_percentage, theme.reset,
            });
            if (rl5.resets_at_ms) |reset_ms| {
                var reset_buf: [64]u8 = undefined;
                const remaining = reset_ms - now_ms;
                try w.print(" {s}{s}{s}", .{ theme.dim, formatResetDuration(&reset_buf, remaining), theme.reset });
            }
        }

        if (stdin_info.rate_limit_5h != null and stdin_info.rate_limit_7d != null) {
            try w.print(" {s}|{s} ", .{ theme.dim, theme.reset });
        }

        if (stdin_info.rate_limit_7d) |rl7| {
            try w.print("\xf0\x9f\x93\x85 ", .{}); // 📅
            const color = contextColor(theme, rl7.used_percentage);
            var bar_buf: [128]u8 = undefined;
            const bar = buildProgressBar(&bar_buf, rl7.used_percentage, bar_width, theme.bar_filled, theme.bar_transition, theme.bar_empty);
            try w.print("{s}7d{s} {s}{s}{s} {s}{d:.0}%{s}", .{
                theme.dim,           theme.reset,
                color,               bar,
                theme.reset,         color,
                rl7.used_percentage, theme.reset,
            });
            if (rl7.resets_at_ms) |reset_ms| {
                var reset_buf: [64]u8 = undefined;
                const remaining = reset_ms - now_ms;
                try w.print(" {s}{s}{s}", .{ theme.dim, formatResetDuration(&reset_buf, remaining), theme.reset });
            }
        }

        try w.writeAll("\n");
    }
}

pub fn printFallback(w: *Writer) void {
    w.writeAll("\xf0\x9f\xa4\x96 Unknown | \xf0\x9f\xa7\xa0 N/A\n\xf0\x9f\x92\xb0 N/A today\n") catch {};
}

// ============================================================
// Tests
// ============================================================

fn contains(haystack: []const u8, needle: []const u8) bool {
    return mem.indexOf(u8, haystack, needle) != null;
}

fn countNewlines(data: []const u8) usize {
    var count: usize = 0;
    for (data) |c| {
        if (c == '\n') count += 1;
    }
    return count;
}

// --- formatCurrency ---

test "formatCurrency zero" {
    var buf: [32]u8 = undefined;
    try std.testing.expectEqualStrings("$0.00", formatCurrency(&buf, 0.0));
}

test "formatCurrency sub-cent" {
    var buf: [32]u8 = undefined;
    const result = formatCurrency(&buf, 0.005);
    try std.testing.expect(contains(result, "$0.005"));
}

test "formatCurrency normal" {
    var buf: [32]u8 = undefined;
    try std.testing.expectEqualStrings("$1.23", formatCurrency(&buf, 1.23));
}

test "formatCurrency negative" {
    var buf: [32]u8 = undefined;
    try std.testing.expectEqualStrings("$0.00", formatCurrency(&buf, -1.0));
}

// --- contextColor ---

test "contextColor thresholds" {
    const theme = theme_default;
    try std.testing.expectEqualStrings(theme.green, contextColor(theme, 0.0));
    try std.testing.expectEqualStrings(theme.green, contextColor(theme, 49.9));
    try std.testing.expectEqualStrings(theme.yellow, contextColor(theme, 50.0));
    try std.testing.expectEqualStrings(theme.yellow, contextColor(theme, 74.9));
    try std.testing.expectEqualStrings(theme.red, contextColor(theme, 75.0));
    try std.testing.expectEqualStrings(theme.red, contextColor(theme, 100.0));
}

// --- buildProgressBar ---

test "buildProgressBar default UTF-8 chars" {
    var buf: [128]u8 = undefined;
    const bar = buildProgressBar(&buf, 50.0, 10, "\xe2\x96\x88", "\xe2\x96\x93", "\xe2\x96\x91");
    try std.testing.expectEqual(@as(usize, 30), bar.len);
    try std.testing.expectEqualStrings("\xe2\x96\x88", bar[0..3]);
    try std.testing.expectEqualStrings("\xe2\x96\x91", bar[27..30]);
}

test "buildProgressBar single-byte chars" {
    var buf: [128]u8 = undefined;
    const bar = buildProgressBar(&buf, 75.0, 8, "#", "=", "-");
    try std.testing.expectEqual(@as(usize, 8), bar.len);
    try std.testing.expectEqualStrings("######--", bar);
}

test "buildProgressBar transition char" {
    var buf: [128]u8 = undefined;
    const bar1 = buildProgressBar(&buf, 37.5, 8, "#", "=", "-");
    try std.testing.expectEqualStrings("###-----", bar1);

    const bar2 = buildProgressBar(&buf, 40.0, 8, "#", "=", "-");
    try std.testing.expectEqualStrings("###=----", bar2);
}

test "buildProgressBar 0% and 100%" {
    var buf: [128]u8 = undefined;
    const empty = buildProgressBar(&buf, 0.0, 4, "#", "=", "-");
    try std.testing.expectEqualStrings("----", empty);

    const full = buildProgressBar(&buf, 100.0, 4, "#", "=", "-");
    try std.testing.expectEqualStrings("####", full);
}

// --- formatResetDuration ---

test "formatResetDuration" {
    var buf: [64]u8 = undefined;

    try std.testing.expectEqualStrings("now", formatResetDuration(&buf, 0));
    try std.testing.expectEqualStrings("now", formatResetDuration(&buf, -1000));
    try std.testing.expectEqualStrings("30m", formatResetDuration(&buf, 30 * 60 * 1000));
    try std.testing.expectEqualStrings("2h 15m", formatResetDuration(&buf, (2 * 60 + 15) * 60 * 1000));

    const three_days_4h = (3 * 24 + 4) * 3600 * 1000;
    try std.testing.expectEqualStrings("3d 4h", formatResetDuration(&buf, three_days_4h));
}

// --- truncateBranch ---

test "truncateBranch short branch unchanged" {
    var buf: [256]u8 = undefined;
    const result = truncateBranch(&buf, "main", 24);
    try std.testing.expectEqualStrings("main", result);
}

test "truncateBranch exact max unchanged" {
    var buf: [256]u8 = undefined;
    const branch = "feature/exactly-twentyfo";
    try std.testing.expectEqual(@as(usize, 24), branch.len);
    const result = truncateBranch(&buf, branch, 24);
    try std.testing.expectEqualStrings(branch, result);
}

test "truncateBranch long branch truncated" {
    var buf: [256]u8 = undefined;
    const result = truncateBranch(&buf, "feature/very-long-branch-name-that-overflows", 24);
    try std.testing.expectEqual(@as(usize, 26), result.len);
    try std.testing.expectEqualStrings("feature/very-long-branc\xe2\x80\xa6", result);
}

test "truncateBranch min max_len" {
    var buf: [256]u8 = undefined;
    const result = truncateBranch(&buf, "feature/something", 3);
    try std.testing.expectEqualStrings("feature/something", result);
}

// --- printOutput: Line 1 ---

test "printOutput line1 model name" {
    var aw: Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    const info = StdinInfo{ .model_name = "Opus 4.6" };
    try printOutput(&aw.writer, theme_default, info, null, 0, null);
    try std.testing.expect(contains(aw.writer.buffered(), "Opus 4.6"));
}

test "printOutput line1 model unknown" {
    var aw: Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    const info = StdinInfo{};
    try printOutput(&aw.writer, theme_default, info, null, 0, null);
    try std.testing.expect(contains(aw.writer.buffered(), "Unknown"));
}

test "printOutput line1 context percentage with color" {
    var aw: Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    const info = StdinInfo{ .context_pct = 80.0 };
    try printOutput(&aw.writer, theme_default, info, null, 0, null);
    const out = aw.writer.buffered();
    try std.testing.expect(contains(out, "80%"));
    try std.testing.expect(contains(out, theme_default.red));
}

test "printOutput line1 context NA" {
    var aw: Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    const info = StdinInfo{};
    try printOutput(&aw.writer, theme_default, info, null, 0, null);
    try std.testing.expect(contains(aw.writer.buffered(), "N/A"));
}

test "printOutput line1 git branch" {
    var aw: Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    const info = StdinInfo{};
    try printOutput(&aw.writer, theme_default, info, null, 0, "main");
    const out = aw.writer.buffered();
    try std.testing.expect(contains(out, "main"));
    try std.testing.expect(contains(out, "\xf0\x9f\x8c\xbf")); // 🌿
}

// --- printOutput: Line 2 ---

test "printOutput line2 today cost" {
    var aw: Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    const scan = ScanResult{ .today_cost = 1.50 };
    try printOutput(&aw.writer, theme_default, StdinInfo{}, scan, 0, null);
    const out = aw.writer.buffered();
    try std.testing.expect(contains(out, "$1.50"));
    try std.testing.expect(contains(out, "today"));
}

test "printOutput line2 block cost and burn rate" {
    var aw: Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    const scan = ScanResult{
        .today_cost = 0.50,
        .block = .{
            .start_ms = 0,
            .end_ms = 5 * 3600 * 1000,
            .cost = 2.00,
            .burn_rate_per_hr = 0.80,
        },
    };
    try printOutput(&aw.writer, theme_default, StdinInfo{}, scan, 0, null);
    const out = aw.writer.buffered();
    try std.testing.expect(contains(out, "$2.00"));
    try std.testing.expect(contains(out, "block"));
    try std.testing.expect(contains(out, "\xf0\x9f\x93\x8a")); // 📊
    try std.testing.expect(contains(out, "$0.80"));
    try std.testing.expect(contains(out, "/h"));
    try std.testing.expect(contains(out, "\xf0\x9f\x94\xa5")); // 🔥
}

test "printOutput line2 scan null" {
    var aw: Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try printOutput(&aw.writer, theme_default, StdinInfo{}, null, 0, null);
    try std.testing.expect(contains(aw.writer.buffered(), "N/A today"));
}

// --- printOutput: Line 3 ---

test "printOutput line3 5h rate limit" {
    var aw: Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    const info = StdinInfo{
        .rate_limit_5h = .{ .used_percentage = 42.0 },
    };
    try printOutput(&aw.writer, theme_default, info, null, 0, null);
    const out = aw.writer.buffered();
    try std.testing.expect(contains(out, "\xf0\x9f\x95\x94")); // 🕔
    try std.testing.expect(contains(out, "5h"));
    try std.testing.expect(contains(out, "42%"));
    try std.testing.expect(contains(out, theme_default.green)); // 42% < 50% = green
}

test "printOutput line3 7d rate limit" {
    var aw: Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    const info = StdinInfo{
        .rate_limit_7d = .{ .used_percentage = 86.0 },
    };
    try printOutput(&aw.writer, theme_default, info, null, 0, null);
    const out = aw.writer.buffered();
    try std.testing.expect(contains(out, "\xf0\x9f\x93\x85")); // 📅
    try std.testing.expect(contains(out, "7d"));
    try std.testing.expect(contains(out, "86%"));
    try std.testing.expect(contains(out, theme_default.red)); // 86% >= 75% = red
}

test "printOutput line3 both rate limits with separator" {
    var aw: Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    const info = StdinInfo{
        .rate_limit_5h = .{ .used_percentage = 30.0 },
        .rate_limit_7d = .{ .used_percentage = 60.0 },
    };
    try printOutput(&aw.writer, theme_default, info, null, 0, null);
    const out = aw.writer.buffered();
    try std.testing.expect(contains(out, "5h"));
    try std.testing.expect(contains(out, "7d"));
    // 3 newlines: line1 + line2 + line3
    try std.testing.expectEqual(@as(usize, 3), countNewlines(out));
}

test "printOutput line3 rate limit reset time" {
    var aw: Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    const now_ms: i64 = 1000 * 1000;
    const info = StdinInfo{
        .rate_limit_5h = .{
            .used_percentage = 50.0,
            .resets_at_ms = now_ms + 2 * 3600 * 1000 + 30 * 60 * 1000, // +2h 30m
        },
    };
    try printOutput(&aw.writer, theme_default, info, null, now_ms, null);
    try std.testing.expect(contains(aw.writer.buffered(), "2h 30m"));
}

test "printOutput no line3 without rate limits" {
    var aw: Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try printOutput(&aw.writer, theme_default, StdinInfo{}, null, 0, null);
    // Only 2 newlines (line1 + line2), no line3
    try std.testing.expectEqual(@as(usize, 2), countNewlines(aw.writer.buffered()));
}

test "printOutput rate limit colors use contextColor" {
    var aw: Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    const theme = theme_catppuccin_mocha;
    const info = StdinInfo{
        .rate_limit_5h = .{ .used_percentage = 60.0 }, // 50-75 = yellow
        .rate_limit_7d = .{ .used_percentage = 90.0 }, // >=75 = red
    };
    try printOutput(&aw.writer, theme, info, null, 0, null);
    const out = aw.writer.buffered();
    try std.testing.expect(contains(out, theme.yellow));
    try std.testing.expect(contains(out, theme.red));
}

// --- printFallback ---

test "printFallback output" {
    var aw: Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    printFallback(&aw.writer);
    const out = aw.writer.buffered();
    try std.testing.expect(contains(out, "Unknown"));
    try std.testing.expect(contains(out, "N/A"));
    try std.testing.expect(contains(out, "N/A today"));
    try std.testing.expectEqual(@as(usize, 2), countNewlines(out));
}
