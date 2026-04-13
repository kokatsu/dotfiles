const std = @import("std");
const json = std.json;

pub fn getObj(val: json.Value) ?json.ObjectMap {
    return switch (val) {
        .object => |o| o,
        else => null,
    };
}

pub fn getObjField(obj: json.ObjectMap, key: []const u8) ?json.ObjectMap {
    return if (obj.get(key)) |v| getObj(v) else null;
}

pub fn getStr(val: json.Value) ?[]const u8 {
    return switch (val) {
        .string => |s| s,
        else => null,
    };
}

test "getObj returns object" {
    const parsed = try json.parseFromSlice(json.Value, std.testing.allocator, "{\"a\":1}", .{});
    defer parsed.deinit();
    try std.testing.expect(getObj(parsed.value) != null);
}

test "getStr returns string" {
    try std.testing.expectEqualStrings("hello", getStr(.{ .string = "hello" }).?);
}

test "getStr returns null for non-string" {
    try std.testing.expect(getStr(.{ .integer = 42 }) == null);
}
