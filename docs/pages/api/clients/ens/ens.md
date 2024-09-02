## ENSClient
A public client that interacts with the ENS contracts.

Currently ENSAvatar is not supported but will be in future versions.

### Signature

```zig
pub fn ENSClient(comptime client_type: Clients) type
```

## EnsErrors

Set of possible errors when performing ens client actions.

```zig
EncodeErrors || ClientType.BasicRequestErrors || DecoderErrors || error{
            ExpectedEnsContracts,
            NoSpaceLeft,
            InvalidCharacter,
            InvalidLength,
            InvalidAddress,
            FailedToDecodeResponse,
        }
```

## Init
Starts the RPC connection
If the contracts are null it defaults to mainnet contracts.

### Signature

```zig
pub fn init(opts: InitOpts) (ClientType.InitErrors || error{InvalidChain})!*ENS
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
pub fn getEnsAddress(self: *ENS, name: []const u8, opts: BlockNumberRequest) EnsErrors!AbiDecoded(Address)
```

## GetEnsName
Gets the ENS name associated with the address.

Caller owns the memory if the request is successfull.
Calls the reverse resolver and decodes with the same.

This will fail if its not a valid checksumed address.

### Signature

```zig
pub fn getEnsName(self: *ENS, address: []const u8, opts: BlockNumberRequest) EnsErrors!RPCResponse([]const u8)
```

## GetEnsResolver
Gets the ENS resolver associated with the name.

Caller owns the memory if the request is successfull.
Calls the find resolver and decodes with the same one.

The names are not normalized so make sure that the names are normalized before hand.

### Signature

```zig
pub fn getEnsResolver(self: *ENS, name: []const u8, opts: BlockNumberRequest) EnsErrors!Address
```

## GetEnsText
Gets a text record for a specific ENS name.

Caller owns the memory if the request is successfull.
Calls the resolver and decodes with the text resolver.

The names are not normalized so make sure that the names are normalized before hand.

### Signature

```zig
pub fn getEnsText(self: *ENS, name: []const u8, key: []const u8, opts: BlockNumberRequest) EnsErrors!AbiDecoded([]const u8)
```

