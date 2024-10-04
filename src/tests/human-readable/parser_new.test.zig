const tokenizer = @import("../../human-readable/lexer.zig");
const std = @import("std");
const testing = std.testing;

const Parser = @import("../../human-readable/ParserNew.zig");
const Ast = @import("../../human-readable/Ast.zig");
const HumanAbi = @import("../../human-readable/HumanAbi.zig");

test "Human readable" {
    var ast = try Ast.parse(testing.allocator, "struct Foo{uint bar;}");
    defer ast.deinit(testing.allocator);

    // const abi_gen: HumanAbi = .{
    //     .allocator = testing.allocator,
    //     .ast = &ast,
    // };

    std.debug.print("FOOOOO: {any}\n", .{ast.nodes.items(.tag)});
    // std.debug.print("FOOOOO: {s}\n", .{ast.getNodeSource(1)});
    // std.debug.print("FOOOOO: {}\n", .{try abi_gen.toStructParamComponent(1)});
}
