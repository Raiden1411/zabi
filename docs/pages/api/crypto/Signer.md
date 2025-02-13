## RecoverPubKeyErrors

Set of possible errors when trying to recover a public key from a `message_hash`.

```zig
NotSquareError || EncodingError || IdentityElementError || NonCanonicalError || error{InvalidMessageHash}
```

## SigningErrors

Set of possible errors when signing a message.

```zig
IdentityElementError || NonCanonicalError
```

## RecoverPubkey
Recovers the public key from a message

Returns the public key in an uncompressed sec1 format so that
it can be used later to recover the address.

### Signature

```zig
pub fn recoverPubkey(signature: Signature, message_hash: Hash) RecoverPubKeyErrors!UncompressedPublicKey
```

## RecoverAddress
Recovers the address from a message using the
recovered public key from the message.

### Signature

```zig
pub fn recoverAddress(signature: Signature, message_hash: Hash) RecoverPubKeyErrors!Address
```

## Init
Creates the signer state.

Generates a compressed public key from the provided `private_key`.

If a null value is provided a random key will
be generated. This is to mimic the behaviour from zig's `KeyPair` types.

### Signature

```zig
pub fn init(private_key: ?Hash) IdentityElementError!Signer
```

## Sign
Signs an ethereum or EVM like chains message.

Since ecdsa signatures are malliable EVM chains only accept
signature with low s values.

We enforce this behaviour as well as using RFC 6979
for generating deterministic scalars for recoverying public keys from messages.

### Signature

```zig
pub fn sign(self: Signer, hash: Hash) SigningErrors!Signature
```

## VerifyMessage
Verifies if a message was signed by this signer.

### Signature

```zig
pub fn verifyMessage(self: Signer, message_hash: Hash, signature: Signature) bool
```

## GetPublicKeyUncompressed
Gets the uncompressed version of the public key

### Signature

```zig
pub fn getPublicKeyUncompressed(self: Signer) [65]u8
```

## GenerateNonce
Implementation of RFC 6979 of deterministic k values for deterministic signature generation.
Reference: https://datatracker.ietf.org/doc/html/rfc6979

### Signature

```zig
pub fn generateNonce(self: Signer, message_hash: Hash) [32]u8
```

