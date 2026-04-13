const std = @import("std");
const cargo_test = @import("filters/cargo_test.zig");
const rspec = @import("filters/rspec.zig");
const bun_test = @import("filters/bun_test.zig");
const jest = @import("filters/jest.zig");

const MAX_INPUT: usize = 16 * 1024 * 1024;

pub fn run(allocator: std.mem.Allocator, kind: []const u8) !void {
    var stdin_file = std.fs.File.stdin();
    var buf: [8192]u8 = undefined;
    var reader = stdin_file.reader(&buf);
    var data = std.ArrayList(u8){};
    defer data.deinit(allocator);
    reader.interface.appendRemaining(allocator, &data, .limited(MAX_INPUT)) catch {};

    const out = try filter(allocator, kind, data.items);
    defer allocator.free(out);
    try std.fs.File.stdout().writeAll(out);
}

pub fn filter(allocator: std.mem.Allocator, kind: []const u8, input: []const u8) ![]u8 {
    if (std.mem.eql(u8, kind, "cargo-test")) return cargo_test.filter(allocator, input);
    if (std.mem.eql(u8, kind, "rspec")) return rspec.filter(allocator, input);
    if (std.mem.eql(u8, kind, "bun-test")) return bun_test.filter(allocator, input);
    if (std.mem.eql(u8, kind, "jest")) return jest.filter(allocator, input);
    return allocator.dupe(u8, input);
}

test "filter unknown kind passes through" {
    const allocator = std.testing.allocator;
    const out = try filter(allocator, "unknown", "hello\n");
    defer allocator.free(out);
    try std.testing.expectEqualStrings("hello\n", out);
}
