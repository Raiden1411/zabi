const abi = @import("zabi").abi.abitypes;
const std = @import("std");
const testing = std.testing;

const AbiItem = abi.AbiItem;
const Constructor = abi.Constructor;
const Error = abi.Error;
const Event = abi.Event;
const Fallback = abi.Fallback;
const Function = abi.Function;
const Receive = abi.Receive;

test "Formatting" {
    {
        try testing.expectFmt("error Foo(address bar)", "{f}", .{Error{
            .type = .@"error",
            .name = "Foo",
            .inputs = &.{.{ .type = .{ .address = {} }, .name = "bar" }},
        }});
    }
    {
        try testing.expectFmt("event Foo(address bar)", "{f}", .{Event{
            .type = .event,
            .name = "Foo",
            .inputs = &.{
                .{ .type = .{ .address = {} }, .name = "bar", .indexed = false },
            },
        }});
    }
    {
        try testing.expectFmt("constructor(address bar) payable", "{f}", .{Constructor{
            .type = .constructor,
            .inputs = &.{.{ .type = .{ .address = {} }, .name = "bar" }},
            .stateMutability = .payable,
        }});
    }
    {
        try testing.expectFmt("receive() external payable", "{f}", .{Receive{
            .type = .receive,
            .stateMutability = .payable,
        }});
    }
    {
        try testing.expectFmt("fallback()", "{f}", .{Fallback{
            .type = .fallback,
            .stateMutability = .nonpayable,
        }});
    }
    {
        try testing.expectFmt("fallback() payable", "{f}", .{Fallback{
            .type = .fallback,
            .stateMutability = .payable,
        }});
    }
    {
        try testing.expectFmt("function Foo(address bar)", "{f}", .{
            Function{
                .type = .function,
                .name = "Foo",
                .inputs = &.{.{ .type = .{ .address = {} }, .name = "bar" }},
                .stateMutability = .nonpayable,
                .outputs = &.{},
            },
        });
    }
    {
        try testing.expectFmt("function Foo(address bar) view", "{f}", .{
            Function{
                .type = .function,
                .name = "Foo",
                .inputs = &.{.{ .type = .{ .address = {} }, .name = "bar" }},
                .stateMutability = .view,
                .outputs = &.{},
            },
        });
    }
    {
        try testing.expectFmt("function Foo(address bar) pure returns (bool baz)", "{f}", .{
            Function{
                .type = .function,
                .name = "Foo",
                .inputs = &.{.{ .type = .{ .address = {} }, .name = "bar" }},
                .stateMutability = .pure,
                .outputs = &.{
                    .{ .type = .{ .bool = {} }, .name = "baz" },
                },
            },
        });
    }
    {
        try testing.expectFmt("function Foo((string[] foo, uint256 bar, (bytes[] fizz, bool buzz, int256[] jazz)[] baz) fizzbuzz)", "{f}", .{
            Function{
                .type = .function,
                .name = "Foo",
                .inputs = &.{.{
                    .type = .{ .tuple = {} },
                    .name = "fizzbuzz",
                    .components = &.{
                        .{ .type = .{ .dynamicArray = &.{ .string = {} } }, .name = "foo" },
                        .{ .type = .{ .uint = 256 }, .name = "bar" },
                        .{
                            .type = .{ .dynamicArray = &.{ .tuple = {} } },
                            .name = "baz",
                            .components = &.{
                                .{ .type = .{ .dynamicArray = &.{ .bytes = {} } }, .name = "fizz" },
                                .{ .type = .{ .bool = {} }, .name = "buzz" },
                                .{ .type = .{ .dynamicArray = &.{ .int = 256 } }, .name = "jazz" },
                            },
                        },
                    },
                }},
                .stateMutability = .nonpayable,
                .outputs = &.{},
            },
        });
    }
    {
        try testing.expectFmt("function Foo((string[] foo, uint256 bar, (bytes[] fizz, bool buzz, int256[] jazz)[] baz) fizzbuzz)", "{f}", .{
            AbiItem{
                .abiFunction = .{
                    .type = .function,
                    .name = "Foo",
                    .inputs = &.{.{
                        .type = .{ .tuple = {} },
                        .name = "fizzbuzz",
                        .components = &.{
                            .{ .type = .{ .dynamicArray = &.{ .string = {} } }, .name = "foo" },
                            .{ .type = .{ .uint = 256 }, .name = "bar" },
                            .{
                                .type = .{ .dynamicArray = &.{ .tuple = {} } },
                                .name = "baz",
                                .components = &.{
                                    .{ .type = .{ .dynamicArray = &.{ .bytes = {} } }, .name = "fizz" },
                                    .{ .type = .{ .bool = {} }, .name = "buzz" },
                                    .{ .type = .{ .dynamicArray = &.{ .int = 256 } }, .name = "jazz" },
                                },
                            },
                        },
                    }},
                    .stateMutability = .nonpayable,
                    .outputs = &.{},
                },
            },
        });
    }
}
