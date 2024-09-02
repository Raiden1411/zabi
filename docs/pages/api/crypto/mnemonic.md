## english

Wordlist of valid english mnemonic words.

```zig
Wordlist.loadRawList(@embedFile("wordlists/english.txt"))
```

## EntropyArray
The array of entropy bytes of an mnemonic passphrase
Compilation will fail if the count is not 12/15/18/21/24

### Signature

```zig
pub fn EntropyArray(comptime word_count: comptime_int) type
```

## MnemonicToSeed
Converts a mnemonic passphrase into a hashed seed that
can be used later for HDWallets.

Uses `pbkdf2` for the hashing with `HmacSha512` for the
pseudo random function to use.

### Signature

```zig
pub fn mnemonicToSeed(password: []const u8) (WeakParametersError || OutputTooLongError)![64]u8
```

## ToEntropy
Converts the mnemonic phrase into it's entropy representation.

**Example**
```zig
const seed = "test test test test test test test test test test test junk";
const entropy = try toEntropy(12, seed, null);

const bar = try fromEntropy(testing.allocator, 12, entropy, null);
defer testing.allocator.free(bar);

try testing.expectEqualStrings(seed, bar);
```

### Signature

```zig
pub fn toEntropy(
    comptime word_count: comptime_int,
    password: []const u8,
    wordlist: ?Wordlist,
) error{ InvalidMnemonicWord, InvalidMnemonicChecksum }!EntropyArray(word_count)
```

## FromEntropy
Converts the mnemonic entropy into it's seed.

**Example**
```zig
const seed = "test test test test test test test test test test test junk";
const entropy = try toEntropy(12, seed, null);

const bar = try fromEntropy(testing.allocator, 12, entropy, null);
defer testing.allocator.free(bar);

try testing.expectEqualStrings(seed, bar);
```

### Signature

```zig
pub fn fromEntropy(
    allocator: Allocator,
    comptime word_count: comptime_int,
    entropy_bytes: EntropyArray(word_count),
    word_list: ?Wordlist,
) (Allocator.Error || error{Overflow})![]const u8
```

## Wordlist

The word lists that are valid for mnemonic passphrases.

### Properties

```zig
struct {
  word_list: [Wordlist.list_count][]const u8
}
```

### LoadRawList
Loads word in it's raw format and parses it.
It expects that the string is seperated by "\n"

### Signature

```zig
pub fn loadRawList(raw_list: []const u8) List
```

### GetIndex
Performs binary search on the word list
as we assume that the list is alphabetically ordered.

Returns null if the word isn't on the list

### Signature

```zig
pub fn getIndex(self: List, word: []const u8) ?u16
```

