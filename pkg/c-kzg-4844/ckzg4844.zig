const c = @import("c.zig");
const std = @import("std");

pub const Eip4844Errors = error{ SetupAlreadyLoaded, InvalidProof, InvalidG1Length, InvalidG2Length, InvalidSize };

pub const Blob = [c.BYTES_PER_BLOB]u8;
pub const KZGProof = [48]u8;
pub const KZGCommitment = [48]u8;
pub const KZGSettings = c.KZGSettings;

pub const KZGProofResult = struct { proof: KZGProof, y: [32]u8 };

pub const KZG4844 = @This();

pub const BYTES_PER_G1_POINT: usize = 48;

pub const BYTES_PER_G2_POINT: usize = 96;

pub const NUM_G2_POINTS = 65;

/// Amount of bytes per blob
bytes_per_blob: u64 = c.BYTES_PER_BLOB,
/// Amount of bytes per commitment
bytes_per_commitment: u64 = c.BYTES_PER_COMMITMENT,
/// Amount of bytes per field element
bytes_per_field_element: u64 = c.BYTES_PER_FIELD_ELEMENT,
/// Amount of bytes per kzg proof
bytes_per_proof: u64 = c.BYTES_PER_PROOF,
/// Amount of elements per blob
field_elements_per_blob: u64 = c.FIELD_ELEMENTS_PER_BLOB,
/// KZGSettings used for the configuration
settings: KZGSettings = .{},
/// If the trusted setup has already loaded.
loaded: bool = false,

/// Inits the trusted setup from a 2d array of g1 and g2 bytes.
pub fn initTrustedSetup(self: *KZG4844, g1: [][BYTES_PER_G1_POINT]u8, g2: [][BYTES_PER_G2_POINT]u8) !void {
    if (self.loaded)
        return error.SetupAlreadyLoaded;

    if (g1.len != self.field_elements_per_blob)
        return error.InvalidG1Length;

    if (g2.len != NUM_G2_POINTS)
        return error.InvalidG2Length;

    if (c.load_trusted_setup(&self.settings, @ptrCast(@alignCast(g1)), g1.len, @ptrCast(@alignCast(g2)), g2.len) != c.C_KZG_OK)
        return error.FailedToLoadSetup;

    self.loaded = true;
}
/// Inits the trusted setup from a trusted setup file.
pub fn initTrustedSetupFromFile(self: *KZG4844, file_path: [*:0]const u8) !void {
    if (self.loaded)
        return error.SetupAlreadyLoaded;

    const file = c.fopen(file_path, "r");

    if (c.load_trusted_setup_file(&self.settings, file) != c.C_KZG_OK)
        return error.FailedToLoadSetup;

    self.loaded = true;
}
/// Frees the trusted setup. Will panic if the setup was never loaded.
pub fn deinitTrustSetupFile(self: *KZG4844) void {
    if (!self.loaded)
        @panic("Setup is not initialized yet");

    c.free_trusted_setup(&self.settings);
    self.loaded = false;
}
/// Converts a blob to a KZGCommitment.
pub fn blobToKZGCommitment(self: *KZG4844, blob: Blob) !KZGCommitment {
    var commitment: c.Bytes48 = .{ .bytes = undefined };

    if (c.blob_to_kzg_commitment(&commitment, &.{ .bytes = blob }, &self.settings) != c.C_KZG_OK)
        return error.FailedToConvertBlobToCommitment;

    return commitment.bytes;
}
/// Computes a given KZGProof from a blob
pub fn computeKZGProof(self: *KZG4844, blob: Blob, bytes: [32]u8) !KZGProofResult {
    var proof: c.KZGProof = .{ .bytes = undefined };
    var y: c.Bytes32 = .{ .bytes = undefined };

    if (c.compute_kzg_proof(&proof, &y, &.{ .bytes = blob }, &.{ .bytes = bytes }, &self.settings) != c.C_KZG_OK)
        return error.FailedToComputeKZGProof;

    return .{ .proof = proof.bytes, .y = y.bytes };
}
/// Verifies a KZGProof from a commitment.
pub fn verifyKZGProof(self: *KZG4844, commitment_bytes: KZGCommitment, z_bytes: [32]u8, y_bytes: [32]u8, proof_bytes: KZGProof) !bool {
    var verify = false;

    if (c.verify_kzg_proof(&verify, &.{ .bytes = commitment_bytes }, &.{ .bytes = z_bytes }, &.{ .bytes = y_bytes }, &.{ .bytes = proof_bytes }, &self.settings) != c.C_KZG_OK)
        return error.InvalidProof;

    return verify;
}
/// Verifies a Blob KZG Proof from a commitment.
pub fn verifyBlobKZGProof(self: *KZG4844, blob: Blob, commitment_bytes: KZGCommitment, proof_bytes: KZGProof) !bool {
    var verify = false;

    if (c.verify_blob_kzg_proof(&verify, &.{ .bytes = blob }, &.{ .bytes = commitment_bytes }, &.{ .bytes = proof_bytes }, &self.settings) != c.C_KZG_OK)
        return error.InvalidProof;

    return verify;
}
/// Verifies a batch of blob KZG proofs from an array commitments and blobs.
pub fn verifyBlobKZGProofBatch(self: *KZG4844, blobs: []c.Blob, commitment_bytes: []c.KZGCommitment, proof_bytes: []c.KZGProof) !bool {
    var verify = false;

    if (blobs.len != commitment_bytes.len or blobs.len != proof_bytes.len)
        return error.InvalidSize;

    if (c.verify_blob_kzg_proof_batch(&verify, @ptrCast(@alignCast(blobs)), @ptrCast(@alignCast(commitment_bytes)), @ptrCast(@alignCast(proof_bytes)), blobs.len, &self.settings) != c.C_KZG_OK)
        return error.InvalidProof;

    return verify;
}

test "Blob_to_kzg_commitment" {
    var trusted: KZG4844 = .{};
    try trusted.initTrustedSetupFromFile("./tests/trusted_setup.txt");
    defer trusted.deinitTrustSetupFile();

    var file = try std.fs.cwd().openFile("./tests/blob_to_kzg_commitment.json", .{});
    defer file.close();

    const end = try file.getEndPos();
    const buffer = try std.testing.allocator.alloc(u8, end);
    defer std.testing.allocator.free(buffer);
    var buf_io = std.io.bufferedReader(file.reader());
    var reader = buf_io.reader();

    const Type = struct {
        input: struct {
            blob: []const u8,
        },
        output: []const u8,
    };
    _ = try reader.readAll(buffer);
    const parsed = try std.json.parseFromSlice(Type, std.testing.allocator, buffer, .{});
    defer parsed.deinit();

    var decoded: Blob = undefined;
    _ = try std.fmt.hexToBytes(&decoded, parsed.value.input.blob[2..]);
    const commit = try trusted.blobToKZGCommitment(decoded);

    try std.testing.expectFmt(parsed.value.output, "0x{s}", .{std.fmt.fmtSliceHexLower(commit[0..])});
}

test "Compute_kzg_proof" {
    var trusted: KZG4844 = .{};
    try trusted.initTrustedSetupFromFile("./tests/trusted_setup.txt");
    defer trusted.deinitTrustSetupFile();

    var file = try std.fs.cwd().openFile("./tests/compute_kzg_proof.json", .{});
    defer file.close();

    const end = try file.getEndPos();
    const buffer = try std.testing.allocator.alloc(u8, end);
    defer std.testing.allocator.free(buffer);
    var buf_io = std.io.bufferedReader(file.reader());
    var reader = buf_io.reader();

    const Type = struct {
        input: struct { blob: []const u8, z: []const u8 },
        output: []const []const u8,
    };
    _ = try reader.readAll(buffer);
    const parsed = try std.json.parseFromSlice(Type, std.testing.allocator, buffer, .{});
    defer parsed.deinit();

    var decoded: Blob = undefined;
    _ = try std.fmt.hexToBytes(&decoded, parsed.value.input.blob[2..]);
    var z: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(&z, parsed.value.input.z[2..]);
    const proof = try trusted.computeKZGProof(decoded, z);

    try std.testing.expectFmt(parsed.value.output[0], "0x{s}", .{std.fmt.fmtSliceHexLower(proof.proof[0..])});
    try std.testing.expectFmt(parsed.value.output[1], "0x{s}", .{std.fmt.fmtSliceHexLower(proof.y[0..])});
}

test "Verify_kzg_proof" {
    var trusted: KZG4844 = .{};
    try trusted.initTrustedSetupFromFile("./tests/trusted_setup.txt");
    defer trusted.deinitTrustSetupFile();

    var file = try std.fs.cwd().openFile("./tests/verify_kzg_proof.json", .{});
    defer file.close();

    const end = try file.getEndPos();
    const buffer = try std.testing.allocator.alloc(u8, end);
    defer std.testing.allocator.free(buffer);
    var buf_io = std.io.bufferedReader(file.reader());
    var reader = buf_io.reader();

    const Type = struct {
        input: struct { commitment: []const u8, z: []const u8, y: []const u8, proof: []const u8 },
        output: bool,
    };
    _ = try reader.readAll(buffer);
    const parsed = try std.json.parseFromSlice(Type, std.testing.allocator, buffer, .{});
    defer parsed.deinit();

    var commitment: [48]u8 = undefined;
    _ = try std.fmt.hexToBytes(&commitment, parsed.value.input.commitment[2..]);
    var proof: [48]u8 = undefined;
    _ = try std.fmt.hexToBytes(&proof, parsed.value.input.proof[2..]);
    var y: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(&y, parsed.value.input.y[2..]);
    var z: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(&z, parsed.value.input.z[2..]);
    const verify = try trusted.verifyKZGProof(commitment, z, y, proof);

    try std.testing.expect(parsed.value.output == verify);
}

test "Verify_blob_kzg_proof" {
    var trusted: KZG4844 = .{};
    try trusted.initTrustedSetupFromFile("./tests/trusted_setup.txt");
    defer trusted.deinitTrustSetupFile();

    var file = try std.fs.cwd().openFile("./tests/verify_blob_kzg_proof.json", .{});
    defer file.close();

    const end = try file.getEndPos();
    const buffer = try std.testing.allocator.alloc(u8, end);
    defer std.testing.allocator.free(buffer);
    var buf_io = std.io.bufferedReader(file.reader());
    var reader = buf_io.reader();

    const Type = struct {
        input: struct { blob: []const u8, commitment: []const u8, proof: []const u8 },
        output: bool,
    };
    _ = try reader.readAll(buffer);
    const parsed = try std.json.parseFromSlice(Type, std.testing.allocator, buffer, .{});
    defer parsed.deinit();

    var decoded: Blob = undefined;
    _ = try std.fmt.hexToBytes(&decoded, parsed.value.input.blob[2..]);
    var commitment: [48]u8 = undefined;
    _ = try std.fmt.hexToBytes(&commitment, parsed.value.input.commitment[2..]);
    var proof: [48]u8 = undefined;
    _ = try std.fmt.hexToBytes(&proof, parsed.value.input.proof[2..]);
    const verify = try trusted.verifyBlobKZGProof(decoded, commitment, proof);

    try std.testing.expect(parsed.value.output == verify);
}

test "Verify_blob_kzg_proof_batch" {
    var trusted: KZG4844 = .{};
    try trusted.initTrustedSetupFromFile("./tests/trusted_setup.txt");
    defer trusted.deinitTrustSetupFile();

    var file = try std.fs.cwd().openFile("./tests/verify_blob_kzg_proof_batch.json", .{});
    defer file.close();

    const end = try file.getEndPos();
    const buffer = try std.testing.allocator.alloc(u8, end);
    defer std.testing.allocator.free(buffer);
    var buf_io = std.io.bufferedReader(file.reader());
    var reader = buf_io.reader();

    const Type = struct {
        input: struct { blobs: []const []const u8, commitments: []const []const u8, proofs: []const []const u8 },
        output: bool,
    };
    _ = try reader.readAll(buffer);
    const parsed = try std.json.parseFromSlice(Type, std.testing.allocator, buffer, .{});
    defer parsed.deinit();

    var decoded: Blob = undefined;
    _ = try std.fmt.hexToBytes(&decoded, parsed.value.input.blobs[0][2..]);
    var commitment: [48]u8 = undefined;
    _ = try std.fmt.hexToBytes(&commitment, parsed.value.input.commitments[0][2..]);
    var proof: [48]u8 = undefined;
    _ = try std.fmt.hexToBytes(&proof, parsed.value.input.proofs[0][2..]);
    var decoded1: Blob = undefined;
    _ = try std.fmt.hexToBytes(&decoded1, parsed.value.input.blobs[1][2..]);
    var commitment1: [48]u8 = undefined;
    _ = try std.fmt.hexToBytes(&commitment1, parsed.value.input.commitments[1][2..]);
    var proof1: [48]u8 = undefined;
    _ = try std.fmt.hexToBytes(&proof1, parsed.value.input.proofs[1][2..]);
    var decoded2: Blob = undefined;
    _ = try std.fmt.hexToBytes(&decoded2, parsed.value.input.blobs[2][2..]);
    var commitment2: [48]u8 = undefined;
    _ = try std.fmt.hexToBytes(&commitment2, parsed.value.input.commitments[2][2..]);
    var proof2: [48]u8 = undefined;
    _ = try std.fmt.hexToBytes(&proof2, parsed.value.input.proofs[2][2..]);

    var blob_struct = [_]c.Blob{ .{ .bytes = decoded }, .{ .bytes = decoded1 }, .{ .bytes = decoded2 } };
    var commit_struct = [_]c.Bytes48{ .{ .bytes = commitment }, .{ .bytes = commitment1 }, .{ .bytes = commitment2 } };
    var proof_struct = [_]c.Bytes48{ .{ .bytes = proof }, .{ .bytes = proof1 }, .{ .bytes = proof2 } };

    const verify = try trusted.verifyBlobKZGProofBatch(blob_struct[0..], commit_struct[0..], proof_struct[0..]);

    try std.testing.expect(parsed.value.output == verify);
}
