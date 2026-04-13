const std = @import("std");

const Rule = struct {
    prefix: []const u8,
    empty: []const u8,
    with_args: []const u8,
    require_args: bool = false,
};

const ARGS_PLACEHOLDER = "%ARGS%";

const RULES = [_]Rule{
    .{ .prefix = "bundle exec rspec", .empty = "bundle exec rspec 2>&1 | cc-filter stream -k rspec", .with_args = "bundle exec rspec %ARGS% 2>&1 | cc-filter stream -k rspec" },
    .{ .prefix = "git status", .empty = "git status --short", .with_args = "git status --short %ARGS%" },
    .{ .prefix = "git log", .empty = "git log --oneline -n 15", .with_args = "git log --oneline -n 15 %ARGS%" },
    .{ .prefix = "git diff", .empty = "git diff --stat", .with_args = "git diff --stat %ARGS%" },
    .{ .prefix = "git add", .empty = "", .with_args = "git add %ARGS% && echo ok", .require_args = true },
    .{ .prefix = "git push", .empty = "{ git push 2>&1 | tail -3; }", .with_args = "{ git push %ARGS% 2>&1 | tail -3; }" },
    .{ .prefix = "cargo test", .empty = "cargo test 2>&1 | cc-filter stream -k cargo-test", .with_args = "cargo test %ARGS% 2>&1 | cc-filter stream -k cargo-test" },
    .{ .prefix = "bun test", .empty = "bun test 2>&1 | cc-filter stream -k bun-test", .with_args = "bun test %ARGS% 2>&1 | cc-filter stream -k bun-test" },
    .{ .prefix = "rspec", .empty = "rspec 2>&1 | cc-filter stream -k rspec", .with_args = "rspec %ARGS% 2>&1 | cc-filter stream -k rspec" },
    .{ .prefix = "jest", .empty = "jest 2>&1 | cc-filter stream -k jest", .with_args = "jest %ARGS% 2>&1 | cc-filter stream -k jest" },
    .{ .prefix = "ls", .empty = "ls --color=never -1 | head -50", .with_args = "ls --color=never -1 %ARGS% | head -50" },
    .{ .prefix = "tree", .empty = "tree -L 2 --noreport", .with_args = "tree -L 2 --noreport %ARGS%" },
};

pub fn apply(allocator: std.mem.Allocator, command: []const u8) !?[]const u8 {
    const trimmed = std.mem.trim(u8, command, " \t\n\r");
    if (trimmed.len == 0) return null;

    if (hasShellMeta(trimmed)) return null;
    if (std.mem.startsWith(u8, trimmed, "cc-filter")) return null;

    for (RULES) |rule| {
        const args = stripPrefix(trimmed, rule.prefix) orelse continue;
        if (args.len == 0) {
            if (rule.require_args) return null;
            return try allocator.dupe(u8, rule.empty);
        }
        return try substitute(allocator, rule.with_args, args);
    }

    return null;
}

fn substitute(allocator: std.mem.Allocator, template: []const u8, args: []const u8) ![]u8 {
    const idx = std.mem.indexOf(u8, template, ARGS_PLACEHOLDER) orelse return allocator.dupe(u8, template);
    var buf = std.ArrayList(u8){};
    errdefer buf.deinit(allocator);
    try buf.appendSlice(allocator, template[0..idx]);
    try buf.appendSlice(allocator, args);
    try buf.appendSlice(allocator, template[idx + ARGS_PLACEHOLDER.len ..]);
    return buf.toOwnedSlice(allocator);
}

fn stripPrefix(input: []const u8, prefix: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, input, prefix)) return "";
    if (std.mem.startsWith(u8, input, prefix) and input.len > prefix.len and input[prefix.len] == ' ') {
        return std.mem.trimLeft(u8, input[prefix.len..], " ");
    }
    return null;
}

fn hasShellMeta(s: []const u8) bool {
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        switch (s[i]) {
            '|', ';', '`', '&' => return true,
            '$' => if (i + 1 < s.len and s[i + 1] == '(') return true,
            else => {},
        }
    }
    return false;
}

test "apply: git status" {
    const out = try apply(std.testing.allocator, "git status");
    defer if (out) |o| std.testing.allocator.free(o);
    try std.testing.expectEqualStrings("git status --short", out.?);
}

test "apply: git status with args" {
    const out = try apply(std.testing.allocator, "git status -uno");
    defer if (out) |o| std.testing.allocator.free(o);
    try std.testing.expectEqualStrings("git status --short -uno", out.?);
}

test "apply: git log" {
    const out = try apply(std.testing.allocator, "git log");
    defer if (out) |o| std.testing.allocator.free(o);
    try std.testing.expectEqualStrings("git log --oneline -n 15", out.?);
}

test "apply: git log with args" {
    const out = try apply(std.testing.allocator, "git log --author=me");
    defer if (out) |o| std.testing.allocator.free(o);
    try std.testing.expectEqualStrings("git log --oneline -n 15 --author=me", out.?);
}

test "apply: git diff" {
    const out = try apply(std.testing.allocator, "git diff");
    defer if (out) |o| std.testing.allocator.free(o);
    try std.testing.expectEqualStrings("git diff --stat", out.?);
}

test "apply: git diff with args" {
    const out = try apply(std.testing.allocator, "git diff HEAD~1");
    defer if (out) |o| std.testing.allocator.free(o);
    try std.testing.expectEqualStrings("git diff --stat HEAD~1", out.?);
}

test "apply: git add with args" {
    const out = try apply(std.testing.allocator, "git add foo.txt");
    defer if (out) |o| std.testing.allocator.free(o);
    try std.testing.expectEqualStrings("git add foo.txt && echo ok", out.?);
}

test "apply: git add without args returns null" {
    const out = try apply(std.testing.allocator, "git add");
    try std.testing.expect(out == null);
}

test "apply: git push" {
    const out = try apply(std.testing.allocator, "git push");
    defer if (out) |o| std.testing.allocator.free(o);
    try std.testing.expectEqualStrings("{ git push 2>&1 | tail -3; }", out.?);
}

test "apply: git push with args" {
    const out = try apply(std.testing.allocator, "git push origin main");
    defer if (out) |o| std.testing.allocator.free(o);
    try std.testing.expectEqualStrings("{ git push origin main 2>&1 | tail -3; }", out.?);
}

test "apply: ls" {
    const out = try apply(std.testing.allocator, "ls");
    defer if (out) |o| std.testing.allocator.free(o);
    try std.testing.expectEqualStrings("ls --color=never -1 | head -50", out.?);
}

test "apply: ls with args" {
    const out = try apply(std.testing.allocator, "ls -la");
    defer if (out) |o| std.testing.allocator.free(o);
    try std.testing.expectEqualStrings("ls --color=never -1 -la | head -50", out.?);
}

test "apply: tree" {
    const out = try apply(std.testing.allocator, "tree");
    defer if (out) |o| std.testing.allocator.free(o);
    try std.testing.expectEqualStrings("tree -L 2 --noreport", out.?);
}

test "apply: tree with args" {
    const out = try apply(std.testing.allocator, "tree src");
    defer if (out) |o| std.testing.allocator.free(o);
    try std.testing.expectEqualStrings("tree -L 2 --noreport src", out.?);
}

test "apply: unknown command returns null" {
    const out = try apply(std.testing.allocator, "echo hi");
    try std.testing.expect(out == null);
}

test "apply: unknown git subcommand returns null" {
    const out = try apply(std.testing.allocator, "git foo");
    try std.testing.expect(out == null);
}

test "apply: skip when contains pipe" {
    const out = try apply(std.testing.allocator, "ls | grep foo");
    try std.testing.expect(out == null);
}

test "apply: skip when contains &&" {
    const out = try apply(std.testing.allocator, "git status && echo done");
    try std.testing.expect(out == null);
}

test "apply: skip when contains background &" {
    const out = try apply(std.testing.allocator, "git status &");
    try std.testing.expect(out == null);
}

test "apply: skip when contains semicolon" {
    const out = try apply(std.testing.allocator, "git status; echo");
    try std.testing.expect(out == null);
}

test "apply: skip when contains backtick" {
    const out = try apply(std.testing.allocator, "git log `cat a`");
    try std.testing.expect(out == null);
}

test "apply: skip when contains command substitution" {
    const out = try apply(std.testing.allocator, "git log $(cat a)");
    try std.testing.expect(out == null);
}

test "apply: skip cc-filter prefixed" {
    const out = try apply(std.testing.allocator, "cc-filter hook");
    try std.testing.expect(out == null);
}

test "apply: ls does not match lsof" {
    const out = try apply(std.testing.allocator, "lsof -i");
    try std.testing.expect(out == null);
}

test "apply: empty command returns null" {
    const out = try apply(std.testing.allocator, "");
    try std.testing.expect(out == null);
}

test "apply: whitespace-only returns null" {
    const out = try apply(std.testing.allocator, "   ");
    try std.testing.expect(out == null);
}

test "apply: cargo test" {
    const out = try apply(std.testing.allocator, "cargo test");
    defer if (out) |o| std.testing.allocator.free(o);
    try std.testing.expectEqualStrings("cargo test 2>&1 | cc-filter stream -k cargo-test", out.?);
}

test "apply: cargo test with args" {
    const out = try apply(std.testing.allocator, "cargo test --lib foo");
    defer if (out) |o| std.testing.allocator.free(o);
    try std.testing.expectEqualStrings("cargo test --lib foo 2>&1 | cc-filter stream -k cargo-test", out.?);
}

test "apply: bun test" {
    const out = try apply(std.testing.allocator, "bun test");
    defer if (out) |o| std.testing.allocator.free(o);
    try std.testing.expectEqualStrings("bun test 2>&1 | cc-filter stream -k bun-test", out.?);
}

test "apply: bun test with args" {
    const out = try apply(std.testing.allocator, "bun test src/foo.test.ts");
    defer if (out) |o| std.testing.allocator.free(o);
    try std.testing.expectEqualStrings("bun test src/foo.test.ts 2>&1 | cc-filter stream -k bun-test", out.?);
}

test "apply: rspec" {
    const out = try apply(std.testing.allocator, "rspec");
    defer if (out) |o| std.testing.allocator.free(o);
    try std.testing.expectEqualStrings("rspec 2>&1 | cc-filter stream -k rspec", out.?);
}

test "apply: rspec with args" {
    const out = try apply(std.testing.allocator, "rspec spec/foo_spec.rb");
    defer if (out) |o| std.testing.allocator.free(o);
    try std.testing.expectEqualStrings("rspec spec/foo_spec.rb 2>&1 | cc-filter stream -k rspec", out.?);
}

test "apply: bundle exec rspec" {
    const out = try apply(std.testing.allocator, "bundle exec rspec");
    defer if (out) |o| std.testing.allocator.free(o);
    try std.testing.expectEqualStrings("bundle exec rspec 2>&1 | cc-filter stream -k rspec", out.?);
}

test "apply: bundle exec rspec with args" {
    const out = try apply(std.testing.allocator, "bundle exec rspec spec/foo_spec.rb");
    defer if (out) |o| std.testing.allocator.free(o);
    try std.testing.expectEqualStrings("bundle exec rspec spec/foo_spec.rb 2>&1 | cc-filter stream -k rspec", out.?);
}

test "apply: bundle without rspec returns null" {
    const out = try apply(std.testing.allocator, "bundle install");
    try std.testing.expect(out == null);
}

test "apply: jest" {
    const out = try apply(std.testing.allocator, "jest");
    defer if (out) |o| std.testing.allocator.free(o);
    try std.testing.expectEqualStrings("jest 2>&1 | cc-filter stream -k jest", out.?);
}

test "apply: jest with args" {
    const out = try apply(std.testing.allocator, "jest --coverage");
    defer if (out) |o| std.testing.allocator.free(o);
    try std.testing.expectEqualStrings("jest --coverage 2>&1 | cc-filter stream -k jest", out.?);
}

test "apply: longest match wins for bundle exec rspec" {
    const out = try apply(std.testing.allocator, "bundle exec rspec --tag slow");
    defer if (out) |o| std.testing.allocator.free(o);
    try std.testing.expectEqualStrings("bundle exec rspec --tag slow 2>&1 | cc-filter stream -k rspec", out.?);
}
