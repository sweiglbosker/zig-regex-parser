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

pub const ParseTree = struct {
    allocator: *std.mem.Allocator,
    root: *Node,

    pub const Node = struct {
        rule: Rule,
        child: ?*Node = null,
        sibling: ?*Node = null,

        pub fn init(allocator: *std.mem.Allocator, rule: Rule) !*Node {
            const node = try allocator.create(Node);
            node.* = .{ .rule = rule };

            return node;
        }

        pub fn deinit(self: *Node, allocator: *std.mem.Allocator) void {
            if (self.child) |child| {
                child.deinit();
            }

            if (self.sibling) |sibling| {
                sibling.deinit();
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
                if (node.next) |sibling| {
                    itr = sibling;
                } else {
                    break;
                }
            }

            itr.next = child;
            return;
        }
    };
};

pub fn init(tokens: []const Token) Self {
    return .{
        .tokens = tokens,
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
    return (self.Peek() == null);
}

fn next(self: *Self) ?Token {
    const r = self.peek();

    self.i += 1;

    return r;
}

pub fn parse(self: *Self, allocator: *std.mem.Allocator) !ParseTree {
    return .{
        .allocator = allocator,
        .root = try self.parseRegex(),
    };
}

// TODO: optional or anytype?
fn parseTerminal(self: *Self, expected: ?Token.Lexeme) !*ParseTree.Node {
    const terminal = self.next() orelse {
        if (expected) |lexeme| {
            std.log.err("Parser error: expected token of type {s}.", .{@tagName(lexeme)});
        }

        std.log.err("Parser error: expected terminal but found end of expression", .{});

        return Error.ExpectedToken;
    };

    if (expected) |lexeme| {
        if (activeTag(terminal.lexeme) != lexeme) { // is this necessary?
            std.log.err("Parser error: expected token of {s} but found token {s}.\n", .{ @tagName(lexeme), @tagName(terminal) });
            return Error.UnexpectedToken;
        }
    }

    return try ParseTree.Node.init(self.allocator, .{ .Terminal = terminal });
}

fn parseRegex(self: *Self) !*ParseTree.Node {
    var pt = try ParseTree.Node.init(self.allocator, Rule.Regex);
    errdefer pt.deinit();

    pt.appendChild(try self.parseAnchored());
    pt.appendChild(try self.parseRegexR());

    return pt;
}

fn parseRegexR(self: *Self) !?*ParseTree.Node {
    var pt = try ParseTree.Node.init(self.allocator, Rule.Regex);
    errdefer pt.deinit();

    // re -> ε
    if (self.epsilon()) {
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
    errdefer pt.deinit();

    if (self.peek() == Token.Lexeme.StartAnchor) {
        pt.appendChild(try self.parseTerminal(.StartAnchor));
    }

    pt.appendChild(try self.parseConcatenated());

    if (self.peek() == Token.Lexeme.EndAnchor) {
        pt.appendChild(try self.parseTerminal(.EndAnchor));
    }

    return pt;
}

fn parseConcatenated(self: *Self) !*ParseTree.Node {
    var pt = try ParseTree.Node.init(self.allocator, Rule.Concatenated);
    errdefer pt.deinit();

    pt.appendChild(try self.parseQuantified());

    pt.appendChild(try self.parseConcatenatedR());

    return pt;
}

fn parseConcatenatedR(self: *Self) !?*ParseTree.Node {
    var pt = try ParseTree.Node.init(self.allocator, Rule.ConcatenatedR);
    errdefer pt.deinit();

    if (self.epsilon()) {
        return null;
    }

    pt.appendChild(try self.parseQuantified());

    pt.appendChild(try self.parseConcatenatedR());

    return pt;
}

fn parseQuantified(self: *Self) !*ParseTree.Node {
    var pt = try ParseTree.Node.init(self.allocator, Rule.Quantified);
    errdefer pt.deinit();

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
    errdefer pt.deinit();

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
