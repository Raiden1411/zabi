## ConvertToEnum
Convert the struct fields into to a enum.

### Signature

```zig
pub fn ConvertToEnum(comptime T: type) type
```

## Extract
Type function use to extract enum members from any enum.

The needle can be just the tagName of a single member or a comma seperated value.

Compilation will fail if a invalid needle is provided.

### Signature

```zig
pub fn Extract(comptime T: type, comptime needle: []const u8) type
```

## MergeStructs
Merge structs into a single one

### Signature

```zig
pub fn MergeStructs(comptime T: type, comptime K: type) type
```

## MergeTupleStructs
Merge tuple structs

### Signature

```zig
pub fn MergeTupleStructs(comptime T: type, comptime K: type) type
```

## StructToTupleType
Convert a struct into a tuple type.

### Signature

```zig
pub fn StructToTupleType(comptime T: type) type
```

## Omit
Omits the selected keys from struct types.

### Signature

```zig
pub fn Omit(comptime T: type, comptime keys: []const []const u8) type
```

