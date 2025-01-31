const std = @import("std");
const formatter = @import("zabi").ast.formatter;
const testing = std.testing;

const Ast = @import("zabi").ast.Ast;
const Formatter = formatter.SolidityFormatter(std.ArrayList(u8).Writer);
const Parser = @import("zabi").ast.Parser;

test "Basic" {
    const slice =
        \\    function _transferOwnership(address newOwner) internal override(foo.bar, baz.foo) {
        \\        address oldOwner = _owner;
        \\        _owner = newOwner;
        \\        emit OwnershipTransferred(oldOwner, newOwner);
        \\        if (foo > 5) 
        \\ {foo +=       bar;}
        \\        if (foo > 5) 
        \\  foo +=       bar;
        \\      do {
        \\        uint ggggg = 42;
        \\       } while (true);
        \\
        \\        for (uint   foo   = 0;   foo > 5; ++foo) 
        \\ {foo +=       bar;}
        \\        for (uint   foo   = 0;   foo > 5; ++foo) 
        \\ foo +=       bar;
        \\ 
        \\        while (true) 
        \\ {foo +=       bar;}
        \\        if (foo > 5) 
        \\ {foo +=       bar;} else    {fooooo;}
        \\        if (foo > 5) 
        \\ foo +=       bar; else    {fooooo;}
        \\ unchecked        {bar      += fooo;}
        \\ continue;
        \\ break;
        \\ return           foooooo +           6;
        \\ 
        \\    }
    ;

    var list = std.ArrayList(u8).init(testing.allocator);
    errdefer list.deinit();

    var ast = try Ast.parse(testing.allocator, slice);
    defer ast.deinit(testing.allocator);

    var format: Formatter = .init(ast, 4, list.writer());

    std.debug.print("Nodes: {any}\n", .{ast.nodes.items(.tag)});
    try format.formatStatement(@intCast(ast.nodes.len - 1), .none);

    const fmt = try list.toOwnedSlice();
    defer testing.allocator.free(fmt);

    std.debug.print("Formatted:\n{s}\n", .{fmt});
}

test "Element" {
    const slice =
        \\   using {         asdasdasdasd as +     } for              int256;
    ;

    var list = std.ArrayList(u8).init(testing.allocator);
    errdefer list.deinit();

    var ast = try Ast.parse(testing.allocator, slice);
    defer ast.deinit(testing.allocator);

    var format: Formatter = .init(ast, 4, list.writer());

    std.debug.print("Nodes: {any}\n", .{ast.nodes.items(.tag)});
    try format.formatContractBodyElement(4);

    const fmt = try list.toOwnedSlice();
    defer testing.allocator.free(fmt);

    std.debug.print("Formatted:\n{s}\n", .{fmt});
}
