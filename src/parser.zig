//
// note to self: think about anchors in subexpressions

const std = @import("std");
const Regex = @import("regex.zig");

const assert = std.debug.assert;
const activeTag = std.meta.activeTag;
const Token = Regex.Token;

const Self = @This();

const Error = error{ UnexpectedToken, ExpectedToken };

const TokenIndex = usize;

const Rule = union(enum) {
    Terminal: Token,
    Regex,
    RegexR,
    Anchored,
    AnchoredR,
    Concatenated,
    ConcatenatedR,
    Quantified,
    Expr,
};

i: TokenIndex = 0,
tokens: []const Token,
allocator: std.mem.Allocator,

pub const ParseTree = struct {
    allocator: std.mem.Allocator,
    root: *Node,

    pub fn format(self: *const ParseTree, comptime fmt: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        if (fmt.len != 0) {
            return std.fmt.invalidFmtError;
        }

        try writer.print("{}\n", .{self.root});
    }

    pub const Node = struct {
        rule: Rule,
        child: ?*Node = null,
        sibling: ?*Node = null,

        pub fn format(self: *const Node, comptime fmt: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
            if (fmt.len != 0) {
                return std.fmt.invalidFmtError;
            }

            try writer.print("rule: {s}", .{@tagName(self.rule)});

            switch (self.rule) {
                .Terminal => |*token| {
                    try writer.print("token: {}\n", .{token});
                },
                else => {
                    try writer.print("\n", .{});
                },
            }

            if (self.sibling) |bro| {
                try writer.print("{}", .{bro});
            }

            if (self.child) |son| {
                try writer.print("{}", .{son});
            }
        }

        pub fn init(allocator: std.mem.Allocator, rule: Rule) !*Node {
            const node = try allocator.create(Node);
            node.* = .{ .rule = rule };

            return node;
        }

        pub fn deinit(self: *Node, allocator: std.mem.Allocator) void {
            if (self.child) |child| {
                child.deinit(allocator);
            }

            if (self.sibling) |sibling| {
                sibling.deinit(allocator);
            }

            allocator.destroy(self);
        }

        pub fn appendChild(self: *Node, child: ?*Node) void {
            if (self.child == null) {
                self.child = child;
                return;
            }

            var itr = self.child;

            while (itr) |node| {
                if (node.sibling) |bro| {
                    itr = bro;
                } else {
                    break;
                }
            }

            itr.?.sibling = child;
            return;
        }
    };

    pub fn deinit(self: *ParseTree) void {
        self.root.deinit(self.allocator);
    }
};

pub fn init(allocator: std.mem.Allocator, tokens: []const Token) Self {
    return .{
        .tokens = tokens,
        .allocator = allocator,
    };
}

fn peek(self: *Self) ?Token {
    if (self.i >= self.tokens.len) {
        return null;
    } else {
        return self.tokens[self.i];
    }
}

inline fn epsilon(self: *Self) bool {
    return (self.peek() == null);
}

fn next(self: *Self) ?Token {
    const r = self.peek();

    self.i += 1;

    return r;
}

pub fn parse(self: *Self) !ParseTree {
    return .{ .root = try self.parseRegex(), .allocator = self.allocator };
}

// TODO: optional or anytype?
fn parseTerminal(self: *Self, expected: ?@TypeOf(.Lexeme)) !*ParseTree.Node {
    const terminal = self.next() orelse {
        if (expected) |lexeme| {
            std.log.err("Parser error: expected token of type {s}.", .{@tagName(lexeme)});
        }

        std.log.err("Parser error: expected terminal but found end of expression", .{});

        return Error.ExpectedToken;
    };

    if (expected) |lexeme| {
        if (activeTag(terminal.lexeme) != lexeme) { // is this necessary?
            std.debug.print("Parser error: expected token of {s} but found token {s}.\n", .{ @tagName(lexeme), @tagName(terminal.lexeme) });
            return Error.UnexpectedToken;
        }
    }

    return try ParseTree.Node.init(self.allocator, .{ .Terminal = terminal });
}

fn parseRegex(self: *Self) error{ OutOfMemory, UnexpectedToken, ExpectedToken }!*ParseTree.Node {
    var pt = try ParseTree.Node.init(self.allocator, Rule.Regex);
    errdefer pt.deinit(self.allocator);

    pt.appendChild(try self.parseAnchored());
    pt.appendChild(try self.parseRegexR());

    return pt;
}

fn parseRegexR(self: *Self) !?*ParseTree.Node {
    var pt = try ParseTree.Node.init(self.allocator, Rule.Regex);
    errdefer pt.deinit(self.allocator);

    // re -> ε
    if (self.epsilon()) {
        pt.deinit(self.allocator);
        return null;
    }

    // re -> '|' <are> <re'>

    pt.appendChild(try self.parseTerminal(.Pipe));
    pt.appendChild(try self.parseAnchored());
    pt.appendChild(try self.parseRegexR());

    return pt;
}

fn parseAnchored(self: *Self) !*ParseTree.Node {
    var pt = try ParseTree.Node.init(self.allocator, Rule.Anchored);
    errdefer pt.deinit(self.allocator);

    if (self.peek()) |token| {
        if (token.lexeme == .StartAnchor) {
            pt.appendChild(try self.parseTerminal(.StartAnchor));
        }
    }

    pt.appendChild(try self.parseConcatenated());

    if (self.peek()) |token| {
        if (token.lexeme == .EndAnchor) {
            pt.appendChild(try self.parseTerminal(.EndAnchor));
        }
    }

    return pt;
}

fn parseConcatenated(self: *Self) !*ParseTree.Node {
    var pt = try ParseTree.Node.init(self.allocator, Rule.Concatenated);
    errdefer pt.deinit(self.allocator);

    pt.appendChild(try self.parseQuantified());

    pt.appendChild(try self.parseConcatenatedR());

    return pt;
}

fn parseConcatenatedR(self: *Self) !?*ParseTree.Node {
    var pt = try ParseTree.Node.init(self.allocator, Rule.ConcatenatedR);
    errdefer pt.deinit(self.allocator);

    if (self.epsilon()) {
        pt.deinit(self.allocator);
        return null;
    }

    pt.appendChild(try self.parseQuantified());

    pt.appendChild(try self.parseConcatenatedR());

    return pt;
}

fn parseQuantified(self: *Self) !*ParseTree.Node {
    var pt = try ParseTree.Node.init(self.allocator, Rule.Quantified);
    errdefer pt.deinit(self.allocator);

    pt.appendChild(try self.parseExpr());

    if (self.peek()) |token| {
        if (token.isQuantifier()) {
            pt.appendChild(try self.parseTerminal(null));
        }
    }

    return pt;
}

fn parseExpr(self: *Self) !*ParseTree.Node {
    var pt = try ParseTree.Node.init(self.allocator, Rule.Quantified);
    errdefer pt.deinit(self.allocator);

    if (self.peek().?.lexeme == .LParen) {
        pt.appendChild(try self.parseTerminal(.LParen));
        pt.appendChild(try self.parseRegex());
        pt.appendChild(try self.parseTerminal(.RParen));
    }

    pt.appendChild(switch (self.peek().?.lexeme) {
        .Literal => try self.parseTerminal(.Literal),
        .Class => try self.parseTerminal(.Class),
        .Dot => try self.parseTerminal(.Dot),
        else => unreachable,
    });

    return pt;
}
