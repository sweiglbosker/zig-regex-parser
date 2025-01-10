const std = @import("std");
const Regex = @import("regex.zig");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var lexer = try Regex.Lexer.init(allocator, "abc?[a-zA-Z]");
    defer lexer.deinit();

    const tokens = try lexer.scan();

    for (tokens) |token| {
        try stdout.print("{}\n", .{token});
    }

    var parser = Regex.Parser.init(allocator, tokens);
    var parse_tree = try parser.parse();

    parse_tree.deinit();
}
