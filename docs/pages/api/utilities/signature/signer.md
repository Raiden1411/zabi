# `Signer`

## Definition

This is essentially a wrapper for `libsecp256k1`.
This is the same library that powers `geth`.

## Usage

This is expecting you to pass in a private key of you could use the `generateRandomSigner` that uses Zigs to generate a random `Secp256k1` scalar that will be used as the private key.

## getAddressFromPublicKey

Gets the ethereum address from the signers public key.

```zig
const signer = @import("zabi").secp256k1
const random = try signer.generateRandomSigner();

try random.getAddressFromPublicKey();
```

### Returns

Type: `[20]u8` -> This is not checksumed.

## Sign

Signs a message using the signer. This expected that the message was previously hashed.

```zig
const signer = @import("zabi").secp256k1
const random = try signer.generateRandomSigner();

try random.sign([_]u8{0} ** 32);
```

### Returns

Type: `Signature` 

## RecoverPublicKey

Recovers a public key from a message and signature. This expected that the message was previously hashed.

```zig
const signer = @import("zabi").secp256k1
const random = try signer.generateRandomSigner();

try random.recoverPublicKey([_]u8{0} ** 32, .{.r = [_]u8{0} ** 32, .s =[_]u8{0} ** 32, .v = 0 });
```

### Returns

Type: `[65]u8` 

## RecoverEthereumAddress

Recovers a ethereum from a message and signature. This expected that the message was previously hashed.
The address will already be checksumed.

```zig
const signer = @import("zabi").secp256k1
const random = try signer.generateRandomSigner();

try random.recoverEthereumAddress([_]u8{0} ** 32, .{.r = [_]u8{0} ** 32, .s =[_]u8{0} ** 32, .v = 0 });
```

### Returns

Type: `[40]u8` 

## RecoverMessageAddress

Exactly the same as above but the message will be hashed.
The address will already be checksumed.

```zig
const signer = @import("zabi").secp256k1
const random = try signer.generateRandomSigner();

try random.recoverMessageAddress([_]u8{0} ** 32, .{.r = [_]u8{0} ** 32, .s =[_]u8{0} ** 32, .v = 0 });
```

### Returns

Type: `[40]u8` 

## SignMessage

Signs an ethereum message. 
Follows the specification so it prepends \x19Ethereum Signed Message:\n to the start of the message.

```zig
const signer = @import("zabi").secp256k1
const random = try signer.generateRandomSigner();

try random.signMessage(testing.allocator, [_]u8{0} ** 32);
```

### Returns

Type: `Signature` 

## VerifyMessage

Verifies if a given message was sent by the current signer.

```zig
const signer = @import("zabi").secp256k1
const random = try signer.generateRandomSigner();

try random.verifyMessage(testing.allocator, .{.r = [_]u8{0} ** 32, .s =[_]u8{0} ** 32, .v = 0 }, [_]u8{0} ** 32);
```

### Returns

Type: `bool` 
