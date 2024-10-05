const tokenizer = @import("../../human-readable/lexer.zig");
const std = @import("std");
const testing = std.testing;

const Parser = @import("../../human-readable/Parser.zig");
const Ast = @import("../../human-readable/Ast.zig");
const HumanAbi = @import("../../human-readable/HumanAbi.zig");

test "Human readable" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const abi = try HumanAbi.parse(arena.allocator(), "struct Bar{uint bazz;}\nstruct Foo{uint baz; Bar jazz;}\nfunction foo(Foo[69][] bar)");
    // defer ast.deinit(testing.allocator);

    // const abi_gen: HumanAbi = .{
    //     .allocator = testing.allocator,
    //     .ast = &ast,
    // };
    //
    // const abi = try abi_gen.toAbi();
    // std.debug.print("FOOOOO: {any}\n", .{ast.nodes.items(.tag)});
    // std.debug.print("FOOOOO: {s}\n", .{ast.getNodeSource(1)});
    std.debug.print("FOOOOO: {any}\n", .{abi});
    std.debug.print("FOOOOO: {any}\n", .{abi.len});
}
