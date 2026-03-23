const std = @import("std");
const mem = std.mem;
const fs = std.fs;

// ============================================================
// ISO 8601 Parser
// ============================================================

pub fn parseIso8601ToMs(s: []const u8) ?i64 {
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
pub fn daysFromCivil(year_in: i32, month_in: u8, day_in: u8) i64 {
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

pub fn computeLocalDayStartMs(now_ms: i64, utc_offset_s: i32) i64 {
    const now_s = @divFloor(now_ms, @as(i64, 1000));
    const offset_s: i64 = @intCast(utc_offset_s);
    const local_s = now_s + offset_s;
    const local_day_start_s = @divFloor(local_s, @as(i64, 86400)) * 86400;
    return (local_day_start_s - offset_s) * 1000;
}

/// Get the start of today in milliseconds (local timezone, pure Zig)
pub fn getLocalDayStartMs(allocator: std.mem.Allocator, now_ms: i64) i64 {
    const now_s = @divFloor(now_ms, @as(i64, 1000));
    const offset_s = getUtcOffsetSeconds(allocator, now_s);
    return computeLocalDayStartMs(now_ms, offset_s);
}

pub fn floorToHourMs(ms: i64) i64 {
    const ms_per_hour: i64 = 3600 * 1000;
    return @divFloor(ms, ms_per_hour) * ms_per_hour;
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

// --- computeLocalDayStartMs ---

test "computeLocalDayStartMs UTC" {
    // 2025-06-15T12:30:00Z
    const now_ms: i64 = (daysFromCivil(2025, 6, 15) * 86400 + 12 * 3600 + 30 * 60) * 1000;
    const day_start = computeLocalDayStartMs(now_ms, 0);
    // Should be 2025-06-15T00:00:00Z
    const expected: i64 = daysFromCivil(2025, 6, 15) * 86400 * 1000;
    try std.testing.expectEqual(expected, day_start);
}

test "computeLocalDayStartMs JST +9h" {
    // 2025-06-15T02:00:00Z = 2025-06-15T11:00:00 JST
    const now_ms: i64 = (daysFromCivil(2025, 6, 15) * 86400 + 2 * 3600) * 1000;
    const day_start = computeLocalDayStartMs(now_ms, 32400); // +9h
    // JST day start = 2025-06-15T00:00:00 JST = 2025-06-14T15:00:00Z
    const expected: i64 = (daysFromCivil(2025, 6, 14) * 86400 + 15 * 3600) * 1000;
    try std.testing.expectEqual(expected, day_start);
}

test "computeLocalDayStartMs EST -5h" {
    // 2025-06-15T03:00:00Z = 2025-06-14T22:00:00 EST
    const now_ms: i64 = (daysFromCivil(2025, 6, 15) * 86400 + 3 * 3600) * 1000;
    const day_start = computeLocalDayStartMs(now_ms, -18000); // -5h
    // EST day start = 2025-06-14T00:00:00 EST = 2025-06-14T05:00:00Z
    const expected: i64 = (daysFromCivil(2025, 6, 14) * 86400 + 5 * 3600) * 1000;
    try std.testing.expectEqual(expected, day_start);
}

test "computeLocalDayStartMs result is multiple of 1000" {
    const now_ms: i64 = (daysFromCivil(2025, 6, 15) * 86400 + 12 * 3600) * 1000 + 500;
    const day_start = computeLocalDayStartMs(now_ms, 32400);
    try std.testing.expectEqual(@as(i64, 0), @mod(day_start, 1000));
}

// --- parseTzif v1 ---

test "parseTzif v1 format" {
    const header_size = 44;
    var data: [header_size + 10]u8 = .{0} ** (header_size + 10);
    @memcpy(data[0..4], "TZif");
    data[4] = 0; // v1 (not '2' or '3')
    // typecnt = 1
    std.mem.writeInt(u32, data[36..40], 1, .big);
    // charcnt = 4
    std.mem.writeInt(u32, data[40..44], 4, .big);
    // timecnt = 0, so no transitions

    // Type entry: offset = 3600 (UTC+1), dst=0, abbr_idx=0
    std.mem.writeInt(u32, data[44..48], @bitCast(@as(i32, 3600)), .big);
    data[48] = 0; // dst flag
    data[49] = 0; // abbr index
    // Abbreviation
    @memcpy(data[50..54], "CET\x00");

    const offset = parseTzif(&data, 1700000000);
    try std.testing.expect(offset != null);
    try std.testing.expectEqual(@as(i32, 3600), offset.?);
}

// --- parseTzifData with transitions ---

test "parseTzifData with transition table" {
    // Build a v1-style data block with 2 transitions and 2 types
    // Type 0: offset=0 (UTC), non-DST
    // Type 1: offset=3600 (UTC+1), DST
    // Transition at t=1000 -> type 1, transition at t=2000 -> type 0

    var data: [128]u8 = .{0} ** 128;
    const timecnt: u32 = 2;
    const typecnt: u32 = 2;

    // Transition times (4 bytes each, big-endian, 32-bit)
    std.mem.writeInt(u32, data[0..4], @bitCast(@as(i32, 1000)), .big);
    std.mem.writeInt(u32, data[4..8], @bitCast(@as(i32, 2000)), .big);

    // Type indices (1 byte each)
    data[8] = 1; // transition at 1000 -> type 1
    data[9] = 0; // transition at 2000 -> type 0

    // Type entries (6 bytes each): offset(4) + dst(1) + abbr_idx(1)
    // Type 0: offset=0
    std.mem.writeInt(u32, data[10..14], 0, .big);
    data[14] = 0;
    data[15] = 0;
    // Type 1: offset=3600
    std.mem.writeInt(u32, data[16..20], @bitCast(@as(i32, 3600)), .big);
    data[20] = 1;
    data[21] = 0;

    // Before all transitions: should use first non-DST type (type 0)
    try std.testing.expectEqual(@as(?i32, 0), parseTzifData(&data, timecnt, typecnt, 500, false));

    // Between transitions: after t=1000, type 1
    try std.testing.expectEqual(@as(?i32, 3600), parseTzifData(&data, timecnt, typecnt, 1500, false));

    // After all transitions: after t=2000, type 0
    try std.testing.expectEqual(@as(?i32, 0), parseTzifData(&data, timecnt, typecnt, 3000, false));
}

// --- findFirstNonDstType ---

test "findFirstNonDstType first type is non-DST" {
    const types = [_]u8{
        0x00, 0x0e, 0x10, 0x00, // utoff (big-endian)
        0, // dst = 0 (non-DST)
        0, // idx
    };
    try std.testing.expectEqual(@as(u8, 0), findFirstNonDstType(&types, 1));
}

test "findFirstNonDstType all DST returns 0" {
    const types = [_]u8{
        0, 0, 0, 0, 1, 0, // type 0: dst=1
        0, 0, 0, 0, 1, 0, // type 1: dst=1
    };
    try std.testing.expectEqual(@as(u8, 0), findFirstNonDstType(&types, 2));
}

test "findFirstNonDstType third type is first non-DST" {
    const types = [_]u8{
        0, 0, 0, 0, 1, 0, // type 0: dst=1
        0, 0, 0, 0, 1, 0, // type 1: dst=1
        0, 0, 0, 0, 0, 0, // type 2: dst=0
    };
    try std.testing.expectEqual(@as(u8, 2), findFirstNonDstType(&types, 3));
}

// --- parseIso8601ToMs edge cases ---

test "parseIso8601ToMs lowercase t separator" {
    const ts = parseIso8601ToMs("2025-01-15t10:30:00Z").?;
    const expected: i64 = (daysFromCivil(2025, 1, 15) * 86400 + 10 * 3600 + 30 * 60) * 1000;
    try std.testing.expectEqual(expected, ts);
}

test "parseIso8601ToMs milliseconds 1 digit" {
    const ts = parseIso8601ToMs("2025-01-15T00:00:00.1Z").?;
    const base: i64 = daysFromCivil(2025, 1, 15) * 86400 * 1000;
    try std.testing.expectEqual(base + 100, ts);
}

test "parseIso8601ToMs milliseconds 2 digits" {
    const ts = parseIso8601ToMs("2025-01-15T00:00:00.12Z").?;
    const base: i64 = daysFromCivil(2025, 1, 15) * 86400 * 1000;
    try std.testing.expectEqual(base + 120, ts);
}

test "parseIso8601ToMs milliseconds 4+ digits truncated" {
    const ts = parseIso8601ToMs("2025-01-15T00:00:00.1234Z").?;
    const base: i64 = daysFromCivil(2025, 1, 15) * 86400 * 1000;
    try std.testing.expectEqual(base + 123, ts);
}

test "parseIso8601ToMs leap year Feb 29" {
    const ts = parseIso8601ToMs("2024-02-29T00:00:00Z").?;
    const expected: i64 = daysFromCivil(2024, 2, 29) * 86400 * 1000;
    try std.testing.expectEqual(expected, ts);
}

// --- daysFromCivil edge cases ---

test "daysFromCivil leap year" {
    const feb28 = daysFromCivil(2024, 2, 28);
    const feb29 = daysFromCivil(2024, 2, 29);
    const mar1 = daysFromCivil(2024, 3, 1);
    try std.testing.expectEqual(feb28 + 1, feb29);
    try std.testing.expectEqual(feb29 + 1, mar1);
}

test "daysFromCivil non-leap year Feb 28 to Mar 1" {
    const feb28 = daysFromCivil(2025, 2, 28);
    const mar1 = daysFromCivil(2025, 3, 1);
    try std.testing.expectEqual(feb28 + 1, mar1);
}

test "daysFromCivil pre-epoch" {
    const day = daysFromCivil(1969, 12, 31);
    try std.testing.expectEqual(@as(i64, -1), day);
}

test "daysFromCivil year boundary Dec 31 to Jan 1" {
    const dec31 = daysFromCivil(2024, 12, 31);
    const jan1 = daysFromCivil(2025, 1, 1);
    try std.testing.expectEqual(dec31 + 1, jan1);
}

// --- floorToHourMs edge cases ---

test "floorToHourMs negative timestamp" {
    try std.testing.expectEqual(@as(i64, -3600000), floorToHourMs(-1));
}

test "floorToHourMs exactly on hour boundary" {
    try std.testing.expectEqual(@as(i64, 3600000), floorToHourMs(3600000));
}

test "floorToHourMs negative exactly on hour" {
    try std.testing.expectEqual(@as(i64, -3600000), floorToHourMs(-3600000));
}
