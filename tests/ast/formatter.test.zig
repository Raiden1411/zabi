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
        \\ 
        \\ 
        \\ 
        \\ 
        \\ 
        \\ //       This is a comment
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
        \\      //   Commentsssssss
        \\      /// I AM A DOC COMMENT
        \\          //   Comment
        \\contract SendToFallback is ForBar     ,   ASFASDSADASD      {
        \\ //       This is a comment
        \\    function transferToFallback(address payable _to) public payable {
        \\ assembly  {
        \\  fooo := 0x69
        \\  bar, jazz := sload(0x60)
        \\  let lol := 0x69
        \\  let lol, bar := sload(0x69)
        \\  if iszero(temp) { break }
        \\  for { let temp := value } 1 {} {
        \\  result := add(result, w)
        \\  mstore8(add(result, 1), mload(and(temp, 15)))
        \\  mstore8(result, mload(and(shr(4, temp), 15)))
        \\  temp := shr(8, temp)
        \\  if iszero(temp) { break }
        \\  }
        \\  switch lol(69)
        \\  case 69 {mload(0x80)}
        \\  case 0x40 {mload(0x80)}
        \\  case "FOOOOOOO" {mload(0x80)}
        \\  case bar {mload(0x80, 69)}
        \\  default {sload(0x80)}
        \\  function foo (bar, baz) -> fizz, buzz {mload(0x80)}
        \\    
        \\    
        \\    
        \\    
        \\    
        \\  function foo (bar, baz) {mload(0x80)}
        \\  }
        \\    
        \\    }
        // \\
        // \\
        // \\
        // \\ //       This is a comment
        // \\
        // \\              /// I AM A DOC COMMENT
        // \\      function callFallback(address payable _to) public payable {
        // \\ //       This is a comment
        // // \\        require(sent, "Failed to send Ether");
        // \\    }
        \\}
    ;

    var list = std.ArrayList(u8).init(testing.allocator);
    errdefer list.deinit();

    var ast = try Ast.parse(testing.allocator, slice);
    defer ast.deinit(testing.allocator);

    var format: Formatter = .init(ast, 4, list.writer());

    std.debug.print("Nodes: {any}\n", .{ast.nodes.items(.tag)});
    // std.debug.print("Nodes: {}\n", .{ast.nodes.items(.tag)[ast.nodes.items(.data)[15].lhs]});
    // std.debug.print("Nodes: {}\n", .{ast.nodes.items(.data)[15].lhs});
    // std.debug.print("Nodes: {}\n", .{ast.nodes.items(.data)[15].rhs});
    std.debug.assert(ast.errors.len == 0);

    try format.format();

    const fmt = try list.toOwnedSlice();
    defer testing.allocator.free(fmt);

    std.debug.print("Formatted:\n{s}\n", .{fmt});
}
