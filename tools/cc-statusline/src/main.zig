const std = @import("std");
const json = std.json;
const mem = std.mem;
const fs = std.fs;
const ctime = @cImport({
    @cInclude("time.h");
});

// ============================================================
// Constants
// ============================================================

const cache_path = "/tmp/cc-statusline-cache.bin";
const cache_ttl_s: i64 = 30;
const block_duration_ms: i64 = 5 * 60 * 60 * 1000;
const scan_window_ms: i64 = 10 * 60 * 60 * 1000;
const token_200k: i64 = 200_000;

const cache_magic = [4]u8{ 'C', 'C', 'S', 'L' };
const cache_ver: u32 = 1;

// ANSI
const ansi = struct {
    const green = "\x1b[32m";
    const yellow = "\x1b[33m";
    const red = "\x1b[31m";
    const reset = "\x1b[0m";
};

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
};

const ScanResult = struct {
    today_cost: f64 = 0,
    block: ?BlockInfo = null,
    max_mtime_s: i64 = 0,
};

const CacheData = extern struct {
    magic: [4]u8,
    version: u32,
    write_time_s: i64,
    max_mtime_s: i64,
    today_cost: f64,
    has_block: u8,
    block_start_ms: i64,
    block_end_ms: i64,
    block_cost: f64,
    block_burn_rate: f64,
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
    .{ .prefix = "claude-opus-4-6", .input = 5e-6, .output = 25e-6, .cache_creation = 6.25e-6, .cache_read = 5e-7 },
    // Opus 4.5
    .{ .prefix = "claude-opus-4-5", .input = 5e-6, .output = 25e-6, .cache_creation = 6.25e-6, .cache_read = 5e-7 },
    // Opus 4.1
    .{ .prefix = "claude-opus-4-1", .input = 15e-6, .output = 75e-6, .cache_creation = 18.75e-6, .cache_read = 1.5e-6 },
    // Opus 4 (Claude 3 Opus)
    .{ .prefix = "claude-3-opus", .input = 15e-6, .output = 75e-6, .cache_creation = 18.75e-6, .cache_read = 1.5e-6 },
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
    .{ .prefix = "claude-3-5-haiku", .input = 1e-6, .output = 5e-6, .cache_creation = 1.25e-6, .cache_read = 1e-7 },
};

fn findPricing(model: []const u8) ?ModelPricing {
    for (&pricing_table) |p| {
        if (mem.startsWith(u8, model, p.prefix)) return p;
    }
    return null;
}

fn calcTokenCost(tokens: i64, base_rate: f64, above_rate: ?f64) f64 {
    if (tokens <= 0) return 0;
    const t: f64 = @floatFromInt(tokens);
    if (above_rate) |ar| {
        if (tokens > token_200k) {
            const base_t: f64 = @floatFromInt(token_200k);
            return base_t * base_rate + (t - base_t) * ar;
        }
    }
    return t * base_rate;
}

fn calculateEntryCost(pricing: ModelPricing, usage: TokenUsage) f64 {
    return calcTokenCost(usage.input_tokens, pricing.input, pricing.input_above_200k) +
        calcTokenCost(usage.output_tokens, pricing.output, pricing.output_above_200k) +
        calcTokenCost(usage.cache_creation_input_tokens, pricing.cache_creation, pricing.cache_creation_above_200k) +
        calcTokenCost(usage.cache_read_input_tokens, pricing.cache_read, pricing.cache_read_above_200k);
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

/// Get the start of today in milliseconds (local timezone)
fn getLocalDayStartMs(now_ms: i64) i64 {
    const now_s = @divFloor(now_ms, @as(i64, 1000));
    const ct: ctime.time_t = @intCast(now_s);
    var tm: ctime.struct_tm = undefined;
    _ = ctime.localtime_r(&ct, &tm);
    var midnight_tm = tm;
    midnight_tm.tm_hour = 0;
    midnight_tm.tm_min = 0;
    midnight_tm.tm_sec = 0;
    const midnight_s = ctime.mktime(&midnight_tm);
    return @as(i64, midnight_s) * 1000;
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
            if (cost.get("total_duration_ms")) |dur| {
                if (getF64(dur)) |d| info.session_duration_ms = @as(i64, @intFromFloat(d));
            }
            if (cost.get("total_lines_added")) |la| info.lines_added = getI64(la);
            if (cost.get("total_lines_removed")) |lr| info.lines_removed = getI64(lr);
        }
    }
    if (root.get("context_window")) |v| {
        if (getObj(v)) |ctx| {
            if (ctx.get("total_input_tokens")) |t| {
                if (getF64(t)) |tv| info.context_tokens = @as(i64, @intFromFloat(tv));
            }
            if (ctx.get("used_percentage")) |pct| info.context_pct = getF64(pct);
        }
    }
    if (root.get("session_id")) |v| info.session_id = getStr(v);
    if (root.get("transcript_path")) |v| info.transcript_path = getStr(v);
    return info;
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

fn collectTranscriptFiles(allocator: std.mem.Allocator, projects_path: []const u8, now_ms: i64) struct { files: [][]const u8, max_mtime_s: i64 } {
    var files: std.ArrayListUnmanaged([]const u8) = .{};
    var max_mtime_s: i64 = 0;
    const cutoff_ms = now_ms - scan_window_ms;

    var projects_dir = fs.openDirAbsolute(projects_path, .{ .iterate = true }) catch
        return .{ .files = files.toOwnedSlice(allocator) catch &.{}, .max_mtime_s = 0 };
    defer projects_dir.close();

    var proj_it = projects_dir.iterate();
    while (proj_it.next() catch null) |proj_entry| {
        if (proj_entry.kind != .directory) continue;
        const proj_name = allocator.dupe(u8, proj_entry.name) catch continue;
        scanDirRecursive(allocator, projects_path, proj_name, &files, &max_mtime_s, cutoff_ms);
    }

    return .{
        .files = files.toOwnedSlice(allocator) catch &.{},
        .max_mtime_s = max_mtime_s,
    };
}

fn scanDirRecursive(allocator: std.mem.Allocator, base_path: []const u8, rel_path: []const u8, files: *std.ArrayListUnmanaged([]const u8), max_mtime_s: *i64, cutoff_ms: i64) void {
    const full_path = std.fmt.allocPrint(allocator, "{s}/{s}", .{ base_path, rel_path }) catch return;
    var dir = fs.openDirAbsolute(full_path, .{ .iterate = true }) catch return;
    defer dir.close();

    var it = dir.iterate();
    while (it.next() catch null) |entry| {
        if (entry.kind == .directory) {
            const sub_rel = std.fmt.allocPrint(allocator, "{s}/{s}", .{ rel_path, entry.name }) catch continue;
            scanDirRecursive(allocator, base_path, sub_rel, files, max_mtime_s, cutoff_ms);
        } else if (entry.kind == .file and mem.endsWith(u8, entry.name, ".jsonl")) {
            const stat = dir.statFile(entry.name) catch continue;

            const mtime_s: i64 = @intCast(@divFloor(stat.mtime, std.time.ns_per_s));
            const mtime_ms: i64 = @intCast(@divFloor(stat.mtime, std.time.ns_per_ms));
            if (mtime_s > max_mtime_s.*) max_mtime_s.* = mtime_s;
            if (mtime_ms < cutoff_ms) continue;

            const abs_path = std.fmt.allocPrint(allocator, "{s}/{s}", .{ full_path, entry.name }) catch continue;
            files.append(allocator, abs_path) catch continue;
        }
    }
}

fn parseTranscriptFiles(allocator: std.mem.Allocator, files: []const []const u8) []TranscriptEntry {
    var entries: std.ArrayListUnmanaged(TranscriptEntry) = .{};
    var seen = std.StringHashMapUnmanaged(void){};

    for (files) |file_path| {
        var f = fs.openFileAbsolute(file_path, .{}) catch continue;
        defer f.close();
        const content = f.readToEndAlloc(allocator, 100 * 1024 * 1024) catch continue;

        parseJsonlContent(allocator, content, &entries, &seen);
    }

    return entries.toOwnedSlice(allocator) catch &.{};
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

fn computeCosts(entries: []TranscriptEntry, now_ms: i64) ScanResult {
    const today_start_ms = getLocalDayStartMs(now_ms);
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

fn readCache(now_s: i64, max_mtime_s: i64) ?ScanResult {
    var f = fs.openFileAbsolute(cache_path, .{}) catch return null;
    defer f.close();
    const content = f.readToEndAlloc(std.heap.page_allocator, 256) catch return null;

    if (content.len < @sizeOf(CacheData)) return null;

    var data: CacheData = undefined;
    @memcpy(mem.asBytes(&data), content[0..@sizeOf(CacheData)]);

    if (!mem.eql(u8, &data.magic, &cache_magic)) return null;
    if (data.version != cache_ver) return null;
    if (now_s - data.write_time_s > cache_ttl_s) return null;
    if (data.max_mtime_s != max_mtime_s) return null;

    var result = ScanResult{
        .today_cost = data.today_cost,
        .block = null,
        .max_mtime_s = data.max_mtime_s,
    };
    if (data.has_block != 0) {
        result.block = .{
            .start_ms = data.block_start_ms,
            .end_ms = data.block_end_ms,
            .cost = data.block_cost,
            .burn_rate_per_hr = data.block_burn_rate,
        };
    }
    return result;
}

fn writeCache(result: ScanResult, now_s: i64) void {
    const data = CacheData{
        .magic = cache_magic,
        .version = cache_ver,
        .write_time_s = now_s,
        .max_mtime_s = result.max_mtime_s,
        .today_cost = result.today_cost,
        .has_block = if (result.block != null) 1 else 0,
        .block_start_ms = if (result.block) |b| b.start_ms else 0,
        .block_end_ms = if (result.block) |b| b.end_ms else 0,
        .block_cost = if (result.block) |b| b.cost else 0,
        .block_burn_rate = if (result.block) |b| b.burn_rate_per_hr else 0,
    };
    const bytes = mem.asBytes(&data);
    const tmp_path = cache_path ++ ".tmp";
    var f = fs.createFileAbsolute(tmp_path, .{}) catch return;
    defer f.close();
    var wbuf: [128]u8 = undefined;
    var w = f.writer(&wbuf);
    w.interface.writeAll(bytes) catch return;
    w.interface.flush() catch return;
    fs.renameAbsolute(tmp_path, cache_path) catch {};
}

// ============================================================
// Output
// ============================================================

fn formatCurrency(buf: []u8, value: f64) []const u8 {
    if (value > 0 and value < 0.01) {
        return std.fmt.bufPrint(buf, "${d:.4}", .{value}) catch "$?.??";
    }
    return std.fmt.bufPrint(buf, "${d:.2}", .{value}) catch "$?.??";
}

fn contextColor(pct: f64) []const u8 {
    if (pct < 50.0) return ansi.green;
    if (pct < 75.0) return ansi.yellow;
    return ansi.red;
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

fn printOutput(stdin_info: StdinInfo, scan: ?ScanResult) !void {
    const stdout = fs.File{ .handle = std.posix.STDOUT_FILENO };
    var buf: [4096]u8 = undefined;
    var writer = stdout.writer(&buf);
    const w = &writer.interface;

    // Model
    const model_name = stdin_info.model_name orelse "Unknown";
    try w.print("\xf0\x9f\xa4\x96 {s}", .{model_name});

    // Session cost
    var cost_buf: [32]u8 = undefined;
    const session_str = if (stdin_info.session_cost) |c| formatCurrency(&cost_buf, c) else "N/A";
    try w.print(" | \xf0\x9f\x92\xb0 {s} session", .{session_str});

    // Today cost
    var today_buf: [32]u8 = undefined;
    if (scan) |s| {
        try w.print(" / {s} today", .{formatCurrency(&today_buf, s.today_cost)});
    } else {
        try w.writeAll(" / N/A today");
    }

    // Block info
    if (scan) |s| {
        if (s.block) |block| {
            var block_buf: [32]u8 = undefined;
            var dur_buf: [64]u8 = undefined;
            const now_ms = std.time.milliTimestamp();
            const remaining = block.end_ms - now_ms;
            try w.print(" / {s} block ({s})", .{
                formatCurrency(&block_buf, block.cost),
                formatDuration(&dur_buf, remaining),
            });
            var rate_buf: [32]u8 = undefined;
            try w.print(" | \xf0\x9f\x94\xa5 {s}/hr", .{formatCurrency(&rate_buf, block.burn_rate_per_hr)});
        } else {
            try w.writeAll(" / N/A block");
        }
    } else {
        try w.writeAll(" / N/A block");
    }

    // Context
    if (stdin_info.context_pct) |pct| {
        const color = contextColor(pct);
        if (stdin_info.context_tokens) |tokens| {
            var tok_buf: [32]u8 = undefined;
            try w.print(" | \xf0\x9f\xa7\xa0 {s} {s}({d:.0}%){s}", .{ formatIntComma(&tok_buf, tokens), color, pct, ansi.reset });
        } else {
            try w.print(" | \xf0\x9f\xa7\xa0 {s}{d:.0}%{s}", .{ color, pct, ansi.reset });
        }
    } else if (stdin_info.context_tokens) |tokens| {
        var tok_buf: [32]u8 = undefined;
        try w.print(" | \xf0\x9f\xa7\xa0 {s}", .{formatIntComma(&tok_buf, tokens)});
    } else {
        try w.writeAll(" | \xf0\x9f\xa7\xa0 N/A");
    }

    // Lines changed
    if (stdin_info.lines_added != null or stdin_info.lines_removed != null) {
        const added = stdin_info.lines_added orelse 0;
        const removed = stdin_info.lines_removed orelse 0;
        try w.print(" | \xf0\x9f\x93\x9d {s}+{d}{s} {s}-{d}{s}", .{ ansi.green, added, ansi.reset, ansi.red, removed, ansi.reset });
    }

    // Session duration
    if (stdin_info.session_duration_ms) |dur_ms| {
        var dur_sec = @divFloor(dur_ms, @as(i64, 1000));
        const hours = @divFloor(dur_sec, @as(i64, 3600));
        dur_sec -= hours * 3600;
        const mins = @divFloor(dur_sec, @as(i64, 60));
        const secs = dur_sec - mins * 60;
        if (hours > 0) {
            try w.print(" | \xf0\x9f\x95\x90 {d}h {d}m {d}s", .{ hours, mins, secs });
        } else {
            try w.print(" | \xf0\x9f\x95\x90 {d}m {d}s", .{ mins, secs });
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
    w.writeAll("\xf0\x9f\xa4\x96 Unknown | \xf0\x9f\x92\xb0 N/A session / N/A today / N/A block | \xf0\x9f\xa7\xa0 N/A\n") catch {};
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

    // Read stdin
    const stdin = fs.File{ .handle = std.posix.STDIN_FILENO };
    const stdin_data = stdin.readToEndAlloc(allocator, 1024 * 1024) catch "";

    // Parse stdin JSON
    const stdin_info = parseStdin(allocator, stdin_data);

    // Scan transcripts (or use cache)
    const scan: ?ScanResult = blk: {
        const config_dir = getConfigDir(allocator) catch break :blk null;
        const projects_path = std.fmt.allocPrint(allocator, "{s}/projects", .{config_dir}) catch break :blk null;
        const now_ms = std.time.milliTimestamp();
        const now_s = @divFloor(now_ms, @as(i64, 1000));

        // Phase 1: collect file info + max mtime (fast)
        const file_info = collectTranscriptFiles(allocator, projects_path, now_ms);

        // Check cache
        if (readCache(now_s, file_info.max_mtime_s)) |cached| {
            break :blk cached;
        }

        // Phase 2: parse files (slow, only on cache miss)
        const entries = parseTranscriptFiles(allocator, file_info.files);
        var result = computeCosts(entries, now_ms);
        result.max_mtime_s = file_info.max_mtime_s;

        // Write cache
        writeCache(result, now_s);

        break :blk result;
    };

    try printOutput(stdin_info, scan);
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
    // input: 200000 * 3e-6 + 50000 * 6e-6 = 0.6 + 0.3 = 0.9
    // output: 100 * 15e-6 = 0.0015
    try std.testing.expectApproxEqAbs(@as(f64, 0.9015), cost, 1e-10);
}
