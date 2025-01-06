const std = @import("std");
const Regex = @import("regex.zig");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var lexer = try Regex.Lexer.init(&allocator, "abc");
    defer lexer.deinit();

    const tokens = try lexer.scan();

    for (tokens) |token| {
        stdout.print("{}\n", token);
    }

    var parser = Regex.Parser.init(tokens);
    var parse_tree = try parser.parse(allocator);
    defer parse_tree.root.deinit();
}
