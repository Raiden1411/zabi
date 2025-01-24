const std = @import("std");
const formatter = @import("zabi").ast.formatter;
const testing = std.testing;

const Ast = @import("zabi").ast.Ast;
const Formatter = formatter.SolidityFormatter(std.ArrayList(u8).Writer, 4);
const Parser = @import("zabi").ast.Parser;

test "Basic" {
    const slice =
        \\    function _transferOwnership(address newOwner) internal override(foo.bar, baz.foo) {
        \\        address oldOwner = _owner;
        \\        _owner = newOwner;
        \\        emit OwnershipTransferred(oldOwner, newOwner);
        \\    }
    ;

    var list = std.ArrayList(u8).init(testing.allocator);
    errdefer list.deinit();

    var ast = try Ast.parse(testing.allocator, slice);
    defer ast.deinit(testing.allocator);

    var format: Formatter = .init(ast, list.writer());

    std.debug.print("Nodes: {any}\n", .{ast.nodes.items(.tag)});
    try format.formatStatement(@intCast(ast.nodes.len - 1));

    const fmt = try list.toOwnedSlice();
    defer testing.allocator.free(fmt);

    std.debug.print("Formatted:\n{s}\n", .{fmt});
    // try testing.expectEqualStrings("10000 gwei", fmt);
}
