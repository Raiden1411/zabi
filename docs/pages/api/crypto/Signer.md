## RecoverPubkey
Recovers the public key from a message
Returns the public key in an uncompressed sec1 format so that
it can be used later to recover the address.

## RecoverAddress
Recovers the address from a message using the
recovered public key from the message.

## Init
Inits the signer. Generates a compressed public key from the provided
`private_key`. If a null value is provided a random key will
be generated. This is to mimic the behaviour from zig's `KeyPair` types.

## Sign
Signs an ethereum or EVM like chains message.\
Since ecdsa signatures are malliable EVM chains only accept
signature with low s values. We enforce this behaviour as well
as using RFC 6979 for generating deterministic scalars for recoverying
public keys from messages.

## VerifyMessage
Verifies if a message was signed by this signer.

## GetPublicKeyUncompressed
Gets the uncompressed version of the public key

## GenerateNonce
Implementation of RFC 6979 of deterministic k values for deterministic signature generation.\
Reference: https://datatracker.ietf.org/doc/html/rfc6979

