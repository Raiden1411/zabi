pub const MIN_BLOB_GASPRICE = 1;
pub const BLOB_GASPRICE_UPDATE_FRACTION = 3;
pub const GAS_PER_BLOB = 1 << 17;
pub const VERSIONED_HASH_VERSION_KZG = 0x01;
pub const TARGET_BLOB_NUMBER_PER_BLOCK = 3;
pub const MAX_BLOB_NUMBER_PER_BLOCK = 2 * TARGET_BLOB_NUMBER_PER_BLOCK;
pub const QUICK_STEP: u64 = 2;
pub const FASTEST_STEP: u64 = 3;
pub const FAST_STEP: u64 = 5;
pub const MID_STEP: u64 = 8;
pub const SLOW_STEP: u64 = 10;
pub const EXT_STEP: u64 = 20;

pub const JUMPDEST: u64 = 1;
pub const SELFDESTRUCT: i64 = 24000;
pub const CREATE: u64 = 32000;
pub const CALLVALUE: u64 = 9000;
pub const NEWACCOUNT: u64 = 25000;
pub const LOG: u64 = 375;
pub const LOGDATA: u64 = 8;
pub const LOGTOPIC: u64 = 375;
pub const KECCAK256: u64 = 30;
pub const KECCAK256WORD: u64 = 6;
pub const BLOCKHASH: u64 = 20;
pub const CODEDEPOSIT: u64 = 200;
pub const CONDITION_JUMP_GAS: u64 = 4;
pub const RETF_GAS: u64 = 4;
pub const DATA_LOAD_GAS: u64 = 4;

/// EIP-1884: Repricing for trie-size-dependent opcodes
pub const ISTANBUL_SLOAD_GAS: u64 = 800;
pub const SSTORE_SET: u64 = 20000;
pub const SSTORE_RESET: u64 = 5000;
pub const REFUND_SSTORE_CLEARS: i64 = 15000;

pub const TRANSACTION: u64 = 21000;
pub const TRANSACTION_ZERO_DATA: u64 = 4;
pub const TRANSACTION_NON_ZERO_DATA_INIT: u64 = 16;
pub const TRANSACTION_NON_ZERO_DATA_FRONTIER: u64 = 68;

pub const EOF_CREATE_GAS: u64 = 32000;

// berlin eip2929 constants
pub const ACCESS_LIST_ADDRESS: u64 = 2400;
pub const ACCESS_LIST_STORAGE_KEY: u64 = 1900;
pub const COLD_SLOAD_COST: u64 = 2100;
pub const COLD_ACCOUNT_ACCESS_COST: u64 = 2600;
pub const WARM_STORAGE_READ_COST: u64 = 100;
pub const WARM_SSTORE_RESET: u64 = SSTORE_RESET - COLD_SLOAD_COST;

/// EIP-3860 : Limit and meter initcode
pub const INITCODE_WORD_COST: u64 = 2;

pub const CALL_STIPEND: u64 = 2300;
pub const EMPTY_HASH = [_]u8{ 0xc5, 0xd2, 0x46, 0x01, 0x86, 0xf7, 0x23, 0x3c, 0x92, 0x7e, 0x7d, 0xb2, 0xdc, 0xc7, 0x03, 0xc0, 0xe5, 0x00, 0xb6, 0x53, 0xca, 0x82, 0x27, 0x3b, 0x7b, 0xfa, 0xd8, 0x04, 0x5d, 0x85, 0xa4, 0x70 };
