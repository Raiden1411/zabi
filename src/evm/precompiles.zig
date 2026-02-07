const gas_tracker = @import("gas_tracker.zig");
const signature_type = zabi_crypto.signature;
const Signer = zabi_crypto.Signer;
const specification = @import("specification.zig");
const std = @import("std");
const zabi_types = @import("zabi-types").ethereum;
const zabi_crypto = @import("zabi-crypto");

const Address = zabi_types.Address;
const Allocator = std.mem.Allocator;
const GasTracker = gas_tracker.GasTracker;
const Interpreter = @import("Interpreter.zig");
const InterpreterStatus = Interpreter.InterpreterStatus;
const Signature = signature_type.Signature;
const SpecId = specification.SpecId;

/// Identifiers for precompile contracts mapped to addresses `0x01..0x05`.
///
/// `modexp` (`0x05`) is only available from Byzantium and later.
pub const PrecompileId = enum(u8) {
    ecrecover = 1,
    sha256 = 2,
    ripemd160 = 3,
    identity = 4,
    modexp = 5,

    /// Resolves a precompile ID for an address under the active spec.
    ///
    /// Returns `null` when the address is not a precompile for the selected fork.
    pub fn fromAddress(spec: SpecId, address: Address) ?PrecompileId {
        const id: u160 = std.mem.readInt(u160, &address, .big);

        if (id == 0 or id > @intFromEnum(PrecompileId.modexp))
            return null;

        if (id == @intFromEnum(PrecompileId.modexp) and !spec.enabled(.BYZANTIUM))
            return null;

        return @enumFromInt(id);
    }
};

/// Result produced by precompile execution.
///
/// `output` is allocator-owned and must be freed by the caller.
pub const PrecompileResult = struct {
    status: InterpreterStatus,
    output: []u8,
    gas: GasTracker,
};

const PRECOMPILE_ECRECOVER_GAS: u64 = 3000;
const PRECOMPILE_SHA256_BASE_GAS: u64 = 60;
const PRECOMPILE_SHA256_WORD_GAS: u64 = 12;
const PRECOMPILE_RIPEMD160_BASE_GAS: u64 = 600;
const PRECOMPILE_RIPEMD160_WORD_GAS: u64 = 120;
const PRECOMPILE_IDENTITY_BASE_GAS: u64 = 15;
const PRECOMPILE_IDENTITY_WORD_GAS: u64 = 3;

/// Executes a precompile call and applies fork-aware gas rules.
///
/// The returned `output` is newly allocated with `allocator`.
pub fn executePrecompile(
    allocator: Allocator,
    spec: SpecId,
    address: Address,
    input: []const u8,
    gas_limit: u64,
) Allocator.Error!PrecompileResult {
    const id = PrecompileId.fromAddress(spec, address) orelse unreachable;

    switch (id) {
        .modexp => {
            const parsed = parseModExpInput(input) orelse
                return precompileOutOfGas(gas_limit);

            const exp_head = modExpExponentHead(parsed);
            const cost = modExpGasCost(spec, parsed, exp_head) orelse
                return precompileOutOfGas(gas_limit);

            if (cost > gas_limit) {
                return precompileOutOfGas(gas_limit);
            }

            const gas: GasTracker = .{
                .available = gas_limit - cost,
                .refund_amount = 0,
                .total = gas_limit,
            };

            const output = try executeModExp(allocator, parsed);

            return .{
                .status = .returned,
                .output = output,
                .gas = gas,
            };
        },
        else => {
            const cost = precompileSimpleGasCost(id, input.len) orelse
                return precompileOutOfGas(gas_limit);

            if (cost > gas_limit) {
                return precompileOutOfGas(gas_limit);
            }

            var gas = GasTracker.init(gas_limit);
            gas.available = gas_limit - cost;

            const output = switch (id) {
                .ecrecover => try executeEcRecover(allocator, input),
                .sha256 => try executeSha256(allocator, input),
                .ripemd160 => try executeRipemd160(allocator, input),
                .identity => try executeIdentity(allocator, input),
                .modexp => unreachable,
            };

            return .{
                .status = .returned,
                .output = output,
                .gas = gas,
            };
        },
    }
}

/// Builds a reverted precompile result with all gas marked as consumed.
fn precompileOutOfGas(gas_limit: u64) Allocator.Error!PrecompileResult {
    const gas: GasTracker = .{
        .available = 0,
        .refund_amount = 0,
        .total = gas_limit,
    };

    return .{
        .status = .reverted,
        .output = &.{},
        .gas = gas,
    };
}

/// Computes gas cost for non-MODEXP precompiles using per-word pricing.
fn precompileSimpleGasCost(id: PrecompileId, input_length: usize) ?u64 {
    const length_u64 = std.math.cast(u64, input_length) orelse return null;
    const words = countWords(length_u64) orelse return null;

    return switch (id) {
        .ecrecover => PRECOMPILE_ECRECOVER_GAS,
        .sha256 => checkedAddProduct(PRECOMPILE_SHA256_BASE_GAS, PRECOMPILE_SHA256_WORD_GAS, words),
        .ripemd160 => checkedAddProduct(PRECOMPILE_RIPEMD160_BASE_GAS, PRECOMPILE_RIPEMD160_WORD_GAS, words),
        .identity => checkedAddProduct(PRECOMPILE_IDENTITY_BASE_GAS, PRECOMPILE_IDENTITY_WORD_GAS, words),
        .modexp => null,
    };
}

/// Computes `base + per_word * words` and returns `null` on overflow.
fn checkedAddProduct(base: u64, per_word: u64, words: u64) ?u64 {
    const product, const overflow_mul = @mulWithOverflow(per_word, words);
    if (overflow_mul != 0) {
        return null;
    }

    const total, const overflow_add = @addWithOverflow(base, product);
    if (overflow_add != 0) {
        return null;
    }

    return total;
}

/// Returns `ceil(length / 32)` with overflow protection.
fn countWords(length: u64) ?u64 {
    const sum, const overflow = @addWithOverflow(length, 31);
    if (overflow != 0) {
        return null;
    }

    return @divFloor(sum, 32);
}

/// Executes precompile `0x01` (ECRECOVER), returning zeroed output on invalid signatures.
fn executeEcRecover(allocator: Allocator, input: []const u8) Allocator.Error![]u8 {
    var output = try allocator.alloc(u8, 32);
    @memset(output, 0);

    var padded: [128]u8 = [_]u8{0} ** 128;
    const copy_length = @min(input.len, padded.len);
    if (copy_length > 0) {
        @memcpy(padded[0..copy_length], input[0..copy_length]);
    }

    const message_hash: [32]u8 = padded[0..32].*;
    const v_value = std.mem.readInt(u256, padded[32..64], .big);
    const r_value = std.mem.readInt(u256, padded[64..96], .big);
    const s_value = std.mem.readInt(u256, padded[96..128], .big);

    if (r_value == 0 or s_value == 0) {
        return output;
    }

    const v_parity = vParityFromValue(v_value) orelse return output;

    const signature: Signature = .{
        .r = r_value,
        .s = s_value,
        .v = v_parity,
    };

    const recovered = Signer.recoverAddress(signature, message_hash) catch return output;

    @memcpy(output[12..32], recovered[0..]);

    return output;
}

/// Maps EVM `v` encodings (`27/28` and `0/1`) into signature parity bits.
fn vParityFromValue(value: u256) ?u2 {
    if (value == 27 or value == 28) {
        return @intCast(value - 27);
    }

    if (value == 0 or value == 1) {
        return @intCast(value);
    }

    return null;
}

/// Executes precompile `0x02` (SHA256).
fn executeSha256(allocator: Allocator, input: []const u8) Allocator.Error![]u8 {
    const output = try allocator.alloc(u8, 32);

    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(input, &hash, .{});

    @memcpy(output, hash[0..]);

    return output;
}

/// Executes precompile `0x03` (RIPEMD160) with 12-byte left padding.
fn executeRipemd160(allocator: Allocator, input: []const u8) Allocator.Error![]u8 {
    var output = try allocator.alloc(u8, 32);
    @memset(output, 0);

    var digest: [20]u8 = undefined;
    ripemd160Hash(input, &digest);

    @memcpy(output[12..32], digest[0..]);

    return output;
}

/// Executes precompile `0x04` (IDENTITY).
fn executeIdentity(allocator: Allocator, input: []const u8) Allocator.Error![]u8 {
    const output = try allocator.alloc(u8, input.len);

    if (input.len > 0) {
        @memcpy(output, input);
    }

    return output;
}

const ModexpParsed = struct {
    base_length: u64,
    exp_length: u64,
    mod_length: u64,
    mod_length_usize: usize,
    base_slice: []const u8,
    exp_slice: []const u8,
    mod_slice: []const u8,
    base_missing: u64,
    exp_missing: u64,
    mod_missing: u64,
};

/// Parses EIP-198 MODEXP calldata layout and captures missing suffix bytes.
///
/// Missing bytes are tracked so callers can treat truncated input as right-padded with zeros.
fn parseModExpInput(input: []const u8) ?ModexpParsed {
    const base_length = readLengthWord(input, 0) orelse return null;
    const exp_length = readLengthWord(input, 32) orelse return null;
    const mod_length = readLengthWord(input, 64) orelse return null;

    const mod_length_usize = std.math.cast(usize, mod_length) orelse return null;

    const base_offset = @as(u64, 96);
    const exp_offset = checkedAddU64(base_offset, base_length) orelse return null;
    const mod_offset = checkedAddU64(exp_offset, exp_length) orelse return null;

    const input_length = @as(u64, input.len);

    const base_window = selectInputSlice(input, input_length, base_offset, base_length);
    const exp_window = selectInputSlice(input, input_length, exp_offset, exp_length);
    const mod_window = selectInputSlice(input, input_length, mod_offset, mod_length);

    return .{
        .base_length = base_length,
        .exp_length = exp_length,
        .mod_length = mod_length,
        .mod_length_usize = mod_length_usize,
        .base_slice = base_window.slice,
        .exp_slice = exp_window.slice,
        .mod_slice = mod_window.slice,
        .base_missing = base_window.missing,
        .exp_missing = exp_window.missing,
        .mod_missing = mod_window.missing,
    };
}

const InputSlice = struct {
    slice: []const u8,
    missing: u64,
};

/// Returns the available input sub-slice and the number of right-padded bytes.
fn selectInputSlice(
    input: []const u8,
    input_length: u64,
    offset: u64,
    length: u64,
) InputSlice {
    std.debug.assert(input_length == input.len);

    if (length == 0) {
        return .{ .slice = &.{}, .missing = 0 };
    }

    if (offset >= input_length) {
        return .{ .slice = &.{}, .missing = length };
    }

    const available = @min(length, input_length - offset);
    const start = std.math.cast(usize, offset) orelse 0;
    const end = std.math.cast(usize, offset + available) orelse 0;

    return .{
        .slice = input[start..end],
        .missing = length - available,
    };
}

/// Reads a 32-byte big-endian length word and narrows it to `u64`.
fn readLengthWord(input: []const u8, offset: usize) ?u64 {
    const value = readPaddedU256Be(input, offset);
    return std.math.cast(u64, value);
}

/// Reads a big-endian `u256` from `input[offset..offset+32]`, right-padding missing bytes with zeros.
fn readPaddedU256Be(input: []const u8, offset: usize) u256 {
    var padded: [32]u8 = [_]u8{0} ** 32;
    if (offset < input.len) {
        const available = @min(input.len - offset, 32);
        @memcpy(padded[0..available], input[offset .. offset + available]);
    }

    return std.mem.readInt(u256, &padded, .big);
}

/// Extracts the first 32 bytes of the exponent for MODEXP gas calculation.
fn modExpExponentHead(parsed: ModexpParsed) u256 {
    if (parsed.exp_length == 0) {
        return 0;
    }

    var head_bytes: [32]u8 = [_]u8{0} ** 32;
    const copy_length = @min(parsed.exp_slice.len, head_bytes.len);
    if (copy_length > 0) {
        @memcpy(head_bytes[0..copy_length], parsed.exp_slice[0..copy_length]);
    }

    return std.mem.readInt(u256, &head_bytes, .big);
}

/// Computes MODEXP gas cost according to fork-specific divisor rules.
fn modExpGasCost(spec: SpecId, parsed: ModexpParsed, exp_head: u256) ?u64 {
    const max_length = @max(parsed.base_length, parsed.mod_length);
    const complexity = modExpMultiplicationComplexity(max_length) orelse return null;
    const exponent_bits = modExpExponentBits(parsed.exp_length, exp_head);
    const exponent_cost = @max(exponent_bits, 1);

    const divisor: u64 = if (spec.enabled(.BERLIN)) 3 else 20;
    const numerator = @as(u128, complexity) * @as(u128, exponent_cost);
    const result = numerator / divisor;

    if (result > std.math.maxInt(u64)) {
        return null;
    }

    return @intCast(result);
}

/// Computes the EIP-198 multiplication complexity term from operand length.
fn modExpMultiplicationComplexity(max_length: u64) ?u64 {
    if (max_length == 0) {
        return 0;
    }

    const length_u128 = @as(u128, max_length);

    if (max_length <= 64) {
        const result = length_u128 * length_u128;
        return @intCast(result);
    }

    if (max_length <= 1024) {
        const squared = length_u128 * length_u128;
        const result = squared / 4 + 96 * length_u128 - 3072;
        if (result > std.math.maxInt(u64)) {
            return null;
        }
        return @intCast(result);
    }

    const squared = length_u128 * length_u128;
    const result = squared / 16 + 480 * length_u128 - 199_680;
    if (result > std.math.maxInt(u64)) {
        return null;
    }

    return @intCast(result);
}

/// Computes adjusted exponent bit-length used by MODEXP pricing.
fn modExpExponentBits(exp_length: u64, exp_head: u256) u64 {
    if (exp_length == 0) {
        return 0;
    }

    const head_bits: u64 = if (exp_head == 0) 0 else 256 - @clz(exp_head);

    if (exp_length <= 32) {
        return head_bits;
    }

    return 8 * (exp_length - 32) + head_bits;
}

/// Executes MODEXP and returns exactly `mod_length` output bytes.
fn executeModExp(allocator: Allocator, parsed: ModexpParsed) Allocator.Error![]u8 {
    if (parsed.mod_length == 0) {
        return &.{};
    }

    var modulus = try bigIntFromBeBytesWithRightPadding(
        allocator,
        parsed.mod_slice,
        parsed.mod_missing,
    );
    defer modulus.deinit();

    const output = try allocator.alloc(u8, parsed.mod_length_usize);
    @memset(output, 0);

    if (modulus.eqlZero()) {
        return output;
    }

    var base = try bigIntFromBeBytesWithRightPadding(
        allocator,
        parsed.base_slice,
        parsed.base_missing,
    );
    defer base.deinit();

    var result = try computeModularExponentiation(
        allocator,
        &base,
        &modulus,
        parsed.exp_slice,
        parsed.exp_missing,
    );
    defer result.deinit();

    writeBigIntAsBe(output, result);

    return output;
}

const BigInt = std.math.big.int.Managed;

/// Performs modular exponentiation using square-and-multiply over big integers.
fn computeModularExponentiation(
    allocator: Allocator,
    base: *const BigInt,
    modulus: *const BigInt,
    exp_slice: []const u8,
    exp_missing: u64,
) Allocator.Error!BigInt {
    var result = try BigInt.initSet(allocator, 1);
    errdefer result.deinit();

    var product = try BigInt.init(allocator);
    defer product.deinit();

    var quotient = try BigInt.init(allocator);
    defer quotient.deinit();

    var remainder = try BigInt.init(allocator);
    defer remainder.deinit();

    var base_mod = try BigInt.init(allocator);
    defer base_mod.deinit();

    try assignModulo(&base_mod, base, modulus, &quotient, &remainder);
    try assignModulo(&result, &result, modulus, &quotient, &remainder);

    var index: usize = 0;
    while (index < exp_slice.len) : (index += 1) {
        try applyExponentByte(
            exp_slice[index],
            &result,
            &base_mod,
            modulus,
            &product,
            &quotient,
            &remainder,
        );
    }

    var missing = exp_missing;
    while (missing > 0) : (missing -= 1) {
        try applyExponentByte(
            0,
            &result,
            &base_mod,
            modulus,
            &product,
            &quotient,
            &remainder,
        );
    }

    return result;
}

/// Applies one exponent byte (MSB to LSB) in square-and-multiply form.
fn applyExponentByte(
    value: u8,
    result: *BigInt,
    base_mod: *const BigInt,
    modulus: *const BigInt,
    product: *BigInt,
    quotient: *BigInt,
    remainder: *BigInt,
) Allocator.Error!void {
    var mask: u8 = 0x80;
    while (mask != 0) : (mask >>= 1) {
        try assignModularProduct(result, result, result, modulus, product, quotient, remainder);

        if ((value & mask) != 0) {
            try assignModularProduct(result, result, base_mod, modulus, product, quotient, remainder);
        }
    }
}

/// Assigns `(left * right) mod modulus` into `target`.
fn assignModularProduct(
    target: *BigInt,
    left: *const BigInt,
    right: *const BigInt,
    modulus: *const BigInt,
    product: *BigInt,
    quotient: *BigInt,
    remainder: *BigInt,
) Allocator.Error!void {
    try product.mul(left, right);
    try BigInt.divFloor(quotient, remainder, product, modulus);
    try target.copy(remainder.toConst());
}

/// Assigns `value mod modulus` into `target`.
fn assignModulo(
    target: *BigInt,
    value: *const BigInt,
    modulus: *const BigInt,
    quotient: *BigInt,
    remainder: *BigInt,
) Allocator.Error!void {
    try BigInt.divFloor(quotient, remainder, value, modulus);
    try target.copy(remainder.toConst());
}

/// Parses a big-endian integer and appends zero bytes on the right (least-significant side).
fn bigIntFromBeBytesWithRightPadding(
    allocator: Allocator,
    bytes: []const u8,
    missing_bytes: u64,
) Allocator.Error!BigInt {
    var result = try bigIntFromBeBytes(allocator, bytes);
    errdefer result.deinit();

    if (missing_bytes == 0) {
        return result;
    }

    const shift_bits_u64 = missing_bytes * 8;
    const shift_bits = std.math.cast(usize, shift_bits_u64) orelse return result;

    try result.shiftLeft(&result, shift_bits);

    return result;
}

/// Parses a big-endian byte slice into a managed big integer.
fn bigIntFromBeBytes(allocator: Allocator, bytes: []const u8) Allocator.Error!BigInt {
    var result = try BigInt.initSet(allocator, 0);
    errdefer result.deinit();

    var multiplier = try BigInt.initSet(allocator, 256);
    defer multiplier.deinit();

    var temp = try BigInt.init(allocator);
    defer temp.deinit();

    for (bytes) |byte| {
        try temp.mul(&result, &multiplier);
        result.swap(&temp);
        try result.addScalar(&result, byte);
    }

    return result;
}

/// Writes a positive big integer as big-endian bytes into a fixed-width output slice.
fn writeBigIntAsBe(output: []u8, value: BigInt) void {
    std.debug.assert(value.isPositive());

    if (output.len == 0) {
        return;
    }

    const limbs = value.limbs[0..value.len()];
    const limb_bytes = std.mem.sliceAsBytes(limbs);

    var end: usize = limb_bytes.len;
    while (end > 0 and limb_bytes[end - 1] == 0) : (end -= 1) {}

    if (end == 0) {
        return;
    }

    const significant = limb_bytes[0..end];

    if (significant.len > output.len) {
        const start = significant.len - output.len;
        var i: usize = 0;
        while (i < output.len) : (i += 1) {
            output[output.len - 1 - i] = significant[start + i];
        }
        return;
    }

    var i: usize = 0;
    while (i < significant.len) : (i += 1) {
        output[output.len - 1 - i] = significant[i];
    }
}

/// Adds two `u64` values and returns `null` on overflow.
fn checkedAddU64(left: u64, right: u64) ?u64 {
    const sum, const overflow = @addWithOverflow(left, right);
    if (overflow != 0) {
        return null;
    }

    return sum;
}

/// RIPEMD-160 implementation used by precompile `0x03`.
fn ripemd160Hash(input: []const u8, out: *[20]u8) void {
    const r = [80]u8{
        0, 1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15,
        7, 4,  13, 1,  10, 6,  15, 3,  12, 0, 9,  5,  2,  14, 11, 8,
        3, 10, 14, 4,  9,  15, 8,  1,  2,  7, 0,  6,  13, 11, 5,  12,
        1, 9,  11, 10, 0,  8,  12, 4,  13, 3, 7,  15, 14, 5,  6,  2,
        4, 0,  5,  9,  7,  12, 2,  10, 14, 1, 3,  8,  11, 6,  15, 13,
    };

    const rp = [80]u8{
        5,  14, 7,  0, 9, 2,  11, 4,  13, 6,  15, 8,  1,  10, 3,  12,
        6,  11, 3,  7, 0, 13, 5,  10, 14, 15, 8,  12, 4,  9,  1,  2,
        15, 5,  1,  3, 7, 14, 6,  9,  11, 8,  12, 2,  10, 0,  4,  13,
        8,  6,  4,  1, 3, 11, 15, 0,  5,  12, 2,  13, 9,  7,  10, 14,
        12, 15, 10, 4, 1, 5,  8,  7,  6,  2,  13, 14, 0,  3,  9,  11,
    };

    const s = [80]u8{
        11, 14, 15, 12, 5,  8,  7,  9,  11, 13, 14, 15, 6,  7,  9,  8,
        7,  6,  8,  13, 11, 9,  7,  15, 7,  12, 15, 9,  11, 7,  13, 12,
        11, 13, 6,  7,  14, 9,  13, 15, 14, 8,  13, 6,  5,  12, 7,  5,
        11, 12, 14, 15, 14, 15, 9,  8,  9,  14, 5,  6,  8,  6,  5,  12,
        9,  15, 5,  11, 6,  8,  13, 12, 5,  12, 13, 14, 11, 8,  5,  6,
    };

    const sp = [80]u8{
        8,  9,  9,  11, 13, 15, 15, 5,  7,  7,  8,  11, 14, 14, 12, 6,
        9,  13, 15, 7,  12, 8,  9,  11, 7,  7,  12, 7,  6,  15, 13, 11,
        9,  7,  15, 11, 8,  6,  6,  14, 12, 13, 5,  14, 13, 13, 7,  5,
        15, 5,  8,  11, 14, 14, 6,  14, 6,  9,  12, 9,  12, 5,  15, 8,
        8,  5,  12, 9,  12, 5,  14, 6,  8,  13, 6,  5,  15, 13, 11, 11,
    };

    var h0: u32 = 0x67452301;
    var h1: u32 = 0xEFCDAB89;
    var h2: u32 = 0x98BADCFE;
    var h3: u32 = 0x10325476;
    var h4: u32 = 0xC3D2E1F0;

    var offset: usize = 0;
    while (offset + 64 <= input.len) : (offset += 64) {
        ripemd160Compress(input[offset .. offset + 64], &h0, &h1, &h2, &h3, &h4, r, rp, s, sp);
    }

    var tail: [128]u8 = [_]u8{0} ** 128;
    const remaining = input.len - offset;
    if (remaining > 0) {
        @memcpy(tail[0..remaining], input[offset..]);
    }

    tail[remaining] = 0x80;

    const bit_length = @as(u64, input.len) * 8;
    const pad_size: usize = if (remaining + 1 + 8 <= 64) 64 else 128;
    const tail_len_slice = tail[pad_size - 8 .. pad_size];
    const tail_len_ptr: *[8]u8 = @ptrCast(tail_len_slice.ptr);
    std.mem.writeInt(u64, tail_len_ptr, bit_length, .little);

    ripemd160Compress(tail[0..64], &h0, &h1, &h2, &h3, &h4, r, rp, s, sp);
    if (pad_size == 128) {
        ripemd160Compress(tail[64..128], &h0, &h1, &h2, &h3, &h4, r, rp, s, sp);
    }

    std.mem.writeInt(u32, out[0..4], h0, .little);
    std.mem.writeInt(u32, out[4..8], h1, .little);
    std.mem.writeInt(u32, out[8..12], h2, .little);
    std.mem.writeInt(u32, out[12..16], h3, .little);
    std.mem.writeInt(u32, out[16..20], h4, .little);
}

/// Compresses one 64-byte RIPEMD-160 block into the running hash state.
fn ripemd160Compress(
    block: []const u8,
    h0: *u32,
    h1: *u32,
    h2: *u32,
    h3: *u32,
    h4: *u32,
    r: [80]u8,
    rp: [80]u8,
    s: [80]u8,
    sp: [80]u8,
) void {
    std.debug.assert(block.len == 64);

    var words: [16]u32 = undefined;
    var index: usize = 0;
    while (index < 16) : (index += 1) {
        const start = index * 4;
        const chunk = block[start .. start + 4];
        const chunk_ptr: *const [4]u8 = @ptrCast(chunk.ptr);
        words[index] = std.mem.readInt(u32, chunk_ptr, .little);
    }

    var a = h0.*;
    var b = h1.*;
    var c = h2.*;
    var d = h3.*;
    var e = h4.*;

    var ap = h0.*;
    var bp = h1.*;
    var cp = h2.*;
    var dp = h3.*;
    var ep = h4.*;

    var i: usize = 0;
    while (i < 80) : (i += 1) {
        const t = std.math.rotl(u32, a +% roundFunction(i, b, c, d) +% words[r[i]] +% roundConstant(i), s[i]) +% e;
        a = e;
        e = d;
        d = std.math.rotl(u32, c, 10);
        c = b;
        b = t;

        const tp = std.math.rotl(u32, ap +% parallelRoundFunction(i, bp, cp, dp) +% words[rp[i]] +% parallelRoundConstant(i), sp[i]) +% ep;
        ap = ep;
        ep = dp;
        dp = std.math.rotl(u32, cp, 10);
        cp = bp;
        bp = tp;
    }

    const temp = h1.* +% c +% dp;
    h1.* = h2.* +% d +% ep;
    h2.* = h3.* +% e +% ap;
    h3.* = h4.* +% a +% bp;
    h4.* = h0.* +% b +% cp;
    h0.* = temp;
}

/// Round function for the left RIPEMD-160 lane.
fn roundFunction(round: usize, x: u32, y: u32, z: u32) u32 {
    return switch (round / 16) {
        0 => x ^ y ^ z,
        1 => (x & y) | (~x & z),
        2 => (x | ~y) ^ z,
        3 => (x & z) | (y & ~z),
        else => x ^ (y | ~z),
    };
}

/// Round function for the parallel RIPEMD-160 lane.
fn parallelRoundFunction(round: usize, x: u32, y: u32, z: u32) u32 {
    return switch (round / 16) {
        0 => x ^ (y | ~z),
        1 => (x & z) | (y & ~z),
        2 => (x | ~y) ^ z,
        3 => (x & y) | (~x & z),
        else => x ^ y ^ z,
    };
}

/// Additive round constant for the left RIPEMD-160 lane.
fn roundConstant(round: usize) u32 {
    return switch (round / 16) {
        0 => 0x00000000,
        1 => 0x5A827999,
        2 => 0x6ED9EBA1,
        3 => 0x8F1BBCDC,
        else => 0xA953FD4E,
    };
}

/// Additive round constant for the parallel RIPEMD-160 lane.
fn parallelRoundConstant(round: usize) u32 {
    return switch (round / 16) {
        0 => 0x50A28BE6,
        1 => 0x5C4DD124,
        2 => 0x6D703EF3,
        3 => 0x7A6D76E9,
        else => 0x00000000,
    };
}
