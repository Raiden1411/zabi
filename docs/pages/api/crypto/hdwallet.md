## HDWalletNode
Implementation of BIP32 HDWallets
It doesnt have support yet for extended keys.

## FromSeed
Derive a node from a mnemonic seed. Use `pbkdf2` to generate the seed.

## FromSeedAndPath
Derive a node from a mnemonic seed and path. Use `pbkdf2` to generate the seed.\
The path must follow the specification. Example: m/44'/60'/0'/0/0 (Most common for ethereum)

## DerivePath
Derives a child node from a path.\
The path must follow the specification. Example: m/44'/60'/0'/0/0 (Most common for ethereum)

## DeriveChild
Derive a child node based on the index
If the index is higher than std.math.maxInt(u32) this will error.

## CastrateNode
Castrates a HDWalletNode. This essentially returns the node without the private key.

## EunuchNode
The EunuchNode doesn't have the private field but it
can still be used to derive public keys and chain codes.

## DeriveChild
Derive a child node based on the index
If the index is higher than std.math.maxInt(u32) this will error.\
EunuchWalletNodes cannot derive hardned nodes.

## DerivePath
Derives a child node from a path. This cannot derive hardned nodes.\
The path must follow the specification. Example: m/44/60/0/0/0 (Most common for ethereum)

