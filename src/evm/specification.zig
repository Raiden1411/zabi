const std = @import("std");

/// Specification IDs and their activation block.
///
/// Information can be found here [Ethereum Execution Specification](https://github.com/ethereum/execution-specs)
pub const SpecId = enum(u8) {
    FRONTIER = 0, // Frontier               0
    FRONTIER_THAWING = 1, // Frontier Thawing       200000
    HOMESTEAD = 2, // Homestead              1150000
    DAO_FORK = 3, // DAO Fork               1920000
    TANGERINE = 4, // Tangerine Whistle      2463000
    SPURIOUS_DRAGON = 5, // Spurious Dragon        2675000
    BYZANTIUM = 6, // Byzantium              4370000
    CONSTANTINOPLE = 7, // Constantinople         7280000 is overwritten with PETERSBURG
    PETERSBURG = 8, // Petersburg             7280000
    ISTANBUL = 9, // Istanbul            9069000
    MUIR_GLACIER = 10, // Muir Glacier           9200000
    BERLIN = 11, // Berlin                12244000
    LONDON = 12, // London                12965000
    ARROW_GLACIER = 13, // Arrow Glacier          13773000
    GRAY_GLACIER = 14, // Gray Glacier           15050000
    MERGE = 15, // Paris/Merge            15537394 (TTD: 58750000000000000000000)
    SHANGHAI = 16, // Shanghai               17034870 (Timestamp: 1681338455)
    CANCUN = 17, // Cancun                 19426587 (Timestamp: 1710338135)
    PRAGUE = 18, // Praque                 TBD

    LATEST = std.math.maxInt(u8),

    /// Checks if a given specification id is enabled.
    pub fn enabled(
        self: SpecId,
        other: SpecId,
    ) bool {
        return @intFromEnum(self) >= @intFromEnum(other);
    }
    /// Converts an `u8` to a specId. Return error if the u8 is not valid.
    pub fn toSpecId(num: u8) error{InvalidEnumTag}!SpecId {
        return std.meta.intToEnum(SpecId, num);
    }
};

pub const OptimismSpecId = enum(u8) {
    FRONTIER = 0,
    FRONTIER_THAWING = 1,
    HOMESTEAD = 2,
    DAO_FORK = 3,
    TANGERINE = 4,
    SPURIOUS_DRAGON = 5,
    BYZANTIUM = 6,
    CONSTANTINOPLE = 7,
    PETERSBURG = 8,
    ISTANBUL = 9,
    MUIR_GLACIER = 10,
    BERLIN = 11,
    LONDON = 12,
    ARROW_GLACIER = 13,
    GRAY_GLACIER = 14,
    MERGE = 15,
    BEDROCK = 16,
    REGOLITH = 17,
    SHANGHAI = 18,
    CANYON = 19,
    CANCUN = 20,
    ECOTONE = 21,
    PRAGUE = 22,
    LATEST = std.math.maxInt(u8),

    /// Checks if a given specification id is enabled.
    pub fn enabled(
        self: OptimismSpecId,
        other: OptimismSpecId,
    ) bool {
        return @intFromEnum(self) >= @intFromEnum(other);
    }
    /// Converts an `u8` to a specId. Return error if the u8 is not valid.
    pub fn toSpecId(num: u8) error{InvalidEnumTag}!SpecId {
        return std.meta.intToEnum(OptimismSpecId, num);
    }
};
