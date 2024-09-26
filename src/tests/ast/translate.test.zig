const std = @import("std");
const testing = std.testing;

const Translate = @import("../../ast/Translate.zig");
const Ast = @import("../../ast/Ast.zig");

test "Foo" {
    const slice = "function(string bar, string jazz) public returns(uint baz, int jazz) constant bar = 69;";

    var writer = std.ArrayList(u8).init(testing.allocator);
    errdefer writer.deinit();

    var stream: Translate.PuncAndIndenStream = .{
        .base_writer = writer.writer(),
        .indentation_level = 4,
    };

    var ast = try Ast.parse(testing.allocator, slice);
    defer ast.deinit(testing.allocator);

    const translate = Translate.init(ast, &stream);

    std.debug.print("Slice: {any}\n", .{translate.ast.nodes.items(.tag)});
    std.debug.print("Slice: {s}\n", .{translate.ast.getNodeSource(1)});

    try translate.translateFunctionType(1);
    const translated = try writer.toOwnedSlice();
    defer testing.allocator.free(translated);

    std.debug.print("Slice: {s}\n", .{translated});
}
