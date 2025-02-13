## SpecId

Specification IDs and their activation block.

Information can be found here [Ethereum Execution Specification](https://github.com/ethereum/execution-specs)

### Properties

```zig
enum {
  FRONTIER = 0
  FRONTIER_THAWING = 1
  HOMESTEAD = 2
  DAO_FORK = 3
  TANGERINE = 4
  SPURIOUS_DRAGON = 5
  BYZANTIUM = 6
  CONSTANTINOPLE = 7
  PETERSBURG = 8
  ISTANBUL = 9
  MUIR_GLACIER = 10
  BERLIN = 11
  LONDON = 12
  ARROW_GLACIER = 13
  GRAY_GLACIER = 14
  MERGE = 15
  SHANGHAI = 16
  CANCUN = 17
  PRAGUE = 18
  LATEST = std.math.maxInt(u8)
}
```

### Enabled
Checks if a given specification id is enabled.

### Signature

```zig
pub fn enabled(
    self: SpecId,
    other: SpecId,
) bool
```

### ToSpecId
Converts an `u8` to a specId. Return error if the u8 is not valid.

### Signature

```zig
pub fn toSpecId(num: u8) error{InvalidEnumTag}!SpecId
```

## OptimismSpecId

### Properties

```zig
enum {
  FRONTIER = 0
  FRONTIER_THAWING = 1
  HOMESTEAD = 2
  DAO_FORK = 3
  TANGERINE = 4
  SPURIOUS_DRAGON = 5
  BYZANTIUM = 6
  CONSTANTINOPLE = 7
  PETERSBURG = 8
  ISTANBUL = 9
  MUIR_GLACIER = 10
  BERLIN = 11
  LONDON = 12
  ARROW_GLACIER = 13
  GRAY_GLACIER = 14
  MERGE = 15
  BEDROCK = 16
  REGOLITH = 17
  SHANGHAI = 18
  CANYON = 19
  CANCUN = 20
  ECOTONE = 21
  PRAGUE = 22
  LATEST = std.math.maxInt(u8)
}
```

### Enabled
Checks if a given specification id is enabled.

### Signature

```zig
pub fn enabled(
    self: OptimismSpecId,
    other: OptimismSpecId,
) bool
```

### ToSpecId
Converts an `u8` to a specId. Return error if the u8 is not valid.

### Signature

```zig
pub fn toSpecId(num: u8) error{InvalidEnumTag}!SpecId
```

