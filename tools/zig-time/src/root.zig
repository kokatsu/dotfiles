const std = @import("std");
const mem = std.mem;
const fs = std.fs;

// ============================================================
// TZif parser (pure Zig, no libc dependency)
// ============================================================

/// Resolve the current UTC offset in seconds for the given epoch timestamp.
/// Reads the TZ environment variable and parses TZif binary data.
/// Falls back to /etc/localtime, then UTC (0) if nothing works.
pub fn getUtcOffsetSeconds(allocator: std.mem.Allocator, now_s: i64) i32 {
    if (std.posix.getenv("TZ")) |tz_raw| {
        const tz = if (tz_raw.len > 0 and tz_raw[0] == ':') tz_raw[1..] else tz_raw;
        if (tz.len == 0 or mem.eql(u8, tz, "UTC") or mem.eql(u8, tz, "UTC0")) return 0;

        if (tz.len > 0 and tz[0] == '/') {
            if (readTzifOffset(allocator, tz, now_s)) |off| return off;
        }

        var buf: [256]u8 = undefined;
        const path = std.fmt.bufPrint(&buf, "/usr/share/zoneinfo/{s}", .{tz}) catch null;
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
// Tests
// ============================================================

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

test "parseTzif v1 format" {
    const header_size = 44;
    var data: [header_size + 10]u8 = .{0} ** (header_size + 10);
    @memcpy(data[0..4], "TZif");
    data[4] = 0;
    std.mem.writeInt(u32, data[36..40], 1, .big);
    std.mem.writeInt(u32, data[40..44], 4, .big);

    std.mem.writeInt(u32, data[44..48], @bitCast(@as(i32, 3600)), .big);
    data[48] = 0;
    data[49] = 0;
    @memcpy(data[50..54], "CET\x00");

    const offset = parseTzif(&data, 1700000000);
    try std.testing.expect(offset != null);
    try std.testing.expectEqual(@as(i32, 3600), offset.?);
}

test "parseTzifData with transition table" {
    var data: [128]u8 = .{0} ** 128;
    const timecnt: u32 = 2;
    const typecnt: u32 = 2;

    std.mem.writeInt(u32, data[0..4], @bitCast(@as(i32, 1000)), .big);
    std.mem.writeInt(u32, data[4..8], @bitCast(@as(i32, 2000)), .big);

    data[8] = 1;
    data[9] = 0;

    std.mem.writeInt(u32, data[10..14], 0, .big);
    data[14] = 0;
    data[15] = 0;
    std.mem.writeInt(u32, data[16..20], @bitCast(@as(i32, 3600)), .big);
    data[20] = 1;
    data[21] = 0;

    try std.testing.expectEqual(@as(?i32, 0), parseTzifData(&data, timecnt, typecnt, 500, false));
    try std.testing.expectEqual(@as(?i32, 3600), parseTzifData(&data, timecnt, typecnt, 1500, false));
    try std.testing.expectEqual(@as(?i32, 0), parseTzifData(&data, timecnt, typecnt, 3000, false));
}

test "findFirstNonDstType first type is non-DST" {
    const types = [_]u8{ 0x00, 0x0e, 0x10, 0x00, 0, 0 };
    try std.testing.expectEqual(@as(u8, 0), findFirstNonDstType(&types, 1));
}

test "findFirstNonDstType all DST returns 0" {
    const types = [_]u8{ 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0 };
    try std.testing.expectEqual(@as(u8, 0), findFirstNonDstType(&types, 2));
}

test "findFirstNonDstType third type is first non-DST" {
    const types = [_]u8{ 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0 };
    try std.testing.expectEqual(@as(u8, 2), findFirstNonDstType(&types, 3));
}
