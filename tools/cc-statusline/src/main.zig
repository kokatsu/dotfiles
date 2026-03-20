const std = @import("std");
const json = std.json;
const mem = std.mem;
const fs = std.fs;
const output = @import("output.zig");

const Theme = output.Theme;
const StdinInfo = output.StdinInfo;
const RateLimitWindow = output.RateLimitWindow;
const ScanResult = output.ScanResult;
const BlockInfo = output.BlockInfo;

// ============================================================
// Constants
// ============================================================

const cache_path = "/tmp/cc-statusline-cache.bin";
const cache_ttl_s: i64 = 30;
const block_duration_ms: i64 = 5 * 60 * 60 * 1000;
const scan_window_ms: i64 = 25 * 60 * 60 * 1000; // 25h: 24h + 1h margin for timezone offsets
const token_200k: i64 = 200_000;

const cache_magic = [4]u8{ 'C', 'C', 'S', 'L' };
const cache_ver: u32 = 4;
const file_list_ttl_s: i64 = 300;

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
        result = std.math.mul(i64, result, 10) catch return null;
        result = std.math.add(i64, result, @as(i64, c - '0')) catch return null;
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

fn parseRateLimitWindow(obj: json.ObjectMap) ?RateLimitWindow {
    const pct_val = obj.get("used_percentage") orelse return null;
    const pct = getF64(pct_val) orelse return null;
    var window = RateLimitWindow{ .used_percentage = pct };
    if (obj.get("resets_at")) |ra| {
        if (getStr(ra)) |s| {
            window.resets_at_ms = parseIso8601ToMs(s);
        }
    }
    return window;
}

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

    // Parse rate_limits (added in Claude Code v2.1.80)
    if (root.get("rate_limits")) |rl_val| {
        if (getObj(rl_val)) |rl| {
            if (rl.get("five_hour")) |fh_val| {
                if (getObj(fh_val)) |fh| {
                    info.rate_limit_5h = parseRateLimitWindow(fh);
                }
            }
            if (rl.get("seven_day")) |sd_val| {
                if (getObj(sd_val)) |sd| {
                    info.rate_limit_7d = parseRateLimitWindow(sd);
                }
            }
        }
    }

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
    return try std.fmt.allocPrint(allocator, "{s}/.claude", .{home});
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

fn parseJsonlContent(allocator: std.mem.Allocator, dedup_alloc: std.mem.Allocator, content: []const u8, entries: *std.ArrayListUnmanaged(TranscriptEntry), seen: *std.StringHashMapUnmanaged(void)) void {
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
            const dedup_key = std.fmt.allocPrint(dedup_alloc, "{s}:{s}", .{ msg_id.?, req_id.? }) catch continue;
            const gop = seen.getOrPut(dedup_alloc, dedup_key) catch continue;
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

    // Sort entries in-place by timestamp (mutates the input slice)
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

const cache_header_size: usize = 4 + 4 + 8 + 8 + 8 + 1 + 8 + 8 + 8 + 8 + 8 + 4; // 77 bytes

fn readI64(data: []const u8, pos: usize) i64 {
    return @bitCast(mem.readInt(u64, data[pos..][0..8], .little));
}

fn readF64(data: []const u8, pos: usize) f64 {
    return @bitCast(mem.readInt(u64, data[pos..][0..8], .little));
}

fn readU32(data: []const u8, pos: usize) u32 {
    return mem.readInt(u32, data[pos..][0..4], .little);
}

fn parseCacheBytes(allocator: std.mem.Allocator, content: []const u8, day_start_ms: i64) ?CacheResult {
    if (content.len < cache_header_size) return null;

    // Deserialize header fields manually
    if (!mem.eql(u8, content[0..4], &cache_magic)) return null;
    const version = readU32(content, 4);
    if (version != cache_ver) return null;

    const write_time_s = readI64(content, 8);
    const last_full_scan_s = readI64(content, 16);
    const today_cost = readF64(content, 24);
    const has_block = content[32];
    const block_start_ms = readI64(content, 33);
    const block_end_ms = readI64(content, 41);
    const block_cost = readF64(content, 49);
    const block_burn_rate = readF64(content, 57);
    const hdr_day_start_ms = readI64(content, 65);
    const file_count = readU32(content, 73);

    // Invalidate on day boundary change
    if (hdr_day_start_ms != day_start_ms) return null;

    var scan = ScanResult{
        .today_cost = today_cost,
        .block = null,
    };
    if (has_block != 0) {
        scan.block = .{
            .start_ms = block_start_ms,
            .end_ms = block_end_ms,
            .cost = block_cost,
            .burn_rate_per_hr = block_burn_rate,
        };
    }

    // Read file entries
    var files: std.ArrayListUnmanaged(CachedFileEntry) = .{};
    var pos: usize = cache_header_size;
    var i: u32 = 0;
    while (i < file_count) : (i += 1) {
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
        .write_time_s = write_time_s,
        .last_full_scan_s = last_full_scan_s,
        .day_start_ms = hdr_day_start_ms,
    };
}

fn readCache(allocator: std.mem.Allocator, day_start_ms: i64) ?CacheResult {
    var f = fs.openFileAbsolute(cache_path, .{}) catch return null;
    defer f.close();
    const content = f.readToEndAlloc(allocator, 64 * 1024 * 1024) catch return null;
    return parseCacheBytes(allocator, content, day_start_ms);
}

fn writeI64(w: anytype, value: i64) !void {
    var buf: [8]u8 = undefined;
    mem.writeInt(u64, &buf, @bitCast(value), .little);
    try w.writeAll(&buf);
}

fn writeF64(w: anytype, value: f64) !void {
    var buf: [8]u8 = undefined;
    mem.writeInt(u64, &buf, @bitCast(value), .little);
    try w.writeAll(&buf);
}

fn writeU32(w: anytype, value: u32) !void {
    var buf: [4]u8 = undefined;
    mem.writeInt(u32, &buf, value, .little);
    try w.writeAll(&buf);
}

fn serializeCacheBytes(w: anytype, result: ScanResult, files: []const CachedFileEntry, now_s: i64, last_full_scan_s: i64, day_start_ms: i64) !void {
    try w.writeAll(&cache_magic);
    try writeU32(w, cache_ver);
    try writeI64(w, now_s);
    try writeI64(w, last_full_scan_s);
    try writeF64(w, result.today_cost);
    try w.writeAll(&[_]u8{if (result.block != null) 1 else 0});
    try writeI64(w, if (result.block) |b| b.start_ms else 0);
    try writeI64(w, if (result.block) |b| b.end_ms else 0);
    try writeF64(w, if (result.block) |b| b.cost else 0);
    try writeF64(w, if (result.block) |b| b.burn_rate_per_hr else 0);
    try writeI64(w, day_start_ms);
    try writeU32(w, @intCast(files.len));

    for (files) |entry| {
        var len_buf: [2]u8 = undefined;
        mem.writeInt(u16, &len_buf, @intCast(entry.path.len), .little);
        try w.writeAll(&len_buf);
        try w.writeAll(entry.path);
        try writeI64(w, entry.file_size);
        try writeF64(w, entry.per_file_cost);
        try writeI64(w, entry.parsed_size);
    }
}

fn writeCache(result: ScanResult, files: []const CachedFileEntry, now_s: i64, last_full_scan_s: i64, day_start_ms: i64) void {
    const tmp_path = cache_path ++ ".tmp";
    var f = fs.createFileAbsolute(tmp_path, .{}) catch return;
    defer f.close();
    var wbuf: [8192]u8 = undefined;
    var writer = f.writer(&wbuf);
    serializeCacheBytes(&writer.interface, result, files, now_s, last_full_scan_s, day_start_ms) catch return;
    writer.interface.flush() catch return;
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
    var changed: std.StringHashMapUnmanaged(CachedFileEntry) = .{};
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
            changed.put(allocator, entry.path, .{
                .path = entry.path,
                .file_size = current_size,
                .per_file_cost = entry.per_file_cost,
                .parsed_size = entry.parsed_size,
            }) catch return null;
        }
    }

    if (any_shrunk) return null;

    if (changed.count() == 0) {
        writeCache(cached.scan, cached.files, now_s, cached.last_full_scan_s, day_start_ms);
        return cached.scan;
    }

    var total_diff_cost: f64 = 0;
    var new_files: std.ArrayListUnmanaged(CachedFileEntry) = .{};
    var global_seen = std.StringHashMapUnmanaged(void){};

    for (cached.files) |entry| {
        if (changed.get(entry.path)) |ch| {
            var entries: std.ArrayListUnmanaged(TranscriptEntry) = .{};

            parse_file: {
                var f = fs.openFileAbsolute(ch.path, .{}) catch break :parse_file;
                defer f.close();
                if (ch.parsed_size > 0) {
                    f.seekTo(@intCast(ch.parsed_size)) catch break :parse_file;
                }
                const content = f.readToEndAlloc(allocator, 100 * 1024 * 1024) catch break :parse_file;
                if (content.len > 0) {
                    parseJsonlContent(allocator, allocator, content, &entries, &global_seen);
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

    var new_today_cost: f64 = 0;
    for (new_files.items) |entry| {
        new_today_cost += entry.per_file_cost;
    }

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
    var cache_files: std.ArrayListUnmanaged(CachedFileEntry) = .{};

    var tmp_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer tmp_arena.deinit();
    var global_seen = std.StringHashMapUnmanaged(void){};

    for (file_infos) |fi| {
        _ = tmp_arena.reset(.retain_capacity);
        const tmp = tmp_arena.allocator();

        var f = fs.openFileAbsolute(fi.path, .{}) catch continue;
        defer f.close();
        const content = f.readToEndAlloc(tmp, 100 * 1024 * 1024) catch continue;

        var file_entries: std.ArrayListUnmanaged(TranscriptEntry) = .{};
        parseJsonlContent(tmp, allocator, content, &file_entries, &global_seen);

        for (file_entries.items) |entry| {
            all_entries.append(allocator, .{
                .timestamp_ms = entry.timestamp_ms,
                .model = allocator.dupe(u8, entry.model) catch "unknown",
                .usage = entry.usage,
            }) catch continue;
        }

        const new_items = all_entries.items[all_entries.items.len - file_entries.items.len ..];
        var per_cost: f64 = 0;
        for (new_items) |entry| {
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
// Main
// ============================================================

pub fn main() void {
    mainImpl() catch {
        const stdout = fs.File{ .handle = std.posix.STDOUT_FILENO };
        var buf: [256]u8 = undefined;
        var writer = stdout.writer(&buf);
        output.printFallback(&writer.interface);
        writer.interface.flush() catch {};
    };
}

fn mainImpl() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const theme = output.initTheme();

    // Read stdin
    const stdin = fs.File{ .handle = std.posix.STDIN_FILENO };
    const stdin_data = stdin.readToEndAlloc(allocator, 1024 * 1024) catch &.{};

    // Parse stdin JSON
    const stdin_info = parseStdin(allocator, stdin_data);

    const now_ms = std.time.milliTimestamp();

    // Scan transcripts (or use cache)
    const scan = scanTranscripts(allocator, now_ms);

    // Resolve git branch
    var branch_buf: [256]u8 = undefined;
    const git_branch: ?[]const u8 = if (stdin_info.cwd) |cwd| getGitBranch(&branch_buf, cwd) else null;

    const stdout = fs.File{ .handle = std.posix.STDOUT_FILENO };
    var buf: [4096]u8 = undefined;
    var writer = stdout.writer(&buf);
    try output.printOutput(&writer.interface, theme, stdin_info, scan, now_ms, git_branch);
    try writer.interface.flush();
}

// ============================================================
// Tests
// ============================================================

test "parseIso8601ToMs" {
    const ts1 = parseIso8601ToMs("2025-01-15T10:30:00Z").?;
    const expected1: i64 = (daysFromCivil(2025, 1, 15) * 86400 + 10 * 3600 + 30 * 60) * 1000;
    try std.testing.expectEqual(expected1, ts1);

    const ts2 = parseIso8601ToMs("2025-01-15T10:30:00.123Z").?;
    try std.testing.expectEqual(expected1 + 123, ts2);

    try std.testing.expectEqual(@as(?i64, null), parseIso8601ToMs("invalid"));
    try std.testing.expectEqual(@as(?i64, null), parseIso8601ToMs(""));
}

test "parseDecimal overflow" {
    try std.testing.expectEqual(@as(?i64, 12345), parseDecimal("12345"));
    try std.testing.expectEqual(@as(?i64, 0), parseDecimal("0"));
    try std.testing.expectEqual(@as(?i64, null), parseDecimal("99999999999999999999"));
    try std.testing.expectEqual(@as(?i64, null), parseDecimal("12a3"));
    try std.testing.expectEqual(@as(?i64, 0), parseDecimal(""));
}

test "daysFromCivil" {
    try std.testing.expectEqual(@as(i64, 0), daysFromCivil(1970, 1, 1));
    try std.testing.expectEqual(@as(i64, 10957), daysFromCivil(2000, 1, 1));
}

test "floorToHourMs" {
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
    try std.testing.expectApproxEqAbs(@as(f64, 0.905), cost, 1e-10);
}

test "parseTzif v2 fixed offset" {
    const header_size = 44;
    var v1_header: [header_size]u8 = .{0} ** header_size;
    @memcpy(v1_header[0..4], "TZif");
    v1_header[4] = '2';
    v1_header[39] = 1;
    v1_header[43] = 4;

    var v1_type: [6]u8 = .{0} ** 6;
    std.mem.writeInt(u32, v1_type[0..4], @bitCast(@as(i32, 32400)), .big);
    const v1_abbr = [4]u8{ 'J', 'S', 'T', 0 };

    var v2_header: [header_size]u8 = .{0} ** header_size;
    @memcpy(v2_header[0..4], "TZif");
    v2_header[4] = '2';
    v2_header[39] = 1;
    v2_header[43] = 4;

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
    const now_s: i64 = @divFloor(std.time.milliTimestamp(), @as(i64, 1000));
    if (readTzifOffset(std.testing.allocator, "/etc/localtime", now_s)) |offset| {
        try std.testing.expect(offset >= -14 * 3600 and offset <= 14 * 3600);
    }
}

test "getLocalDayStartMs returns valid day boundary" {
    const now_ms = std.time.milliTimestamp();
    const day_start = getLocalDayStartMs(std.testing.allocator, now_ms);
    try std.testing.expect(day_start <= now_ms);
    try std.testing.expect(now_ms - day_start < 86400 * 1000);
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
    const gap = block_duration_ms + 1000;
    var entries = [_]TranscriptEntry{
        .{ .timestamp_ms = base_ms, .model = "claude-sonnet-4-5-20250929", .usage = .{ .input_tokens = 1000, .output_tokens = 500 } },
        .{ .timestamp_ms = base_ms + gap, .model = "claude-sonnet-4-5-20250929", .usage = .{ .input_tokens = 2000, .output_tokens = 1000 } },
    };
    const now_ms = base_ms + gap + 60000;
    const block = identifyActiveBlock(&entries, now_ms);
    try std.testing.expect(block != null);
    try std.testing.expect(block.?.start_ms >= base_ms + gap - 3600 * 1000);
}

test "computeCosts today entries only" {
    const now_ms: i64 = (daysFromCivil(2025, 6, 15) * 86400 + 12 * 3600) * 1000;
    const today_entry = TranscriptEntry{
        .timestamp_ms = now_ms - 2 * 3600 * 1000,
        .model = "claude-sonnet-4-5-20250929",
        .usage = .{ .input_tokens = 1000, .output_tokens = 500 },
    };
    const old_entry = TranscriptEntry{
        .timestamp_ms = now_ms - 30 * 3600 * 1000,
        .model = "claude-sonnet-4-5-20250929",
        .usage = .{ .input_tokens = 5000, .output_tokens = 2000 },
    };

    var entries = [_]TranscriptEntry{ old_entry, today_entry };
    const result = computeCosts(std.testing.allocator, &entries, now_ms);
    const pricing = findPricing("claude-sonnet-4-5-20250929").?;
    const expected_today = calculateEntryCost(pricing, today_entry.usage);
    try std.testing.expectApproxEqAbs(expected_today, result.today_cost, 1e-10);
}

test "computeCosts old entries excluded from today" {
    const now_ms: i64 = (daysFromCivil(2025, 6, 15) * 86400 + 12 * 3600) * 1000;
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

test "parseStdin rate_limits full" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const input =
        \\{"rate_limits":{"five_hour":{"used_percentage":42.3,"resets_at":"2026-03-20T15:00:00Z"},"seven_day":{"used_percentage":85.7,"resets_at":"2026-03-24T00:00:00Z"}}}
    ;
    const info = parseStdin(arena.allocator(), input);

    try std.testing.expect(info.rate_limit_5h != null);
    try std.testing.expectApproxEqAbs(@as(f64, 42.3), info.rate_limit_5h.?.used_percentage, 1e-10);
    try std.testing.expect(info.rate_limit_5h.?.resets_at_ms != null);

    try std.testing.expect(info.rate_limit_7d != null);
    try std.testing.expectApproxEqAbs(@as(f64, 85.7), info.rate_limit_7d.?.used_percentage, 1e-10);
    try std.testing.expect(info.rate_limit_7d.?.resets_at_ms != null);
}

test "parseStdin rate_limits partial (5h only, no resets_at)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const input =
        \\{"rate_limits":{"five_hour":{"used_percentage":10.0}}}
    ;
    const info = parseStdin(arena.allocator(), input);

    try std.testing.expect(info.rate_limit_5h != null);
    try std.testing.expectApproxEqAbs(@as(f64, 10.0), info.rate_limit_5h.?.used_percentage, 1e-10);
    try std.testing.expectEqual(@as(?i64, null), info.rate_limit_5h.?.resets_at_ms);
    try std.testing.expectEqual(@as(?RateLimitWindow, null), info.rate_limit_7d);
}

test "parseStdin no rate_limits" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const input =
        \\{"model":{"id":"claude-opus-4-6","display_name":"Opus"}}
    ;
    const info = parseStdin(arena.allocator(), input);
    try std.testing.expectEqual(@as(?RateLimitWindow, null), info.rate_limit_5h);
    try std.testing.expectEqual(@as(?RateLimitWindow, null), info.rate_limit_7d);
}

test "parseJsonlContent global dedup across files" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var global_seen = std.StringHashMapUnmanaged(void){};

    const line =
        \\{"timestamp":"2025-06-15T10:00:00Z","message":{"id":"msg_001","model":"claude-sonnet-4-5-20250929","usage":{"input_tokens":1000,"output_tokens":500}},"requestId":"req_001"}
    ;

    var entries1: std.ArrayListUnmanaged(TranscriptEntry) = .{};
    parseJsonlContent(alloc, alloc, line, &entries1, &global_seen);
    try std.testing.expectEqual(@as(usize, 1), entries1.items.len);

    var entries2: std.ArrayListUnmanaged(TranscriptEntry) = .{};
    parseJsonlContent(alloc, alloc, line, &entries2, &global_seen);
    try std.testing.expectEqual(@as(usize, 0), entries2.items.len);
}

test "parseJsonlContent per-file dedup still works" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var seen = std.StringHashMapUnmanaged(void){};

    const content =
        \\{"timestamp":"2025-06-15T10:00:00Z","message":{"id":"msg_001","model":"claude-sonnet-4-5-20250929","usage":{"input_tokens":1000,"output_tokens":500}},"requestId":"req_001"}
        \\
        \\{"timestamp":"2025-06-15T10:00:00Z","message":{"id":"msg_001","model":"claude-sonnet-4-5-20250929","usage":{"input_tokens":1000,"output_tokens":500}},"requestId":"req_001"}
    ;

    var entries: std.ArrayListUnmanaged(TranscriptEntry) = .{};
    parseJsonlContent(alloc, alloc, content, &entries, &seen);
    try std.testing.expectEqual(@as(usize, 1), entries.items.len);
}

test "parseJsonlContent no dedup without ids" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var seen = std.StringHashMapUnmanaged(void){};

    const content =
        \\{"timestamp":"2025-06-15T10:00:00Z","message":{"model":"claude-sonnet-4-5-20250929","usage":{"input_tokens":1000,"output_tokens":500}}}
        \\
        \\{"timestamp":"2025-06-15T10:00:00Z","message":{"model":"claude-sonnet-4-5-20250929","usage":{"input_tokens":1000,"output_tokens":500}}}
    ;

    var entries: std.ArrayListUnmanaged(TranscriptEntry) = .{};
    parseJsonlContent(alloc, alloc, content, &entries, &seen);
    try std.testing.expectEqual(@as(usize, 2), entries.items.len);
}

test "cache roundtrip with block" {
    const Writer = std.io.Writer;
    var aw: Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();

    const scan = ScanResult{
        .today_cost = 12.345,
        .block = .{
            .start_ms = 1000000,
            .end_ms = 19000000,
            .cost = 5.67,
            .burn_rate_per_hr = 1.23,
        },
    };
    const files = [_]CachedFileEntry{
        .{ .path = "/tmp/test/file1.jsonl", .file_size = 4096, .per_file_cost = 3.21, .parsed_size = 4096 },
        .{ .path = "/tmp/test/file2.jsonl", .file_size = 8192, .per_file_cost = 9.12, .parsed_size = 8000 },
    };
    const now_s: i64 = 1700000000;
    const last_full_scan_s: i64 = 1699999900;
    const day_start_ms: i64 = 1699920000000;

    try serializeCacheBytes(&aw.writer, scan, &files, now_s, last_full_scan_s, day_start_ms);

    const result = parseCacheBytes(std.testing.allocator, aw.writer.buffered(), day_start_ms) orelse
        return error.TestUnexpectedResult;
    defer {
        for (result.files) |f| std.testing.allocator.free(f.path);
        std.testing.allocator.free(result.files);
    }

    try std.testing.expectEqual(now_s, result.write_time_s);
    try std.testing.expectEqual(last_full_scan_s, result.last_full_scan_s);
    try std.testing.expectEqual(day_start_ms, result.day_start_ms);
    try std.testing.expectApproxEqAbs(@as(f64, 12.345), result.scan.today_cost, 1e-10);

    const block = result.scan.block orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(i64, 1000000), block.start_ms);
    try std.testing.expectEqual(@as(i64, 19000000), block.end_ms);
    try std.testing.expectApproxEqAbs(@as(f64, 5.67), block.cost, 1e-10);
    try std.testing.expectApproxEqAbs(@as(f64, 1.23), block.burn_rate_per_hr, 1e-10);

    try std.testing.expectEqual(@as(usize, 2), result.files.len);
    try std.testing.expectEqualStrings("/tmp/test/file1.jsonl", result.files[0].path);
    try std.testing.expectEqual(@as(i64, 4096), result.files[0].file_size);
    try std.testing.expectApproxEqAbs(@as(f64, 3.21), result.files[0].per_file_cost, 1e-10);
    try std.testing.expectEqual(@as(i64, 4096), result.files[0].parsed_size);
    try std.testing.expectEqualStrings("/tmp/test/file2.jsonl", result.files[1].path);
    try std.testing.expectEqual(@as(i64, 8192), result.files[1].file_size);
    try std.testing.expectEqual(@as(i64, 8000), result.files[1].parsed_size);
}

test "cache roundtrip without block" {
    const Writer = std.io.Writer;
    var aw: Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();

    const scan = ScanResult{ .today_cost = 0.50 };
    const files = [_]CachedFileEntry{};
    const day_start_ms: i64 = 1699920000000;

    try serializeCacheBytes(&aw.writer, scan, &files, 100, 100, day_start_ms);

    const result = parseCacheBytes(std.testing.allocator, aw.writer.buffered(), day_start_ms) orelse
        return error.TestUnexpectedResult;
    defer std.testing.allocator.free(result.files);

    try std.testing.expectApproxEqAbs(@as(f64, 0.50), result.scan.today_cost, 1e-10);
    try std.testing.expectEqual(@as(?BlockInfo, null), result.scan.block);
    try std.testing.expectEqual(@as(usize, 0), result.files.len);
}

test "cache day boundary invalidation" {
    const Writer = std.io.Writer;
    var aw: Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();

    const day_start_ms: i64 = 1699920000000;
    try serializeCacheBytes(&aw.writer, ScanResult{}, &.{}, 100, 100, day_start_ms);

    // Different day_start_ms should return null
    const different_day: i64 = day_start_ms + 86400 * 1000;
    try std.testing.expectEqual(@as(?CacheResult, null), parseCacheBytes(std.testing.allocator, aw.writer.buffered(), different_day));
}

test "cache invalid magic" {
    var data: [cache_header_size]u8 = .{0} ** cache_header_size;
    @memcpy(data[0..4], "NOPE");
    try std.testing.expectEqual(@as(?CacheResult, null), parseCacheBytes(std.testing.allocator, &data, 0));
}

test "cache too short" {
    const data = [_]u8{ 'C', 'C', 'S', 'L' };
    try std.testing.expectEqual(@as(?CacheResult, null), parseCacheBytes(std.testing.allocator, &data, 0));
}

test {
    _ = output;
}
