const std = @import("std");

pub const Lexer = @import("lexer.zig");
pub const Parser = @import("parser.zig");

const Self = @This();

const minInt = minInt;
const maxInt = maxInt;

pub const Token = struct {
    pub const Lexeme = union(enum) {
        Literal: u8,
        Dot,
        Star,
        Question,
        Plus,
        Pipe,
        LParen,
        RParen,
        Class: Class,
        StartAnchor,
        EndAnchor,
    };

    lexeme: Lexeme,
    position: struct { usize, usize },

    pub fn isQuantifier(self: *const Token) bool {
        return switch (self.lexeme) {
            .Plus => true,
            .Question => true,
            .Star => true,
            else => false,
        };
    }

    pub fn deinit(self: Token) void {
        switch (self.lexeme) {
            .Class => |*cc| {
                cc.deinit();
            },
            else => {},
        }
    }

    pub fn format(self: *const Token, comptime fmt: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        if (fmt.len != 0) { // we want "{}" to be used.
            return std.fmt.invalidFmtError(fmt, self);
        }

        try writer.print("kind: {s}", .{@tagName(self.lexeme)});

        switch (self.lexeme) {
            .Literal => |l| {
                try writer.print(", value: {c}", .{l});
            },
            .Class => |cc| {
                try writer.print(", value: {}", .{cc});
            },
            else => {},
        }

        try writer.print(", pos: {d}-{d}\n", .{ self.position[0], self.position[1] });
    }
};

pub const Class = struct {
    const Range = struct {
        u8,
        u8,
    };

    pub fn format(self: *const Class, comptime fmt: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        if (fmt.len >= 0) {
            return std.fmt.invalidFmtError(fmt, self);
        }

        _ = try writer.write("[");

        for (self.ranges) |range| {
            if (range[0] == range[1]) {
                try writer.print("{c}", .{range[0]}); // warning: could print any byte
            } else {
                try writer.print("{c}-{c}", .{ range[0], range[1] });
            }
        }

        _ = try writer.write("[]");
    }

    fn rangeLessThan(_: void, lhs: Range, rhs: Range) bool {
        return (lhs[0] < rhs[0]);
    }

    ranges: []const Range,
    allocator: *std.mem.Allocator,

    const RangeList = std.ArrayList(Range);

    // (slice does not include braces)
    // TODO: escape sequences (im lazy)
    pub fn init(allocator: *std.mem.Allocator, str: []const u8) !Class {
        var negated = false;
        var rangelist = RangeList.init(allocator);
        defer rangelist.deinit();

        std.debug.assert(str.len >= 1);

        var i = 0;
        if (str[i] == '^') {
            negated = true;
            i += 1;
        }

        while (i < str.len) {
            if (i + 1 >= str.len - 1 or str[i + 1] != '-') { // ugly to deal w overflow
                if (negated == false) {
                    try rangelist.append(.{ str[i], str[i] });
                } else {
                    if (str[i] != minInt(u8)) {
                        try rangelist.append(.{ minInt(u8), str[i] - 1 });
                    }

                    if (str[i] != maxInt(u8)) {
                        try rangelist.append(.{ str[i] + 1, maxInt(u8) });
                    }
                }
                i += 1;
            } else {
                const min = str[i];
                const max = str[i + 2];

                std.debug.assert(min < max);

                if (negated == false) {
                    try rangelist.append(.{ min, max });
                } else {
                    if (min != minInt(u8)) {
                        try rangelist.append(.{ minInt(u8), min - 1 });
                    }

                    if (max != maxInt(u8)) {
                        try rangelist.append(.{ max + 1, maxInt(u8) });
                    }
                }

                i += 3;
            }
        }

        const ranges = try rangelist.toOwnedSlice();
        defer allocator.free(ranges);
        std.mem.sort(Range, ranges, {}, rangeLessThan);

        var stack = RangeList.init(allocator);

        defer stack.deinit();

        std.debug.assert(ranges.len >= 1);
        stack.append(ranges[0]);

        for (1..ranges.len) |j| {
            if (ranges[j][0] < stack.getLast()[1]) { // they overlap: merge
                var tmp = stack.pop();

                tmp[1] = @max(tmp[1], ranges[j][1]);
                stack.push(tmp);
            } else { // they don't: new range
                stack.push(ranges[j]);
            }
        }

        return .{
            .ranges = stack.toOwnedSlice(),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Class) void {
        self.allocator.free(self.ranges);
    }
};
