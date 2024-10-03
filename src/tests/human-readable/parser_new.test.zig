const tokenizer = @import("../../human-readable/lexer.zig");
const std = @import("std");
const testing = std.testing;

const Parser = @import("../../human-readable/ParserNew.zig");
const Ast = @import("../../human-readable/Ast.zig");

test "Human readable" {
    var ast = try Ast.parse(testing.allocator, "function receive(address bar, uint bar) view external\nstruct Foo {address bar;}");
    defer ast.deinit(testing.allocator);

    std.debug.print("FOOOOO: {any}\n", .{ast.nodes.items(.tag)});
    std.debug.print("FOOOOO: {s}\n", .{ast.getNodeSource(1)});
}
