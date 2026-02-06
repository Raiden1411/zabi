const specification = @import("specification.zig");

const SpecId = specification.SpecId;

/// Fork-gated opcode subset that requires explicit specification checks.
pub const GatedOpcode = enum(u8) {
    REVERT = 0xfd,
    RETURNDATASIZE = 0x3d,
    CHAINID = 0x46,
    SELFBALANCE = 0x47,
    CREATE2 = 0xf5,
    DELEGATECALL = 0xf4,
    STATICCALL = 0xfa,
    BLOBHASH = 0x49,
    BLOBBASEFEE = 0x4a,
    TLOAD = 0x5c,
    TSTORE = 0x5d,
    MCOPY = 0x5e,
    PUSH0 = 0x5f,

    /// Returns true when this opcode is enabled for the provided specification id.
    ///
    /// Prague currently aliases Cancun behavior in this codebase.
    pub fn isEnabled(self: GatedOpcode, spec_id: SpecId) bool {
        const min_spec: SpecId = switch (self) {
            .REVERT => .BYZANTIUM,
            .RETURNDATASIZE => .BYZANTIUM,
            .CHAINID => .ISTANBUL,
            .SELFBALANCE => .ISTANBUL,
            .CREATE2 => .PETERSBURG,
            .DELEGATECALL => .HOMESTEAD,
            .STATICCALL => .BYZANTIUM,
            .BLOBHASH => .CANCUN,
            .BLOBBASEFEE => .CANCUN,
            .TLOAD => .CANCUN,
            .TSTORE => .CANCUN,
            .MCOPY => .CANCUN,
            .PUSH0 => .SHANGHAI,
        };

        return spec_id.enabled(min_spec);
    }
};
