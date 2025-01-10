const std = @import("std");

const Regex = @import("regex.zig");
const Token = Regex.Token;

pub const Error = error{ EndOfBuffer, ExpectedCharacter, UnexpectedCharacter };

const Self = @This();

const TokenList = std.ArrayList(Token);

regexp: []const u8,
tokens: ?[]const Token = null,
start: usize = 0,
cursor: usize = 0,
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator, regexp: []const u8) !Self {
    return .{
        .regexp = regexp,
        .allocator = allocator,
    };
}

pub fn deinit(self: *Self) void {
    if (self.tokens) |tl| {
        for (tl) |token| {
            token.deinit();
        }
        self.allocator.free(tl);
    }
}

fn readChar(self: *Self) !u8 {
    if (self.cursor >= self.regexp.len) {
        return Error.EndOfBuffer;
    } else {
        return self.regexp[self.cursor];
    }
}

/// like `advance` but returns `null` instead of `Error.EndOfBuffer`.
pub fn next(self: *Self) !?Token {
    return self.advance() catch |err| {
        if (err == Error.EndOfBuffer)
            return null;

        return err;
    };
}

/// tokenizes and returns the next token, caller is responsible for token memory.
pub fn advance(self: *Self) !Token {
    std.debug.assert(self.cursor == self.start);

    defer {
        self.cursor += 1;
        self.start = self.cursor;
    }

    var c = try self.readChar();

    const t = Token{
        .lexer = self,
        .lexeme = switch (c) {
            '.' => .Dot,
            '*' => .Star,
            '?' => .Question,
            '+' => .Plus,
            '|' => .Pipe,
            '(' => .LParen,
            ')' => .RParen,
            '^' => .StartAnchor,
            '$' => .EndAnchor,
            '[' => .{ .Class = try self.parseClass() },
            else => literal: {
                // TODO: should expand with escape sequences later?
                if (c == '\\') {
                    self.cursor += 1;
                    c = try self.readChar();
                }

                break :literal .{ .Literal = c };
            },
        },
        .position = .{ self.start, self.cursor },
    };

    return t;
}

fn parseClass(self: *Self) !Regex.Class {
    var c = try self.readChar();

    while (c != ']') {
        self.cursor += 1;
        c = self.readChar() catch |err| {
            if (err == Error.EndOfBuffer) {
                std.debug.print("{d}: expected ']' to close character class.\n", .{self.start});
                return Error.ExpectedCharacter;
            } else {
                return err;
            }
        };
    }
    return try Regex.Class.init(self.allocator, self.regexp[self.start + 1 .. self.cursor]);
}

pub fn scan(self: *Self) ![]const Token {
    var tokens = TokenList.init(self.allocator);

    defer tokens.deinit();

    var t = try self.next();

    while (t) |token| : (t = try self.next()) {
        try tokens.append(token);
    }

    self.tokens = try tokens.toOwnedSlice();
    return self.tokens.?;
}
