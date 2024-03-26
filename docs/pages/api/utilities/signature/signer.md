# `Signer`

## Definition

This is a custom zig implementation of ecdsa signers with the `Secp256k1` curve.

## Usage

This is expecting you to pass in a private key or `null` if you passed in `null` we will generate a random `Secp256k1` scalar that will be used as the private key.

## getAddressFromPublicKey

Gets the ethereum address from the signers public key.

```zig
const Signer = @import("zabi").Signer
const random = try signer.init(null);

try random.getAddressFromPublicKey();
```

### Returns

Type: `[20]u8` -> This is not checksumed.

## Sign

Signs a message using the signer. This expected that the message was previously hashed.

```zig
const Signer = @import("zabi").Signer
const random = try signer.init(null);

try random.sign([_]u8{0} ** 32);
```

### Returns

Type: `Signature` 

## RecoverPublicKey

Recovers a public key from a message and signature. This expected that the message was previously hashed.

```zig
const Signer = @import("zabi").Signer
const random = try signer.init(null);

try random.recoverPublicKey([_]u8{0} ** 32, .{.r = [_]u8{0} ** 32, .s =[_]u8{0} ** 32, .v = 0 });
```

### Returns

Type: `[65]u8` 

## RecoverEthereumAddress

Recovers a ethereum from a message and signature. This expected that the message was previously hashed.
The address will already be checksumed.

```zig
const Signer = @import("zabi").Signer
const random = try signer.init(null);

try random.recoverEthereumAddress([_]u8{0} ** 32, .{.r = [_]u8{0} ** 32, .s =[_]u8{0} ** 32, .v = 0 });
```

### Returns

Type: `[40]u8` 

## RecoverMessageAddress

Exactly the same as above but the message will be hashed.
The address will already be checksumed.

```zig
const Signer = @import("zabi").Signer
const random = try signer.init(null);

try random.recoverMessageAddress([_]u8{0} ** 32, .{.r = [_]u8{0} ** 32, .s =[_]u8{0} ** 32, .v = 0 });
```

### Returns

Type: `[40]u8` 

## SignMessage

Signs an ethereum message. 
Follows the specification so it prepends \x19Ethereum Signed Message:\n to the start of the message.

```zig
const Signer = @import("zabi").Signer
const random = try signer.init(null);

try random.signMessage(testing.allocator, [_]u8{0} ** 32);
```

### Returns

Type: `Signature` 

## VerifyMessage

Verifies if a given message was sent by the current signer.

```zig
const Signer = @import("zabi").Signer
const random = try signer.init(null);

try random.verifyMessage(testing.allocator, .{.r = [_]u8{0} ** 32, .s =[_]u8{0} ** 32, .v = 0 }, [_]u8{0} ** 32);
```

### Returns

Type: `bool` 
