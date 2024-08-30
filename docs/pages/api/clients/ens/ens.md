## ENSClient
A public client that interacts with the ENS contracts.

Currently ENSAvatar is not supported but will be in future versions.

### Signature

```zig
pub fn ENSClient(comptime client_type: Clients) type
```

## Init
Starts the RPC connection
If the contracts are null it defaults to mainnet contracts.

### Signature

```zig
pub fn init(opts: InitOpts) !*ENS
```

## Deinit
Frees and destroys any allocated memory

### Signature

```zig
pub fn deinit(self: *ENS) void
```

## GetEnsAddress
Gets the ENS address associated with the ENS name.

Caller owns the memory if the request is successfull.
Calls the resolver address and decodes with address resolver.

The names are not normalized so make sure that the names are normalized before hand.

### Signature

```zig
pub fn getEnsAddress(self: *ENS, name: []const u8, opts: BlockNumberRequest) !AbiDecoded(Address)
```

## GetEnsName
Gets the ENS name associated with the address.

Caller owns the memory if the request is successfull.
Calls the reverse resolver and decodes with the same.

This will fail if its not a valid checksumed address.

### Signature

```zig
pub fn getEnsName(self: *ENS, address: []const u8, opts: BlockNumberRequest) !RPCResponse([]const u8)
```

## GetEnsResolver
Gets the ENS resolver associated with the name.

Caller owns the memory if the request is successfull.
Calls the find resolver and decodes with the same one.

The names are not normalized so make sure that the names are normalized before hand.

### Signature

```zig
pub fn getEnsResolver(self: *ENS, name: []const u8, opts: BlockNumberRequest) !Address
```

## GetEnsText
Gets a text record for a specific ENS name.

Caller owns the memory if the request is successfull.
Calls the resolver and decodes with the text resolver.

The names are not normalized so make sure that the names are normalized before hand.

### Signature

```zig
pub fn getEnsText(self: *ENS, name: []const u8, key: []const u8, opts: BlockNumberRequest) !AbiDecoded([]const u8)
```

