## EthereumSchorrSigner

Ethereum compatible `Schnorr` signer.

For implementation details please go to the [specification](https://github.com/chronicleprotocol/scribe/blob/main/docs/Schnorr.md)

### Properties

```zig
struct {
  /// The private key of this signer.
  private_key: CompressedScalar
  /// The compressed version of the address of this signer.
  public_key: CompressedPublicKey
  /// The chain address of this signer.
  address_bytes: Address
}
```

## SigningErrors

Set of possible errors when signing a message.

```zig
NotSquareError || NonCanonicalError || EncodingError ||
        IdentityElementError || error{ InvalidNonce, InvalidPrivateKey }
```

### Init
Creates the signer state.

Generates a compressed public key from the provided `private_key`.

If a null value is provided a random key will
be generated. This is to mimic the behaviour from zig's `KeyPair` types.

### Signature

```zig
pub fn init(private_key: ?CompressedScalar) IdentityElementError!Self
```

### ConstructMessageHash
Constructs the message digest based on the previously signed message.

### Signature

```zig
pub fn constructMessageHash(message: CompressedScalar) CompressedScalar
```

### HashNonce
Generates the `k` value from random bytes and the private_key.

### Signature

```zig
pub fn hashNonce(random_buffer: CompressedScalar, priv_key: CompressedScalar) CompressedScalar
```

### HashChallenge
Generates the `Schnorr` challenge from `R` bytes, a `message_construct` and a generated ethereum address.

### Signature

```zig
pub fn hashChallenge(
    public_key: CompressedPublicKey,
    message_digest: CompressedScalar,
    address: Address,
) (EncodingError || NonCanonicalError || NotSquareError)!CompressedScalar
```

### GenerateAddress
Generates an ethereum address from the `x` coordinates from a public key.

### Signature

```zig
pub fn generateAddress(r: CompressedScalar) Address
```

### PrivateKeyToScalar
Converts the `private_key` to a `Secp256k1` scalar.

Negates the scalar if the y coordinates are odd.

### Signature

```zig
pub fn privateKeyToScalar(self: Self) (NonCanonicalError || NotSquareError || EncodingError || error{InvalidPrivateKey})!Scalar
```

### SignUnsafe
Generates a `Schnorr` signature for a given message.

This will not verify if the generated signature is correct.
Please use `verifyMessage` to make sure  that the generated signature is valid.

### Signature

```zig
pub fn signUnsafe(self: Self, message: CompressedScalar) SigningErrors!SchnorrSignature
```

### Sign
Generates a `Schnorr` signature for a given message.

This verifies if the generated signature is valid. Otherwise an `InvalidSignature` error is returned.

### Signature

```zig
pub fn sign(self: Self, message: CompressedScalar) (SigningErrors || error{InvalidSignature})!SchnorrSignature
```

### VerifySignature
Verifies if the provided signature was signed by `Self`.

### Signature

```zig
pub fn verifySignature(self: Self, message: CompressedScalar, signature: SchnorrSignature) bool
```

### VerifyMessage
Verifies if the provided signature was signed by the provided `x` coordinate bytes from a compressed public key.

### Signature

```zig
pub fn verifyMessage(public_key: CompressedPublicKey, message_construct: CompressedScalar, signature: SchnorrSignature) bool
```

## SigningErrors

Set of possible errors when signing a message.

```zig
NotSquareError || NonCanonicalError || EncodingError ||
        IdentityElementError || error{ InvalidNonce, InvalidPrivateKey }
```

## SchnorrSigner

BIP0340 `Schnorr` signer.

For implementation details please go to the [specification](https://github.com/bitcoin/bips/blob/master/bip-0340.mediawiki#user-content-Specification)

### Properties

```zig
struct {
  /// The private key of this signer.
  private_key: CompressedScalar
  /// The compressed version of the address of this signer.
  public_key: CompressedPublicKey
}
```

## SigningErrors

Set of possible errors when signing a message.

```zig
NotSquareError || NonCanonicalError || EncodingError ||
        IdentityElementError || error{ InvalidNonce, InvalidPrivateKey }
```

### Init
Generates a compressed public key from the provided `private_key`.

If a null value is provided a random key will
be generated. This is to mimic the behaviour from zig's `KeyPair` types.

### Signature

```zig
pub fn init(private_key: ?CompressedScalar) IdentityElementError!Self
```

### PrivateKeyToScalar
Converts the `private_key` to a `Secp256k1` scalar.

Negates the scalar if the y coordinates are odd.

### Signature

```zig
pub fn privateKeyToScalar(self: Self) (NonCanonicalError || NotSquareError || EncodingError || error{InvalidPrivateKey})!Scalar
```

### SignUnsafe
Generates a `Schnorr` signature for a given message.

This will not verify if the generated signature is correct.
Please use `verifyMessage` to make sure  that the generated signature is valid.

### Signature

```zig
pub fn signUnsafe(self: Self, message: []const u8) SigningErrors!SchnorrSignature
```

### Sign
Generates a `Schnorr` signature for a given message.

This verifies if the generated signature is valid. Otherwise an `InvalidSignature` error is returned.

### Signature

```zig
pub fn sign(self: Self, message: []const u8) (SigningErrors || error{InvalidSignature})!SchnorrSignature
```

### VerifySignature
Verifies if the provided signature was signed by `Self`.

### Signature

```zig
pub fn verifySignature(self: Self, signature: SchnorrSignature, message: []const u8) bool
```

### VerifyMessage
Verifies if the provided signature was signed by the provided `x` coordinate bytes from a compressed public key.

### Signature

```zig
pub fn verifyMessage(pub_key: CompressedScalar, signature: SchnorrSignature, message: []const u8) bool
```

### HashAux
Generates the auxiliary hash from a random set of bytes.

### Signature

```zig
pub fn hashAux(random_buffer: [32]u8) CompressedScalar
```

### HashNonce
Generates the `k` value from the mask of the `aux` hash and a `public_key` with the `message`.

### Signature

```zig
pub fn hashNonce(t: [32]u8, public_key: [32]u8, message: []const u8) CompressedScalar
```

### HashChallenge
Generates the `Schnorr` challenge from `R` bytes, `public_key` and the `message` to sign.

### Signature

```zig
pub fn hashChallenge(k_r: [32]u8, pub_key: [32]u8, message: []const u8) CompressedScalar
```

## SigningErrors

Set of possible errors when signing a message.

```zig
NotSquareError || NonCanonicalError || EncodingError ||
        IdentityElementError || error{ InvalidNonce, InvalidPrivateKey }
```

## LiftX
Extracts a point from the `Secp256k1` curve based on the provided `x` coordinates from
a `CompressedPublicKey` array of bytes.

### Signature

```zig
pub fn liftX(encoded: CompressedScalar) (NonCanonicalError || NotSquareError)!Secp256k1
```

## NonceToScalar
Generates the `k` scalar and bytes from a given `public_key` with the identifier.

### Signature

```zig
pub fn nonceToScalar(bytes: CompressedScalar) (NonCanonicalError || IdentityElementError || error{InvalidNonce})!RBytesAndScalar
```

