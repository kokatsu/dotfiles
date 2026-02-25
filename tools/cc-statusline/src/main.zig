const std = @import("std");
const json = std.json;
const mem = std.mem;
const fs = std.fs;
// ============================================================
// Constants
// ============================================================

const cache_path = "/tmp/cc-statusline-cache.bin";
const cache_ttl_s: i64 = 30;
const block_duration_ms: i64 = 5 * 60 * 60 * 1000;
const scan_window_ms: i64 = 25 * 60 * 60 * 1000;
const token_200k: i64 = 200_000;

const cache_magic = [4]u8{ 'C', 'C', 'S', 'L' };
const cache_ver: u32 = 3;
const file_list_ttl_s: i64 = 300;

// Theme
const Theme = struct {
    model: []const u8,
    green: []const u8,
    yellow: []const u8,
    red: []const u8,
    dim: []const u8,
    reset: []const u8 = "\x1b[0m",
    bar_filled: []const u8 = "\xe2\x96\x88", // █ U+2588
    bar_empty: []const u8 = "\xe2\x96\x91", // ░ U+2591
};

const theme_default = Theme{
    .model = "\x1b[36m",
    .green = "\x1b[32m",
    .yellow = "\x1b[33m",
    .red = "\x1b[31m",
    .dim = "\x1b[2m",
};

const theme_catppuccin_mocha = Theme{
    .model = "\x1b[38;2;137;180;250m", // Blue (#89b4fa)
    .green = "\x1b[38;2;166;227;161m", // Green (#a6e3a1)
    .yellow = "\x1b[38;2;249;226;175m", // Yellow (#f9e2af)
    .red = "\x1b[38;2;243;139;168m", // Red (#f38ba8)
    .dim = "\x1b[38;2;108;112;134m", // Overlay0 (#6c7086)
};

fn initTheme() Theme {
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
    if (std.posix.getenv("CC_STATUSLINE_BAR_EMPTY")) |v| theme.bar_empty = v;

    return theme;
}

// ============================================================
// Types
// ============================================================

const TokenUsage = struct {
    input_tokens: i64 = 0,
    output_tokens: i64 = 0,
    cache_creation_input_tokens: i64 = 0,
    cache_read_input_tokens: i64 = 0,
};

const TranscriptEntry = struct {
    timestamp_ms: i64,
    model: []const u8,
    usage: TokenUsage,
};

const BlockInfo = struct {
    start_ms: i64,
    end_ms: i64,
    cost: f64,
    burn_rate_per_hr: f64,
};

const StdinInfo = struct {
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
};

const ScanResult = struct {
    today_cost: f64 = 0,
    block: ?BlockInfo = null,
};

const CacheHeader = extern struct {
    magic: [4]u8,
    version: u32,
    write_time_s: i64,
    last_full_scan_s: i64,
    today_cost: f64,
    has_block: u8,
    block_start_ms: i64,
    block_end_ms: i64,
    block_cost: f64,
    block_burn_rate: f64,
    day_start_ms: i64,
    file_count: u32,
};

const CachedFileEntry = struct {
    path: []const u8,
    file_size: i64,
    per_file_cost: f64,
    parsed_size: i64,
};

const CacheResult = struct {
    scan: ScanResult,
    files: []CachedFileEntry,
    write_time_s: i64,
    last_full_scan_s: i64,
    day_start_ms: i64,
};

// ============================================================
// Pricing
// ============================================================

const ModelPricing = struct {
    prefix: []const u8,
    input: f64,
    output: f64,
    cache_creation: f64,
    cache_read: f64,
    input_above_200k: ?f64 = null,
    output_above_200k: ?f64 = null,
    cache_creation_above_200k: ?f64 = null,
    cache_read_above_200k: ?f64 = null,
};

const pricing_table = [_]ModelPricing{
    // Opus 4.6
    .{
        .prefix = "claude-opus-4-6",
        .input = 5e-6,
        .output = 25e-6,
        .cache_creation = 6.25e-6,
        .cache_read = 5e-7,
        .input_above_200k = 10e-6,
        .output_above_200k = 37.5e-6,
        .cache_creation_above_200k = 12.5e-6,
        .cache_read_above_200k = 1e-6,
    },
    // Opus 4.5
    .{
        .prefix = "claude-opus-4-5",
        .input = 5e-6,
        .output = 25e-6,
        .cache_creation = 6.25e-6,
        .cache_read = 5e-7,
        .input_above_200k = 10e-6,
        .output_above_200k = 37.5e-6,
        .cache_creation_above_200k = 12.5e-6,
        .cache_read_above_200k = 1e-6,
    },
    // Opus 4.1
    .{ .prefix = "claude-opus-4-1", .input = 15e-6, .output = 75e-6, .cache_creation = 18.75e-6, .cache_read = 1.5e-6 },
    // Opus 4 (matches "claude-opus-4-" after more specific prefixes)
    .{ .prefix = "claude-opus-4", .input = 15e-6, .output = 75e-6, .cache_creation = 18.75e-6, .cache_read = 1.5e-6 },
    // Claude 3 Opus
    .{ .prefix = "claude-3-opus", .input = 15e-6, .output = 75e-6, .cache_creation = 18.75e-6, .cache_read = 1.5e-6 },
    // Sonnet 4.6
    .{
        .prefix = "claude-sonnet-4-6",
        .input = 3e-6,
        .output = 15e-6,
        .cache_creation = 3.75e-6,
        .cache_read = 3e-7,
        .input_above_200k = 6e-6,
        .output_above_200k = 22.5e-6,
        .cache_creation_above_200k = 7.5e-6,
        .cache_read_above_200k = 6e-7,
    },
    // Sonnet 4.5
    .{
        .prefix = "claude-sonnet-4-5",
        .input = 3e-6,
        .output = 15e-6,
        .cache_creation = 3.75e-6,
        .cache_read = 3e-7,
        .input_above_200k = 6e-6,
        .output_above_200k = 22.5e-6,
        .cache_creation_above_200k = 7.5e-6,
        .cache_read_above_200k = 6e-7,
    },
    // Sonnet 4.2
    .{
        .prefix = "claude-sonnet-4-2",
        .input = 3e-6,
        .output = 15e-6,
        .cache_creation = 3.75e-6,
        .cache_read = 3e-7,
        .input_above_200k = 6e-6,
        .output_above_200k = 22.5e-6,
        .cache_creation_above_200k = 7.5e-6,
        .cache_read_above_200k = 6e-7,
    },
    // Sonnet 4 (matches "claude-sonnet-4-" after more specific prefixes)
    .{
        .prefix = "claude-sonnet-4",
        .input = 3e-6,
        .output = 15e-6,
        .cache_creation = 3.75e-6,
        .cache_read = 3e-7,
        .input_above_200k = 6e-6,
        .output_above_200k = 22.5e-6,
        .cache_creation_above_200k = 7.5e-6,
        .cache_read_above_200k = 6e-7,
    },
    // Sonnet 3.7
    .{ .prefix = "claude-3-7-sonnet", .input = 3e-6, .output = 15e-6, .cache_creation = 3.75e-6, .cache_read = 3e-7 },
    // Sonnet 3.5
    .{ .prefix = "claude-3-5-sonnet", .input = 3e-6, .output = 15e-6, .cache_creation = 3.75e-6, .cache_read = 3e-7 },
    // Haiku 4.5
    .{ .prefix = "claude-haiku-4-5", .input = 1e-6, .output = 5e-6, .cache_creation = 1.25e-6, .cache_read = 1e-7 },
    // Haiku 3.5
    .{ .prefix = "claude-3-5-haiku", .input = 8e-7, .output = 4e-6, .cache_creation = 1e-6, .cache_read = 8e-8 },
};

fn findPricing(model: []const u8) ?ModelPricing {
    for (&pricing_table) |p| {
        if (mem.startsWith(u8, model, p.prefix)) return p;
    }
    return null;
}

fn calculateEntryCost(pricing: ModelPricing, usage: TokenUsage) f64 {
    const total_input = usage.input_tokens + usage.cache_creation_input_tokens + usage.cache_read_input_tokens;
    const use_premium = total_input > token_200k and pricing.input_above_200k != null;

    const input_rate = if (use_premium) pricing.input_above_200k.? else pricing.input;
    const output_rate = if (use_premium) (pricing.output_above_200k orelse pricing.output) else pricing.output;
    const cc_rate = if (use_premium) (pricing.cache_creation_above_200k orelse pricing.cache_creation) else pricing.cache_creation;
    const cr_rate = if (use_premium) (pricing.cache_read_above_200k orelse pricing.cache_read) else pricing.cache_read;

    return (if (usage.input_tokens > 0) @as(f64, @floatFromInt(usage.input_tokens)) * input_rate else 0) +
        (if (usage.output_tokens > 0) @as(f64, @floatFromInt(usage.output_tokens)) * output_rate else 0) +
        (if (usage.cache_creation_input_tokens > 0) @as(f64, @floatFromInt(usage.cache_creation_input_tokens)) * cc_rate else 0) +
        (if (usage.cache_read_input_tokens > 0) @as(f64, @floatFromInt(usage.cache_read_input_tokens)) * cr_rate else 0);
}

// ============================================================
// JSON Helpers
// ============================================================

fn getObj(val: json.Value) ?json.ObjectMap {
    return switch (val) {
        .object => |o| o,
        else => null,
    };
}

fn getStr(val: json.Value) ?[]const u8 {
    return switch (val) {
        .string => |s| s,
        else => null,
    };
}

fn getF64(val: json.Value) ?f64 {
    return switch (val) {
        .integer => |i| @as(f64, @floatFromInt(i)),
        .float => |f| f,
        else => null,
    };
}

fn getI64(val: json.Value) ?i64 {
    return switch (val) {
        .integer => |i| i,
        .float => |f| @as(i64, @intFromFloat(f)),
        else => null,
    };
}

// ============================================================
// ISO 8601 Parser
// ============================================================

fn parseIso8601ToMs(s: []const u8) ?i64 {
    if (s.len < 19) return null;
    if (s[4] != '-' or s[7] != '-' or (s[10] != 'T' and s[10] != 't') or s[13] != ':' or s[16] != ':') return null;

    const year = parseDecimal(s[0..4]) orelse return null;
    const month = parseDecimal(s[5..7]) orelse return null;
    const day = parseDecimal(s[8..10]) orelse return null;
    const hour = parseDecimal(s[11..13]) orelse return null;
    const minute = parseDecimal(s[14..16]) orelse return null;
    const second = parseDecimal(s[17..19]) orelse return null;

    var millis: i64 = 0;
    if (s.len > 19 and s[19] == '.') {
        var pos: usize = 20;
        var mult: i64 = 100;
        while (pos < s.len and s[pos] >= '0' and s[pos] <= '9' and mult > 0) : (pos += 1) {
            millis += @as(i64, s[pos] - '0') * mult;
            mult = @divFloor(mult, 10);
        }
    }

    const days = daysFromCivil(@intCast(year), @intCast(month), @intCast(day));
    const epoch_s = days * 86400 + @as(i64, @intCast(hour)) * 3600 + @as(i64, @intCast(minute)) * 60 + @as(i64, @intCast(second));
    return epoch_s * 1000 + millis;
}

fn parseDecimal(s: []const u8) ?i64 {
    var result: i64 = 0;
    for (s) |c| {
        if (c < '0' or c > '9') return null;
        result = result * 10 + @as(i64, c - '0');
    }
    return result;
}

/// Howard Hinnant's civil_from_days algorithm
fn daysFromCivil(year_in: i32, month_in: u8, day_in: u8) i64 {
    var y: i64 = @intCast(year_in);
    const m: i64 = @intCast(month_in);
    const d: i64 = @intCast(day_in);
    if (m <= 2) y -= 1;
    const era = @divFloor(if (y >= 0) y else y - 399, 400);
    const yoe = y - era * 400;
    const doy = @divFloor(153 * (if (m > 2) m - 3 else m + 9) + 2, 5) + d - 1;
    const doe = yoe * 365 + @divFloor(yoe, 4) - @divFloor(yoe, 100) + doy;
    return era * 146097 + doe - 719468;
}

/// Get the start of today in milliseconds (local timezone, pure Zig)
fn getLocalDayStartMs(allocator: std.mem.Allocator, now_ms: i64) i64 {
    const now_s = @divFloor(now_ms, @as(i64, 1000));
    const offset_s: i64 = @intCast(getUtcOffsetSeconds(allocator, now_s));
    const local_s = now_s + offset_s;
    const local_day_start_s = @divFloor(local_s, @as(i64, 86400)) * 86400;
    return (local_day_start_s - offset_s) * 1000;
}

// ============================================================
// Timezone (pure Zig TZIF parser)
// ============================================================

fn getUtcOffsetSeconds(allocator: std.mem.Allocator, now_s: i64) i32 {
    if (std.posix.getenv("TZ")) |tz_raw| {
        const tz = if (tz_raw.len > 0 and tz_raw[0] == ':') tz_raw[1..] else tz_raw;
        if (tz.len == 0 or mem.eql(u8, tz, "UTC") or mem.eql(u8, tz, "UTC0")) return 0;

        // Absolute path
        if (tz.len > 0 and tz[0] == '/') {
            if (readTzifOffset(allocator, tz, now_s)) |off| return off;
        }

        // Zone name under /usr/share/zoneinfo/
        var buf: [256]u8 = undefined;
        const path = std.fmt.bufPrint(&buf, "/usr/share/zoneinfo/{s}", .{tz}) catch null;
        if (path) |p| {
            if (readTzifOffset(allocator, p, now_s)) |off| return off;
        }
    }

    if (readTzifOffset(allocator, "/etc/localtime", now_s)) |off| return off;
    return 0; // UTC fallback
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
        // Binary search for the last transition <= now_s
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
            // Before all transitions: use first non-DST type
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

fn floorToHourMs(ms: i64) i64 {
    const ms_per_hour: i64 = 3600 * 1000;
    return @divFloor(ms, ms_per_hour) * ms_per_hour;
}

// ============================================================
// Stdin Parsing
// ============================================================

fn parseStdin(allocator: std.mem.Allocator, data: []const u8) StdinInfo {
    var info = StdinInfo{};
    if (data.len == 0) return info;
    const parsed = json.parseFromSlice(json.Value, allocator, data, .{}) catch return info;
    const root = getObj(parsed.value) orelse return info;

    if (root.get("model")) |v| {
        if (getObj(v)) |model| {
            if (model.get("id")) |id| info.model_id = getStr(id);
            if (model.get("display_name")) |name| info.model_name = getStr(name);
        }
    }
    if (root.get("cost")) |v| {
        if (getObj(v)) |cost| {
            if (cost.get("total_cost_usd")) |usd| info.session_cost = getF64(usd);
            if (cost.get("total_lines_added")) |la| info.lines_added = getI64(la);
            if (cost.get("total_lines_removed")) |lr| info.lines_removed = getI64(lr);
            if (cost.get("total_duration_ms")) |dur| {
                if (getF64(dur)) |d| info.session_duration_ms = @as(i64, @intFromFloat(d));
            }
        }
    }
    if (root.get("context_window")) |v| {
        if (getObj(v)) |ctx| {
            if (ctx.get("used_percentage")) |pct| info.context_pct = getF64(pct);
            if (ctx.get("current_usage")) |cu| {
                if (getObj(cu)) |usage| {
                    const input = if (usage.get("input_tokens")) |t| getI64(t) orelse 0 else 0;
                    const cache_create = if (usage.get("cache_creation_input_tokens")) |t| getI64(t) orelse 0 else 0;
                    const cache_read = if (usage.get("cache_read_input_tokens")) |t| getI64(t) orelse 0 else 0;
                    info.context_tokens = input + cache_create + cache_read;
                }
            }
        }
    }
    if (root.get("session_id")) |v| info.session_id = getStr(v);
    if (root.get("transcript_path")) |v| info.transcript_path = getStr(v);
    if (root.get("cwd")) |v| info.cwd = getStr(v);
    return info;
}

// ============================================================
// Git Branch Detection
// ============================================================

fn getGitBranch(buf: *[256]u8, cwd: []const u8) ?[]const u8 {
    // Walk up from cwd looking for .git/HEAD
    var path_buf: [4096]u8 = undefined;
    var dir = cwd;

    while (true) {
        const head_path = std.fmt.bufPrint(&path_buf, "{s}/.git/HEAD", .{dir}) catch return null;
        if (readGitHead(buf, head_path)) |branch| return branch;

        // Move to parent directory
        if (mem.lastIndexOfScalar(u8, dir, '/')) |sep| {
            if (sep == 0) {
                // Check root
                const root_path = std.fmt.bufPrint(&path_buf, "/.git/HEAD", .{}) catch return null;
                return readGitHead(buf, root_path);
            }
            dir = dir[0..sep];
        } else {
            return null;
        }
    }
}

fn readGitHead(buf: *[256]u8, path: []const u8) ?[]const u8 {
    var f = fs.openFileAbsolute(path, .{}) catch return null;
    defer f.close();
    const len = f.readAll(buf) catch return null;
    if (len == 0) return null;

    // Trim trailing newline
    var content = buf[0..len];
    if (content[content.len - 1] == '\n') content = content[0 .. content.len - 1];

    // "ref: refs/heads/<branch>"
    const prefix = "ref: refs/heads/";
    if (mem.startsWith(u8, content, prefix)) {
        return content[prefix.len..];
    }

    // Detached HEAD: show short hash (first 7 chars)
    if (content.len >= 7) return content[0..7];
    return content;
}

// ============================================================
// Transcript Scanning
// ============================================================

fn getConfigDir(allocator: std.mem.Allocator) ![]const u8 {
    if (std.posix.getenv("CLAUDE_CONFIG_DIR")) |dir| {
        return try allocator.dupe(u8, dir);
    }
    const home = std.posix.getenv("HOME") orelse return error.NoHome;
    return try std.fmt.allocPrint(allocator, "{s}/.config/claude", .{home});
}

const FileInfo = struct {
    path: []const u8,
    size: i64,
};

fn collectTranscriptFiles(allocator: std.mem.Allocator, projects_path: []const u8, now_ms: i64) []FileInfo {
    var files: std.ArrayListUnmanaged(FileInfo) = .{};
    const cutoff_ms = now_ms - scan_window_ms;

    var projects_dir = fs.openDirAbsolute(projects_path, .{ .iterate = true }) catch
        return files.toOwnedSlice(allocator) catch &.{};
    defer projects_dir.close();

    var proj_it = projects_dir.iterate();
    while (proj_it.next() catch null) |proj_entry| {
        if (proj_entry.kind != .directory) continue;
        const proj_name = allocator.dupe(u8, proj_entry.name) catch continue;
        scanDirRecursive(allocator, projects_path, proj_name, &files, cutoff_ms);
    }

    return files.toOwnedSlice(allocator) catch &.{};
}

fn scanDirRecursive(allocator: std.mem.Allocator, base_path: []const u8, rel_path: []const u8, files: *std.ArrayListUnmanaged(FileInfo), cutoff_ms: i64) void {
    const full_path = std.fmt.allocPrint(allocator, "{s}/{s}", .{ base_path, rel_path }) catch return;
    var dir = fs.openDirAbsolute(full_path, .{ .iterate = true }) catch return;
    defer dir.close();

    var it = dir.iterate();
    while (it.next() catch null) |entry| {
        if (entry.kind == .directory) {
            const sub_rel = std.fmt.allocPrint(allocator, "{s}/{s}", .{ rel_path, entry.name }) catch continue;
            scanDirRecursive(allocator, base_path, sub_rel, files, cutoff_ms);
        } else if (entry.kind == .file and mem.endsWith(u8, entry.name, ".jsonl")) {
            const stat = dir.statFile(entry.name) catch continue;

            const mtime_ms: i64 = @intCast(@divFloor(stat.mtime, std.time.ns_per_ms));
            if (mtime_ms < cutoff_ms) continue;

            const abs_path = std.fmt.allocPrint(allocator, "{s}/{s}", .{ full_path, entry.name }) catch continue;
            files.append(allocator, .{ .path = abs_path, .size = @intCast(stat.size) }) catch continue;
        }
    }
}

fn parseJsonlContent(allocator: std.mem.Allocator, content: []const u8, entries: *std.ArrayListUnmanaged(TranscriptEntry), seen: *std.StringHashMapUnmanaged(void)) void {
    var lines = mem.splitSequence(u8, content, "\n");
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        if (mem.indexOf(u8, line, "\"input_tokens\"") == null) continue;

        const parsed = json.parseFromSlice(json.Value, allocator, line, .{}) catch continue;
        const root = getObj(parsed.value) orelse continue;

        // Deduplication by messageId:requestId
        const msg_id = if (root.get("message")) |mv| blk: {
            const mo = getObj(mv) orelse break :blk @as(?[]const u8, null);
            break :blk if (mo.get("id")) |id| getStr(id) else null;
        } else null;
        const req_id = if (root.get("requestId")) |v| getStr(v) else null;
        if (msg_id != null and req_id != null) {
            const dedup_key = std.fmt.allocPrint(allocator, "{s}:{s}", .{ msg_id.?, req_id.? }) catch continue;
            const gop = seen.getOrPut(allocator, dedup_key) catch continue;
            if (gop.found_existing) continue;
        }

        const timestamp_str = blk: {
            const v = root.get("timestamp") orelse continue;
            break :blk getStr(v) orelse continue;
        };
        const timestamp_ms = parseIso8601ToMs(timestamp_str) orelse continue;

        const msg = blk: {
            const v = root.get("message") orelse continue;
            break :blk getObj(v) orelse continue;
        };
        const uobj = blk: {
            const v = msg.get("usage") orelse continue;
            break :blk getObj(v) orelse continue;
        };
        const model_str = if (msg.get("model")) |v| (getStr(v) orelse "unknown") else "unknown";

        const usage = TokenUsage{
            .input_tokens = if (uobj.get("input_tokens")) |v| getI64(v) orelse 0 else 0,
            .output_tokens = if (uobj.get("output_tokens")) |v| getI64(v) orelse 0 else 0,
            .cache_creation_input_tokens = if (uobj.get("cache_creation_input_tokens")) |v| getI64(v) orelse 0 else 0,
            .cache_read_input_tokens = if (uobj.get("cache_read_input_tokens")) |v| getI64(v) orelse 0 else 0,
        };

        entries.append(allocator, .{
            .timestamp_ms = timestamp_ms,
            .model = model_str,
            .usage = usage,
        }) catch continue;
    }
}

// ============================================================
// Block Detection & Cost Calculation
// ============================================================

fn identifyActiveBlock(entries: []TranscriptEntry, now_ms: i64) ?BlockInfo {
    if (entries.len == 0) return null;

    mem.sort(TranscriptEntry, entries, {}, struct {
        fn f(_: void, a: TranscriptEntry, b: TranscriptEntry) bool {
            return a.timestamp_ms < b.timestamp_ms;
        }
    }.f);

    var block_start_ms = floorToHourMs(entries[0].timestamp_ms);
    var block_entry_start: usize = 0;

    for (entries, 0..) |entry, i| {
        if (i == 0) continue;
        const time_since_start = entry.timestamp_ms - block_start_ms;
        const time_since_prev = entry.timestamp_ms - entries[i - 1].timestamp_ms;
        if (time_since_start > block_duration_ms or time_since_prev > block_duration_ms) {
            block_start_ms = floorToHourMs(entry.timestamp_ms);
            block_entry_start = i;
        }
    }

    var block_cost: f64 = 0;
    for (entries[block_entry_start..]) |entry| {
        if (findPricing(entry.model)) |pricing| {
            block_cost += calculateEntryCost(pricing, entry.usage);
        }
    }

    const block_end_ms = block_start_ms + block_duration_ms;
    const elapsed_ms: i64 = @max(now_ms - block_start_ms, 60000);
    const duration_min: f64 = @as(f64, @floatFromInt(elapsed_ms)) / 60000.0;
    const burn_rate = block_cost / duration_min * 60.0;

    return .{
        .start_ms = block_start_ms,
        .end_ms = block_end_ms,
        .cost = block_cost,
        .burn_rate_per_hr = burn_rate,
    };
}

fn computeCosts(allocator: std.mem.Allocator, entries: []TranscriptEntry, now_ms: i64) ScanResult {
    const today_start_ms = getLocalDayStartMs(allocator, now_ms);
    var today_cost: f64 = 0;
    for (entries) |entry| {
        if (entry.timestamp_ms >= today_start_ms) {
            if (findPricing(entry.model)) |pricing| {
                today_cost += calculateEntryCost(pricing, entry.usage);
            }
        }
    }

    const block = identifyActiveBlock(entries, now_ms);
    return .{
        .today_cost = today_cost,
        .block = block,
    };
}

// ============================================================
// Cache
// ============================================================

fn readCache(allocator: std.mem.Allocator, day_start_ms: i64) ?CacheResult {
    var f = fs.openFileAbsolute(cache_path, .{}) catch return null;
    defer f.close();
    const content = f.readToEndAlloc(allocator, 64 * 1024 * 1024) catch return null;

    if (content.len < @sizeOf(CacheHeader)) return null;

    var header: CacheHeader = undefined;
    @memcpy(mem.asBytes(&header), content[0..@sizeOf(CacheHeader)]);

    if (!mem.eql(u8, &header.magic, &cache_magic)) return null;
    if (header.version != cache_ver) return null;
    // Invalidate on day boundary change
    if (header.day_start_ms != day_start_ms) return null;

    var scan = ScanResult{
        .today_cost = header.today_cost,
        .block = null,
    };
    if (header.has_block != 0) {
        scan.block = .{
            .start_ms = header.block_start_ms,
            .end_ms = header.block_end_ms,
            .cost = header.block_cost,
            .burn_rate_per_hr = header.block_burn_rate,
        };
    }

    // Read file entries
    var files: std.ArrayListUnmanaged(CachedFileEntry) = .{};
    var pos: usize = @sizeOf(CacheHeader);
    var i: u32 = 0;
    while (i < header.file_count) : (i += 1) {
        if (pos + 2 > content.len) break;
        const path_len = mem.readInt(u16, content[pos..][0..2], .little);
        pos += 2;
        if (pos + path_len > content.len) break;
        const path = allocator.dupe(u8, content[pos..][0..path_len]) catch break;
        pos += path_len;
        if (pos + 24 > content.len) break;
        const file_size = @as(i64, @bitCast(mem.readInt(u64, content[pos..][0..8], .little)));
        pos += 8;
        const per_file_cost: f64 = @bitCast(mem.readInt(u64, content[pos..][0..8], .little));
        pos += 8;
        const parsed_size = @as(i64, @bitCast(mem.readInt(u64, content[pos..][0..8], .little)));
        pos += 8;
        files.append(allocator, .{
            .path = path,
            .file_size = file_size,
            .per_file_cost = per_file_cost,
            .parsed_size = parsed_size,
        }) catch break;
    }

    return .{
        .scan = scan,
        .files = files.toOwnedSlice(allocator) catch &.{},
        .write_time_s = header.write_time_s,
        .last_full_scan_s = header.last_full_scan_s,
        .day_start_ms = header.day_start_ms,
    };
}

fn writeCache(result: ScanResult, files: []const CachedFileEntry, now_s: i64, last_full_scan_s: i64, day_start_ms: i64) void {
    const header = CacheHeader{
        .magic = cache_magic,
        .version = cache_ver,
        .write_time_s = now_s,
        .last_full_scan_s = last_full_scan_s,
        .today_cost = result.today_cost,
        .has_block = if (result.block != null) 1 else 0,
        .block_start_ms = if (result.block) |b| b.start_ms else 0,
        .block_end_ms = if (result.block) |b| b.end_ms else 0,
        .block_cost = if (result.block) |b| b.cost else 0,
        .block_burn_rate = if (result.block) |b| b.burn_rate_per_hr else 0,
        .day_start_ms = day_start_ms,
        .file_count = @intCast(files.len),
    };

    const tmp_path = cache_path ++ ".tmp";
    var f = fs.createFileAbsolute(tmp_path, .{}) catch return;
    defer f.close();
    var wbuf: [8192]u8 = undefined;
    var w = f.writer(&wbuf);

    w.interface.writeAll(mem.asBytes(&header)) catch return;

    for (files) |entry| {
        var len_buf: [2]u8 = undefined;
        mem.writeInt(u16, &len_buf, @intCast(entry.path.len), .little);
        w.interface.writeAll(&len_buf) catch return;
        w.interface.writeAll(entry.path) catch return;
        var size_buf: [8]u8 = undefined;
        mem.writeInt(u64, &size_buf, @bitCast(entry.file_size), .little);
        w.interface.writeAll(&size_buf) catch return;
        var cost_buf: [8]u8 = undefined;
        mem.writeInt(u64, &cost_buf, @bitCast(entry.per_file_cost), .little);
        w.interface.writeAll(&cost_buf) catch return;
        var parsed_buf: [8]u8 = undefined;
        mem.writeInt(u64, &parsed_buf, @bitCast(entry.parsed_size), .little);
        w.interface.writeAll(&parsed_buf) catch return;
    }

    w.interface.flush() catch return;
    fs.renameAbsolute(tmp_path, cache_path) catch {};
}

// ============================================================
// Scan Orchestration
// ============================================================

fn scanTranscripts(allocator: std.mem.Allocator, now_ms: i64) ?ScanResult {
    const config_dir = getConfigDir(allocator) catch return null;
    const projects_path = std.fmt.allocPrint(allocator, "{s}/projects", .{config_dir}) catch return null;
    const now_s = @divFloor(now_ms, @as(i64, 1000));
    const day_start_ms = getLocalDayStartMs(allocator, now_ms);

    // Try cache — TTL check before any I/O
    if (readCache(allocator, day_start_ms)) |cached| {
        if (now_s - cached.write_time_s <= cache_ttl_s) {
            return cached.scan;
        }
        // TTL expired, but file list is still fresh — try stat-only diff
        if (now_s - cached.last_full_scan_s <= file_list_ttl_s and cached.files.len > 0) {
            if (diffScan(allocator, cached, now_ms, now_s, day_start_ms)) |result| {
                return result;
            }
        }
    }

    return fullScan(allocator, projects_path, now_ms, now_s, day_start_ms);
}

/// Stat-only diff scan: check cached files for size changes, parse only new bytes.
/// Returns null if any file shrank/disappeared (caller should fall back to full scan).
fn diffScan(allocator: std.mem.Allocator, cached: CacheResult, now_ms: i64, now_s: i64, day_start_ms: i64) ?ScanResult {
    var changed: std.ArrayListUnmanaged(CachedFileEntry) = .{};
    var any_shrunk = false;

    for (cached.files) |entry| {
        const stat = fs.cwd().statFile(entry.path) catch {
            any_shrunk = true;
            break;
        };
        const current_size: i64 = @intCast(stat.size);
        if (current_size < entry.file_size) {
            any_shrunk = true;
            break;
        } else if (current_size > entry.file_size) {
            changed.append(allocator, .{
                .path = entry.path,
                .file_size = current_size,
                .per_file_cost = entry.per_file_cost,
                .parsed_size = entry.parsed_size,
            }) catch return null;
        }
    }

    if (any_shrunk) return null;

    if (changed.items.len == 0) {
        // No changes — refresh TTL and return
        writeCache(cached.scan, cached.files, now_s, cached.last_full_scan_s, day_start_ms);
        return cached.scan;
    }

    // Diff-parse each changed file individually (per-file cost attribution)
    var total_diff_cost: f64 = 0;
    var new_files: std.ArrayListUnmanaged(CachedFileEntry) = .{};

    for (cached.files) |entry| {
        var changed_entry: ?CachedFileEntry = null;
        for (changed.items) |ch| {
            if (mem.eql(u8, ch.path, entry.path)) {
                changed_entry = ch;
                break;
            }
        }

        if (changed_entry) |ch| {
            var seen = std.StringHashMapUnmanaged(void){};
            var entries: std.ArrayListUnmanaged(TranscriptEntry) = .{};

            parse_file: {
                var f = fs.openFileAbsolute(ch.path, .{}) catch break :parse_file;
                defer f.close();
                if (ch.parsed_size > 0) {
                    f.seekTo(@intCast(ch.parsed_size)) catch break :parse_file;
                }
                const content = f.readToEndAlloc(allocator, 100 * 1024 * 1024) catch break :parse_file;
                if (content.len > 0) {
                    parseJsonlContent(allocator, content, &entries, &seen);
                }
            }

            var file_diff_cost: f64 = 0;
            for (entries.items) |e| {
                if (findPricing(e.model)) |pricing| {
                    file_diff_cost += calculateEntryCost(pricing, e.usage);
                }
            }

            total_diff_cost += file_diff_cost;
            new_files.append(allocator, .{
                .path = ch.path,
                .file_size = ch.file_size,
                .per_file_cost = entry.per_file_cost + file_diff_cost,
                .parsed_size = ch.file_size,
            }) catch continue;
        } else {
            new_files.append(allocator, entry) catch continue;
        }
    }

    // Recalculate today_cost from per-file costs
    var new_today_cost: f64 = 0;
    for (new_files.items) |entry| {
        new_today_cost += entry.per_file_cost;
    }

    // Update block info
    const block = blk: {
        if (total_diff_cost == 0) break :blk cached.scan.block;
        if (cached.scan.block) |existing_block| {
            const new_block_cost = existing_block.cost + total_diff_cost;
            const elapsed_ms: i64 = @max(now_ms - existing_block.start_ms, 60000);
            const duration_min: f64 = @as(f64, @floatFromInt(elapsed_ms)) / 60000.0;
            break :blk BlockInfo{
                .start_ms = existing_block.start_ms,
                .end_ms = existing_block.end_ms,
                .cost = new_block_cost,
                .burn_rate_per_hr = new_block_cost / duration_min * 60.0,
            };
        }
        break :blk @as(?BlockInfo, null);
    };

    const result = ScanResult{
        .today_cost = new_today_cost,
        .block = block,
    };
    const new_file_entries = new_files.toOwnedSlice(allocator) catch cached.files;
    writeCache(result, new_file_entries, now_s, cached.last_full_scan_s, day_start_ms);
    return result;
}

fn fullScan(allocator: std.mem.Allocator, projects_path: []const u8, now_ms: i64, now_s: i64, day_start_ms: i64) ScanResult {
    const file_infos = collectTranscriptFiles(allocator, projects_path, now_ms);
    var all_entries: std.ArrayListUnmanaged(TranscriptEntry) = .{};
    var all_seen = std.StringHashMapUnmanaged(void){};
    var cache_files: std.ArrayListUnmanaged(CachedFileEntry) = .{};

    for (file_infos) |fi| {
        var f = fs.openFileAbsolute(fi.path, .{}) catch continue;
        defer f.close();
        const content = f.readToEndAlloc(allocator, 100 * 1024 * 1024) catch continue;

        const before_len = all_entries.items.len;
        parseJsonlContent(allocator, content, &all_entries, &all_seen);

        var per_cost: f64 = 0;
        for (all_entries.items[before_len..]) |entry| {
            if (entry.timestamp_ms >= day_start_ms) {
                if (findPricing(entry.model)) |pricing| {
                    per_cost += calculateEntryCost(pricing, entry.usage);
                }
            }
        }
        cache_files.append(allocator, .{
            .path = fi.path,
            .file_size = fi.size,
            .per_file_cost = per_cost,
            .parsed_size = fi.size,
        }) catch continue;
    }

    const result = computeCosts(allocator, all_entries.items, now_ms);
    const cf = cache_files.toOwnedSlice(allocator) catch &.{};
    writeCache(result, cf, now_s, now_s, day_start_ms);
    return result;
}

// ============================================================
// Output
// ============================================================

fn formatCurrency(buf: []u8, value: f64) []const u8 {
    if (value < 0) return "$0.00";
    if (value > 0 and value < 0.01) {
        return std.fmt.bufPrint(buf, "${d:.4}", .{value}) catch "$?.??";
    }
    return std.fmt.bufPrint(buf, "${d:.2}", .{value}) catch "$?.??";
}

fn contextColor(theme: Theme, pct: f64) []const u8 {
    if (pct < 50.0) return theme.green;
    if (pct < 75.0) return theme.yellow;
    return theme.red;
}

fn buildProgressBar(buf: []u8, pct: f64, width: u8, bar_filled: []const u8, bar_empty: []const u8) []const u8 {
    const clamped = @max(@as(f64, 0), @min(@as(f64, 100), pct));
    const filled: u8 = @intCast(@min(
        @as(u64, @intFromFloat(clamped * @as(f64, @floatFromInt(width)) / 100.0)),
        @as(u64, width),
    ));
    const empty = width - filled;
    var pos: usize = 0;
    var i: u8 = 0;
    while (i < filled) : (i += 1) {
        if (pos + bar_filled.len > buf.len) break;
        @memcpy(buf[pos..][0..bar_filled.len], bar_filled);
        pos += bar_filled.len;
    }
    i = 0;
    while (i < empty) : (i += 1) {
        if (pos + bar_empty.len > buf.len) break;
        @memcpy(buf[pos..][0..bar_empty.len], bar_empty);
        pos += bar_empty.len;
    }
    return buf[0..pos];
}

fn formatIntComma(buf: []u8, value: i64) []const u8 {
    // Format integer with comma separators (e.g., 56000 -> "56,000")
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
    var i: usize = first_group;
    while (i < len) {
        if (pos > 0) {
            if (pos >= buf.len) return "?";
            buf[pos] = ',';
            pos += 1;
        }
        for (digits[i..][0..3]) |ch| {
            if (pos >= buf.len) return "?";
            buf[pos] = ch;
            pos += 1;
        }
        i += 3;
    }
    return buf[0..pos];
}

fn formatDuration(buf: []u8, remaining_ms: i64) []const u8 {
    if (remaining_ms <= 0) return "0m left";
    const total_min = @divFloor(remaining_ms, @as(i64, 60000));
    const hours = @divFloor(total_min, @as(i64, 60));
    const mins = total_min - hours * 60;
    if (hours > 0) {
        return std.fmt.bufPrint(buf, "{d}h {d}m left", .{ hours, mins }) catch "??";
    }
    return std.fmt.bufPrint(buf, "{d}m left", .{mins}) catch "??";
}

fn printOutput(theme: Theme, stdin_info: StdinInfo, scan: ?ScanResult) !void {
    const stdout = fs.File{ .handle = std.posix.STDOUT_FILENO };
    var buf: [4096]u8 = undefined;
    var writer = stdout.writer(&buf);
    const w = &writer.interface;

    // === Line 1: Model + Branch + Context + Lines ===
    const model_name = stdin_info.model_name orelse "Unknown";
    try w.print("\xf0\x9f\xa4\x96 {s}{s}{s}", .{ theme.model, model_name, theme.reset });

    // Git branch
    if (stdin_info.cwd) |cwd| {
        var branch_buf: [256]u8 = undefined;
        if (getGitBranch(&branch_buf, cwd)) |branch| {
            try w.print(" {s}|{s} \xf0\x9f\x8c\xbf {s}{s}{s}", .{ theme.dim, theme.reset, theme.green, branch, theme.reset });
        }
    }

    // Context
    if (stdin_info.context_pct) |pct| {
        const color = contextColor(theme, pct);
        var bar_buf: [128]u8 = undefined;
        const bar = buildProgressBar(&bar_buf, pct, 20, theme.bar_filled, theme.bar_empty);
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
            var dur_buf: [64]u8 = undefined;
            const now_ms = std.time.milliTimestamp();
            const remaining = block.end_ms - now_ms;
            try w.print(" {s}|{s} {s}{s}{s} block", .{
                theme.dim,
                theme.reset,
                theme.yellow,
                formatCurrency(&block_buf, block.cost),
                theme.reset,
            });
            const block_total_ms = block.end_ms - block.start_ms;
            const remaining_pct: f64 = if (block_total_ms > 0)
                @as(f64, @floatFromInt(@max(remaining, @as(i64, 0)))) / @as(f64, @floatFromInt(block_total_ms)) * 100.0
            else
                0;
            const block_bar_color = if (remaining_pct >= 50.0) theme.green else if (remaining_pct >= 20.0) theme.yellow else theme.red;
            var block_bar_buf: [128]u8 = undefined;
            const block_bar = buildProgressBar(&block_bar_buf, remaining_pct, 20, theme.bar_filled, theme.bar_empty);
            try w.print(" {s}{s}{s} {s}", .{ block_bar_color, block_bar, theme.reset, formatDuration(&dur_buf, remaining) });
            var rate_buf: [32]u8 = undefined;
            try w.print(" \xf0\x9f\x94\xa5 {s}{s}/h{s}", .{ theme.yellow, formatCurrency(&rate_buf, block.burn_rate_per_hr), theme.reset });
        }
    }

    try w.writeAll("\n");
    try w.flush();
}

fn printFallback() void {
    const stdout = fs.File{ .handle = std.posix.STDOUT_FILENO };
    var buf: [256]u8 = undefined;
    var writer = stdout.writer(&buf);
    const w = &writer.interface;
    w.writeAll("\xf0\x9f\xa4\x96 Unknown \xf0\x9f\x92\xb0 N/A\n\xf0\x9f\xa7\xa0 N/A\n") catch {};
    w.flush() catch {};
}

// ============================================================
// Main
// ============================================================

pub fn main() void {
    mainImpl() catch {
        printFallback();
    };
}

fn mainImpl() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const theme = initTheme();

    // Read stdin
    const stdin = fs.File{ .handle = std.posix.STDIN_FILENO };
    const stdin_data = stdin.readToEndAlloc(allocator, 1024 * 1024) catch &.{};

    // Parse stdin JSON
    const stdin_info = parseStdin(allocator, stdin_data);

    // Scan transcripts (or use cache)
    const scan = scanTranscripts(allocator, std.time.milliTimestamp());

    try printOutput(theme, stdin_info, scan);
}

// ============================================================
// Tests
// ============================================================

test "parseIso8601ToMs" {
    const ts1 = parseIso8601ToMs("2025-01-15T10:30:00Z").?;
    // 2025-01-15 = 20103 days from epoch
    // 10:30:00 = 37800 seconds
    const expected1: i64 = (daysFromCivil(2025, 1, 15) * 86400 + 10 * 3600 + 30 * 60) * 1000;
    try std.testing.expectEqual(expected1, ts1);

    const ts2 = parseIso8601ToMs("2025-01-15T10:30:00.123Z").?;
    try std.testing.expectEqual(expected1 + 123, ts2);

    try std.testing.expectEqual(@as(?i64, null), parseIso8601ToMs("invalid"));
    try std.testing.expectEqual(@as(?i64, null), parseIso8601ToMs(""));
}

test "daysFromCivil" {
    // Unix epoch: 1970-01-01 = day 0
    try std.testing.expectEqual(@as(i64, 0), daysFromCivil(1970, 1, 1));
    // 2000-01-01 = 10957 days
    try std.testing.expectEqual(@as(i64, 10957), daysFromCivil(2000, 1, 1));
}

test "floorToHourMs" {
    // 1h 30m 15s in ms = 5415000
    const ms = 3600 * 1000 + 30 * 60 * 1000 + 15 * 1000;
    try std.testing.expectEqual(@as(i64, 3600 * 1000), floorToHourMs(ms));
    try std.testing.expectEqual(@as(i64, 0), floorToHourMs(0));
}

test "findPricing" {
    const p1 = findPricing("claude-opus-4-6-20251212");
    try std.testing.expect(p1 != null);
    try std.testing.expectEqual(@as(f64, 5e-6), p1.?.input);

    const p2 = findPricing("claude-sonnet-4-5-20250929");
    try std.testing.expect(p2 != null);
    try std.testing.expectEqual(@as(f64, 3e-6), p2.?.input);
    try std.testing.expect(p2.?.input_above_200k != null);

    try std.testing.expect(findPricing("unknown-model") == null);
}

test "calculateEntryCost" {
    const pricing = findPricing("claude-opus-4-6-20251212").?;
    const usage = TokenUsage{
        .input_tokens = 1000,
        .output_tokens = 500,
        .cache_creation_input_tokens = 0,
        .cache_read_input_tokens = 0,
    };
    const cost = calculateEntryCost(pricing, usage);
    // 1000 * 5e-6 + 500 * 25e-6 = 0.005 + 0.0125 = 0.0175
    try std.testing.expectApproxEqAbs(@as(f64, 0.0175), cost, 1e-10);
}

test "calculateEntryCost tiered" {
    const pricing = findPricing("claude-sonnet-4-5-20250929").?;
    const usage = TokenUsage{
        .input_tokens = 250_000,
        .output_tokens = 100,
        .cache_creation_input_tokens = 0,
        .cache_read_input_tokens = 0,
    };
    const cost = calculateEntryCost(pricing, usage);
    // total_input = 250000 > 200K → all-or-nothing premium
    // input: 250000 * 6e-6 = 1.5
    // output: 100 * 22.5e-6 = 0.00225
    try std.testing.expectApproxEqAbs(@as(f64, 1.50225), cost, 1e-10);
}

test "calculateEntryCost opus tiered with cache" {
    const pricing = findPricing("claude-opus-4-6-20251212").?;
    const usage = TokenUsage{
        .input_tokens = 50_000,
        .output_tokens = 10_000,
        .cache_creation_input_tokens = 100_000,
        .cache_read_input_tokens = 100_000,
    };
    const cost = calculateEntryCost(pricing, usage);
    // total_input = 50000 + 100000 + 100000 = 250000 > 200K → premium
    // input: 50000 * 10e-6 = 0.5
    // output: 10000 * 37.5e-6 = 0.375
    // cache_creation: 100000 * 12.5e-6 = 1.25
    // cache_read: 100000 * 1e-6 = 0.1
    try std.testing.expectApproxEqAbs(@as(f64, 2.225), cost, 1e-10);
}

test "calculateEntryCost under 200k with cache uses base rate" {
    const pricing = findPricing("claude-opus-4-6-20251212").?;
    const usage = TokenUsage{
        .input_tokens = 50_000,
        .output_tokens = 5_000,
        .cache_creation_input_tokens = 80_000,
        .cache_read_input_tokens = 60_000,
    };
    const cost = calculateEntryCost(pricing, usage);
    // total_input = 50000 + 80000 + 60000 = 190000 <= 200K → base rate
    // input: 50000 * 5e-6 = 0.25
    // output: 5000 * 25e-6 = 0.125
    // cache_creation: 80000 * 6.25e-6 = 0.5
    // cache_read: 60000 * 5e-7 = 0.03
    try std.testing.expectApproxEqAbs(@as(f64, 0.905), cost, 1e-10);
}

test "parseTzif v2 fixed offset" {
    // Minimal TZIFv2 file: UTC+9 (JST), no transitions
    const header_size = 44;

    // V1 header: version '2', typecnt=1, charcnt=4, rest=0
    var v1_header: [header_size]u8 = .{0} ** header_size;
    @memcpy(v1_header[0..4], "TZif");
    v1_header[4] = '2';
    // v1 typecnt=1 at offset 36
    v1_header[39] = 1;
    // v1 charcnt=4 at offset 40
    v1_header[43] = 4;

    // V1 data: 1 type entry (6 bytes) + 4 bytes charcnt = 10 bytes
    var v1_type: [6]u8 = .{0} ** 6;
    std.mem.writeInt(u32, v1_type[0..4], @bitCast(@as(i32, 32400)), .big); // UTC+9
    const v1_abbr = [4]u8{ 'J', 'S', 'T', 0 };

    // V2 header: same structure
    var v2_header: [header_size]u8 = .{0} ** header_size;
    @memcpy(v2_header[0..4], "TZif");
    v2_header[4] = '2';
    v2_header[39] = 1; // typecnt=1
    v2_header[43] = 4; // charcnt=4

    // V2 data: same type entry + abbr
    var buf: [header_size + 10 + header_size + 10]u8 = undefined;
    var pos: usize = 0;
    @memcpy(buf[pos..][0..header_size], &v1_header);
    pos += header_size;
    @memcpy(buf[pos..][0..6], &v1_type);
    pos += 6;
    @memcpy(buf[pos..][0..4], &v1_abbr);
    pos += 4;
    @memcpy(buf[pos..][0..header_size], &v2_header);
    pos += header_size;
    @memcpy(buf[pos..][0..6], &v1_type);
    pos += 6;
    @memcpy(buf[pos..][0..4], &v1_abbr);

    const offset = parseTzif(&buf, 1700000000);
    try std.testing.expect(offset != null);
    try std.testing.expectEqual(@as(i32, 32400), offset.?);
}

test "parseTzif invalid data" {
    try std.testing.expectEqual(@as(?i32, null), parseTzif("", 0));
    try std.testing.expectEqual(@as(?i32, null), parseTzif("short", 0));
    var bad: [44]u8 = .{0} ** 44;
    @memcpy(bad[0..4], "NOPE");
    try std.testing.expectEqual(@as(?i32, null), parseTzif(&bad, 0));
}

test "parseTzif reads /etc/localtime" {
    // Verify we can read the system timezone file (if available)
    const now_s: i64 = @divFloor(std.time.milliTimestamp(), @as(i64, 1000));
    if (readTzifOffset(std.testing.allocator, "/etc/localtime", now_s)) |offset| {
        // Offset should be within -14h to +14h
        try std.testing.expect(offset >= -14 * 3600 and offset <= 14 * 3600);
    }
}

test "getLocalDayStartMs returns valid day boundary" {
    const now_ms = std.time.milliTimestamp();
    const day_start = getLocalDayStartMs(std.testing.allocator, now_ms);
    // Day start should be before or equal to now
    try std.testing.expect(day_start <= now_ms);
    // Day start should be within the last 24 hours
    try std.testing.expect(now_ms - day_start < 86400 * 1000);
    // Day start should be aligned (offset from UTC midnight by timezone offset)
    const diff_ms = day_start - @divFloor(day_start, @as(i64, 1000)) * 1000;
    try std.testing.expectEqual(@as(i64, 0), diff_ms);
}

test "identifyActiveBlock empty entries" {
    var entries = [_]TranscriptEntry{};
    try std.testing.expectEqual(@as(?BlockInfo, null), identifyActiveBlock(&entries, 1000));
}

test "identifyActiveBlock single entry" {
    const now_ms: i64 = 1700000000 * 1000;
    var entries = [_]TranscriptEntry{
        .{ .timestamp_ms = now_ms - 60000, .model = "claude-sonnet-4-5-20250929", .usage = .{ .input_tokens = 1000, .output_tokens = 500 } },
    };
    const block = identifyActiveBlock(&entries, now_ms);
    try std.testing.expect(block != null);
    try std.testing.expect(block.?.cost > 0);
    try std.testing.expect(block.?.start_ms <= entries[0].timestamp_ms);
}

test "identifyActiveBlock gap detection" {
    const base_ms: i64 = 1700000000 * 1000;
    const gap = block_duration_ms + 1000; // exceeds block_duration
    var entries = [_]TranscriptEntry{
        .{ .timestamp_ms = base_ms, .model = "claude-sonnet-4-5-20250929", .usage = .{ .input_tokens = 1000, .output_tokens = 500 } },
        .{ .timestamp_ms = base_ms + gap, .model = "claude-sonnet-4-5-20250929", .usage = .{ .input_tokens = 2000, .output_tokens = 1000 } },
    };
    const now_ms = base_ms + gap + 60000;
    const block = identifyActiveBlock(&entries, now_ms);
    try std.testing.expect(block != null);
    // Block should start at the second entry (after the gap)
    try std.testing.expect(block.?.start_ms >= base_ms + gap - 3600 * 1000);
}

test "computeCosts today entries only" {
    // Use a fixed timestamp for "now" (2025-06-15 12:00:00 UTC)
    const now_ms: i64 = (daysFromCivil(2025, 6, 15) * 86400 + 12 * 3600) * 1000;
    // Entry from today (2 hours ago)
    const today_entry = TranscriptEntry{
        .timestamp_ms = now_ms - 2 * 3600 * 1000,
        .model = "claude-sonnet-4-5-20250929",
        .usage = .{ .input_tokens = 1000, .output_tokens = 500 },
    };
    // Entry from yesterday
    const old_entry = TranscriptEntry{
        .timestamp_ms = now_ms - 30 * 3600 * 1000,
        .model = "claude-sonnet-4-5-20250929",
        .usage = .{ .input_tokens = 5000, .output_tokens = 2000 },
    };

    var entries = [_]TranscriptEntry{ old_entry, today_entry };
    const result = computeCosts(std.testing.allocator, &entries, now_ms);

    // Today cost should only include the today entry
    const pricing = findPricing("claude-sonnet-4-5-20250929").?;
    const expected_today = calculateEntryCost(pricing, today_entry.usage);
    try std.testing.expectApproxEqAbs(expected_today, result.today_cost, 1e-10);
}

test "computeCosts old entries excluded from today" {
    // Use a fixed timestamp for "now" (2025-06-15 12:00:00 UTC)
    const now_ms: i64 = (daysFromCivil(2025, 6, 15) * 86400 + 12 * 3600) * 1000;
    // Only old entries (2 days ago)
    var entries = [_]TranscriptEntry{
        .{ .timestamp_ms = now_ms - 48 * 3600 * 1000, .model = "claude-sonnet-4-5-20250929", .usage = .{ .input_tokens = 5000, .output_tokens = 2000 } },
    };
    const result = computeCosts(std.testing.allocator, &entries, now_ms);
    try std.testing.expectApproxEqAbs(@as(f64, 0), result.today_cost, 1e-10);
}

test "parseStdin context_tokens from current_usage" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const input =
        \\{"context_window":{"used_percentage":54.0,"current_usage":{"input_tokens":10000,"cache_creation_input_tokens":3000,"cache_read_input_tokens":7000}}}
    ;
    const info = parseStdin(arena.allocator(), input);
    try std.testing.expectEqual(@as(?i64, 20000), info.context_tokens);
    try std.testing.expectApproxEqAbs(@as(f64, 54.0), info.context_pct.?, 1e-10);
}

test "parseStdin null current_usage" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const input =
        \\{"context_window":{"used_percentage":10.0,"current_usage":null}}
    ;
    const info = parseStdin(arena.allocator(), input);
    try std.testing.expectEqual(@as(?i64, null), info.context_tokens);
    try std.testing.expectApproxEqAbs(@as(f64, 10.0), info.context_pct.?, 1e-10);
}

test "parseStdin missing current_usage" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const input =
        \\{"context_window":{"used_percentage":25.0}}
    ;
    const info = parseStdin(arena.allocator(), input);
    try std.testing.expectEqual(@as(?i64, null), info.context_tokens);
    try std.testing.expectApproxEqAbs(@as(f64, 25.0), info.context_pct.?, 1e-10);
}

test "parseStdin basic fields" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const input =
        \\{"model":{"id":"claude-opus-4-6","display_name":"Opus"},"cost":{"total_cost_usd":1.5},"session_id":"abc-123"}
    ;
    const info = parseStdin(arena.allocator(), input);
    try std.testing.expectEqualStrings("claude-opus-4-6", info.model_id.?);
    try std.testing.expectEqualStrings("Opus", info.model_name.?);
    try std.testing.expectApproxEqAbs(@as(f64, 1.5), info.session_cost.?, 1e-10);
    try std.testing.expectEqualStrings("abc-123", info.session_id.?);
}

test "parseStdin empty input" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const info = parseStdin(arena.allocator(), "");
    try std.testing.expectEqual(@as(?[]const u8, null), info.model_id);
    try std.testing.expectEqual(@as(?f64, null), info.session_cost);
    try std.testing.expectEqual(@as(?f64, null), info.context_pct);
    try std.testing.expectEqual(@as(?i64, null), info.context_tokens);
}

test "buildProgressBar default UTF-8 chars" {
    var buf: [128]u8 = undefined;
    const bar = buildProgressBar(&buf, 50.0, 10, "\xe2\x96\x88", "\xe2\x96\x91");
    // 5 filled (3 bytes each) + 5 empty (3 bytes each) = 30 bytes
    try std.testing.expectEqual(@as(usize, 30), bar.len);
    // First char should be █ (0xe2 0x96 0x88)
    try std.testing.expectEqualStrings("\xe2\x96\x88", bar[0..3]);
    // Last char should be ░ (0xe2 0x96 0x91)
    try std.testing.expectEqualStrings("\xe2\x96\x91", bar[27..30]);
}

test "buildProgressBar single-byte chars" {
    var buf: [128]u8 = undefined;
    const bar = buildProgressBar(&buf, 75.0, 8, "#", "-");
    // 6 filled + 2 empty = 8 bytes
    try std.testing.expectEqual(@as(usize, 8), bar.len);
    try std.testing.expectEqualStrings("######--", bar);
}

test "buildProgressBar 0% and 100%" {
    var buf: [128]u8 = undefined;
    const empty = buildProgressBar(&buf, 0.0, 4, "#", "-");
    try std.testing.expectEqualStrings("----", empty);

    const full = buildProgressBar(&buf, 100.0, 4, "#", "-");
    try std.testing.expectEqualStrings("####", full);
}

test "contextColor thresholds" {
    const theme = theme_default;
    try std.testing.expectEqualStrings(theme.green, contextColor(theme, 0.0));
    try std.testing.expectEqualStrings(theme.green, contextColor(theme, 49.9));
    try std.testing.expectEqualStrings(theme.yellow, contextColor(theme, 50.0));
    try std.testing.expectEqualStrings(theme.yellow, contextColor(theme, 74.9));
    try std.testing.expectEqualStrings(theme.red, contextColor(theme, 75.0));
    try std.testing.expectEqualStrings(theme.red, contextColor(theme, 100.0));
}
