## addr_resolver

```zig
.{
    .name = "addr",
    .type = .function,
    .stateMutability = .view,
    .inputs = &.{
        .{ .type = .{ .fixedBytes = 32 }, .name = "name" },
    },
    .outputs = &.{
        .{ .type = .{ .address = {} }, .name = "" },
    },
}
```

## resolver

```zig
.{
    .name = "resolve",
    .type = .function,
    .stateMutability = .view,
    .inputs = &.{
        .{ .type = .{ .bytes = {} }, .name = "name" },
        .{ .type = .{ .bytes = {} }, .name = "data" },
    },
    .outputs = &.{
        .{ .type = .{ .bytes = {} }, .name = "" },
        .{ .type = .{ .address = {} }, .name = "address" },
    },
}
```

## text_resolver

```zig
.{
    .name = "text",
    .type = .function,
    .stateMutability = .view,
    .inputs = &.{
        .{ .type = .{ .fixedBytes = 32 }, .name = "name" },
        .{ .type = .{ .string = {} }, .name = "key" },
    },
    .outputs = &.{
        .{ .type = .{ .string = {} }, .name = "" },
    },
}
```

## find_resolver

```zig
.{
    .name = "findResolver",
    .type = .function,
    .stateMutability = .view,
    .inputs = &.{
        .{ .type = .{ .bytes = {} }, .name = "" },
    },
    .outputs = &.{
        .{ .type = .{ .address = {} }, .name = "" },
        .{ .type = .{ .fixedBytes = 32 }, .name = "" },
    },
}
```

## reverse_resolver

```zig
.{
    .name = "reverse",
    .type = .function,
    .stateMutability = .view,
    .inputs = &.{
        .{ .type = .{ .bytes = {} }, .name = "reverseName" },
    },
    .outputs = &.{
        .{ .type = .{ .string = {} }, .name = "resolvedName" },
        .{ .type = .{ .address = {} }, .name = "resolvedAddress" },
        .{ .type = .{ .address = {} }, .name = "reverseResolver" },
        .{ .type = .{ .address = {} }, .name = "resolver" },
    },
}
```

