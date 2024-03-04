const c = @import("c.zig");
const std = @import("std");

const Allocator = std.mem.Allocator;
const Sha256 = std.crypto.hash.sha2.Sha256;
const Tuple = std.meta.Tuple;

pub const Eip4844Errors = error{ ExpectedZByte, ExpectJsonFile, ExpectedBlobData, SetupMustBeInitialized, SetupAlreadyLoaded, InvalidProof, InvalidG1Length, InvalidG2Length, InvalidSize };

pub const Blob = [c.BYTES_PER_BLOB]u8;
pub const KZGProof = [c.BYTES_PER_PROOF]u8;
pub const KZGCommitment = [c.BYTES_PER_COMMITMENT]u8;
pub const KZGSettings = c.KZGSettings;

pub const KZGProofResult = struct { proof: KZGProof, y: [c.BYTES_PER_FIELD_ELEMENT]u8 };

pub const KZG4844 = @This();

pub const BYTES_PER_G1_POINT: usize = 48;

pub const BYTES_PER_G2_POINT: usize = 96;

pub const NUM_G2_POINTS = 65;

pub const BLOBS_PER_TRANSACTION = 2;

pub const MAX_BYTES_PER_TX = c.BYTES_PER_BLOB * BLOBS_PER_TRANSACTION - 1;

pub const JsonTrustedSetup = struct {
    g1_monomial: []const []const u8,
    g2_monomial: []const []const u8,
};

pub const Sidecar = struct {
    blob: Blob,
    commitment: KZGCommitment,
    proof: KZGProof,
};

pub const Sidecars = []const Sidecar;

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

fn transformJsonFileFromHex(self: *KZG4844, allocator: Allocator, path: []const u8) ![]const u8 {
    _ = self;

    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const end = try file.getEndPos();
    const buffer = try allocator.alloc(u8, end);
    defer allocator.free(buffer);

    var buf_io = std.io.bufferedReader(file.reader());
    var reader = buf_io.reader();

    _ = try reader.readAll(buffer);
    const parsed = try std.json.parseFromSlice(JsonTrustedSetup, allocator, buffer, .{ .allocate = .alloc_if_needed, .ignore_unknown_fields = true });
    defer parsed.deinit();

    var g_points = std.ArrayList(u8).init(allocator);
    var writer = g_points.writer();

    for (parsed.value.g1_monomial) |g1_point| {
        // Removes "0x"
        try writer.writeAll(g1_point[2..]);
        try writer.writeAll("\n");
    }

    for (parsed.value.g2_monomial, 0..) |g2_point, i| {
        // Removes "0x"
        try writer.writeAll(g2_point[2..]);
        if (i != 64)
            try writer.writeAll("\n");
    }

    return try g_points.toOwnedSlice();
}
/// Transform the g1_monomial and g2_monomial into their g1 and g2 points representation
/// so that they can be used by the `initTrustedSetup` method
pub fn transformJsonFileToBytes(self: *KZG4844, allocator: Allocator, path: []const u8) !Tuple(&[_]type{ [][BYTES_PER_G1_POINT]u8, []const [BYTES_PER_G2_POINT]u8 }) {
    _ = self;

    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const end = try file.getEndPos();
    const buffer = try allocator.alloc(u8, end);
    defer allocator.free(buffer);

    var buf_io = std.io.bufferedReader(file.reader());
    var reader = buf_io.reader();

    _ = try reader.readAll(buffer);
    const parsed = try std.json.parseFromSlice(JsonTrustedSetup, allocator, buffer, .{ .allocate = .alloc_if_needed, .ignore_unknown_fields = true });
    defer parsed.deinit();

    var list_g1 = try std.ArrayList([BYTES_PER_G1_POINT]u8).initCapacity(allocator, parsed.value.g1_monomial.len);
    errdefer list_g1.deinit();

    for (parsed.value.g1_monomial) |g1_point| {
        var buffer_g1: [BYTES_PER_G1_POINT]u8 = undefined;
        _ = try std.fmt.hexToBytes(&buffer_g1, g1_point[2..]);

        try list_g1.append(buffer_g1);
    }

    var list_g2 = try std.ArrayList([BYTES_PER_G2_POINT]u8).initCapacity(allocator, parsed.value.g2_monomial.len);
    errdefer list_g2.deinit();

    for (parsed.value.g2_monomial) |g2_point| {
        var buffer_g2: [BYTES_PER_G2_POINT]u8 = undefined;
        _ = try std.fmt.hexToBytes(&buffer_g2, g2_point[2..]);

        try list_g2.append(buffer_g2);
    }

    return .{ try list_g1.toOwnedSlice(), try list_g2.toOwnedSlice() };
}
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
/// Inits the trusted setup from a json file
pub fn initTrustedSetupFromJsonFile(self: *KZG4844, allocator: Allocator, path: []const u8) !void {
    if (!std.mem.endsWith(u8, path, ".json"))
        return error.ExpectJsonFile;

    const g_points = try self.transformJsonFileFromHex(allocator, path);
    defer allocator.free(g_points);
    const buffer = try allocator.allocSentinel(u8, path.len - 1, 0);
    defer allocator.free(buffer);

    _ = std.mem.replace(u8, path, ".json", ".txt", buffer);
    var output = try std.fs.cwd().createFile(buffer, .{});
    defer output.close();

    try output.writeAll("4096");
    try output.writeAll("\n65\n");
    try output.writeAll(g_points);

    try self.initTrustedSetupFromFile(buffer);
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
/// Converts slices to blobs.
/// Caller owns the allocated memory.
pub fn bytesToBlobs(self: *KZG4844, allocator: Allocator, bytes: []const u8) ![]const Blob {
    if (bytes.len > MAX_BYTES_PER_TX)
        return error.InvalidBlobSize;

    if (bytes.len == 0)
        return error.EmptyBytes;

    const len: usize = @intFromFloat(@ceil(@as(f32, @floatFromInt(bytes.len)) / @as(f32, @floatFromInt(self.bytes_per_blob))));

    var buffer = try allocator.alloc(u8, len * self.bytes_per_blob);
    defer allocator.free(buffer);
    // Zero pads the data.
    @memset(buffer, 0);
    @memcpy(buffer[0..bytes.len], bytes[0..bytes.len]);
    buffer[bytes.len] = 0x80;

    var list = try std.ArrayList([c.BYTES_PER_BLOB]u8).initCapacity(allocator, len);
    errdefer list.deinit();

    for (0..len) |i| {
        const blob_buffer = buffer[i * self.bytes_per_blob .. (i + 1) * self.bytes_per_blob];
        try list.append(try self.bytesToBlob(blob_buffer[0..c.BYTES_PER_BLOB].*));
    }

    return try list.toOwnedSlice();
}
/// Converts an array of blob sized bytes into a `Blob`
pub fn bytesToBlob(self: *KZG4844, data: [c.BYTES_PER_BLOB]u8) !Blob {
    var blob: Blob = undefined;
    for (0..self.field_elements_per_blob) |i| {
        var subset: [32]u8 = undefined;
        @memset(subset[0..], 0);
        @memcpy(subset[0..31], data[i * 31 .. (i + 1) * 31]);
        @memcpy(blob[i * 32 .. (i * 32) + 32], subset[0..]);
    }

    return blob;
}

pub const SideCarOpts = struct {
    data: ?[]const u8 = null,
    blobs: ?[]const Blob = null,
    commitments: ?[]const KZGCommitment = null,
    proofs: ?[]const KZGProof = null,
    z_bytes: ?[]const [32]u8 = null,
};
/// Bundles together the blobs, commitments and proofs into a sidecar.
pub fn toSidecars(self: *KZG4844, allocator: Allocator, opts: SideCarOpts) !Sidecars {
    const blobs = opts.blobs orelse try self.bytesToBlobs(allocator, opts.data orelse return error.ExpectedBlobData);
    const commitments = opts.commitments orelse try self.blobsToKZGCommitment(allocator, blobs);
    const proofs = opts.proofs orelse try self.computeKZGProofs(blobs, opts.z_bytes orelse return error.ExpectedZBytes);

    var list_sidecar = try std.ArrayList(Sidecar).initCapacity(allocator, blobs.len);
    errdefer list_sidecar.deinit();

    for (blobs, commitments, proofs) |blob, commitment, proof| {
        try list_sidecar.append(.{ .blob = blob, .commitment = commitment, .proof = proof });
    }

    return list_sidecar.toOwnedSlice();
}
/// Creates the blobVersioned hashes
pub fn sidecarsToVersionedHash(self: *KZG4844, allocator: Allocator, sidecars: Sidecars, versions: []const ?u8) ![]const [Sha256.digest_length]u8 {
    var list = try std.ArrayList([Sha256.digest_length]u8).initCapacity(allocator, sidecars.commitments.len);
    errdefer list.deinit();

    for (sidecars, versions) |sidecar, version| {
        try list.append(try self.commitmentToVersionedHash(sidecar.commitment, version));
    }

    return try list.toOwnedSlice();
}
/// Converts blobs to KZGCommitments.
/// Caller owns the allocated memory.
pub fn blobsToKZGCommitment(self: *KZG4844, allocator: Allocator, blobs: []const Blob) ![]const KZGCommitment {
    var list = try std.ArrayList(KZGCommitment).initCapacity(allocator, blobs.len);
    errdefer list.deinit();

    for (blobs) |blob| {
        try list.append(try self.blobToKZGCommitment(blob));
    }

    return try list.toOwnedSlice();
}
/// Hashes a slice of KZGCommitments to their version hashes
pub fn commitmentsToVersionedHash(self: *KZG4844, allocator: Allocator, commitments: []const KZGCommitment, version: ?u8) ![]const [Sha256.digest_length]u8 {
    var list = try std.ArrayList([Sha256.digest_length]u8).initCapacity(allocator, commitments.len);
    errdefer list.deinit();

    for (commitments) |commitment| {
        try list.append(try self.commitmentToVersionedHash(commitment, version));
    }

    return try list.toOwnedSlice();
}
/// Hashes a KZGCommitment.
pub fn commitmentToVersionedHash(self: *KZG4844, commitment: KZGCommitment, version: ?u8) ![Sha256.digest_length]u8 {
    _ = self;

    const ver = version orelse 1;
    var buffer: [Sha256.digest_length]u8 = undefined;
    Sha256.hash(&commitment, &buffer, .{});
    buffer[0] = ver;

    return buffer;
}
pub fn blobsToKZGProofs(self: *KZG4844, allocator: Allocator, blobs: []const Blob, z_bytes: []const [32]u8) ![]const KZGProof {
    var proofs = try std.ArrayList(KZGProof).initCapacity(allocator, blobs.len);
    errdefer proofs.deinit();

    for (blobs, z_bytes) |blob, z_byte| {
        const computed = try self.computeKZGProof(blob, z_byte);
        try proofs.append(computed.proof);
    }

    return proofs.toOwnedSlice();
}
/// Converts a blob to a KZGCommitment.
pub fn blobToKZGCommitment(self: *KZG4844, blob: Blob) !KZGCommitment {
    if (!self.loaded)
        return error.SetupMustBeInitialized;

    var commitment: c.Bytes48 = .{ .bytes = undefined };

    if (c.blob_to_kzg_commitment(&commitment, &.{ .bytes = blob }, &self.settings) != c.C_KZG_OK)
        return error.FailedToConvertBlobToCommitment;

    return commitment.bytes;
}
/// Computes a given KZGProof from a blob
pub fn computeKZGProof(self: *KZG4844, blob: Blob, bytes: [32]u8) !KZGProofResult {
    if (!self.loaded)
        return error.SetupMustBeInitialized;

    var proof: c.KZGProof = .{ .bytes = undefined };
    var y: c.Bytes32 = .{ .bytes = undefined };

    if (c.compute_kzg_proof(&proof, &y, &.{ .bytes = blob }, &.{ .bytes = bytes }, &self.settings) != c.C_KZG_OK)
        return error.FailedToComputeKZGProof;

    return .{ .proof = proof.bytes, .y = y.bytes };
}
/// Verifies a KZGProof from a commitment.
pub fn verifyKZGProof(self: *KZG4844, commitment_bytes: KZGCommitment, z_bytes: [32]u8, y_bytes: [32]u8, proof_bytes: KZGProof) !bool {
    if (!self.loaded)
        return error.SetupMustBeInitialized;

    var verify = false;

    if (c.verify_kzg_proof(&verify, &.{ .bytes = commitment_bytes }, &.{ .bytes = z_bytes }, &.{ .bytes = y_bytes }, &.{ .bytes = proof_bytes }, &self.settings) != c.C_KZG_OK)
        return error.InvalidProof;

    return verify;
}
/// Verifies a Blob KZG Proof from a commitment.
pub fn verifyBlobKZGProof(self: *KZG4844, blob: Blob, commitment_bytes: KZGCommitment, proof_bytes: KZGProof) !bool {
    if (!self.loaded)
        return error.SetupMustBeInitialized;

    var verify = false;

    if (c.verify_blob_kzg_proof(&verify, &.{ .bytes = blob }, &.{ .bytes = commitment_bytes }, &.{ .bytes = proof_bytes }, &self.settings) != c.C_KZG_OK)
        return error.InvalidProof;

    return verify;
}
/// Verifies a batch of blob KZG proofs from an array commitments and blobs.
pub fn verifyBlobKZGProofBatch(self: *KZG4844, blobs: []c.Blob, commitment_bytes: []c.KZGCommitment, proof_bytes: []c.KZGProof) !bool {
    if (!self.loaded)
        return error.SetupMustBeInitialized;

    var verify = false;

    if (blobs.len != commitment_bytes.len or blobs.len != proof_bytes.len)
        return error.InvalidSize;

    if (c.verify_blob_kzg_proof_batch(&verify, @ptrCast(@alignCast(blobs)), @ptrCast(@alignCast(commitment_bytes)), @ptrCast(@alignCast(proof_bytes)), blobs.len, &self.settings) != c.C_KZG_OK)
        return error.InvalidProof;

    return verify;
}

test "Compute Hash" {
    var trusted: KZG4844 = .{};
    try trusted.initTrustedSetupFromFile("./tests/trusted_setup.txt");
    defer trusted.deinitTrustSetupFile();

    const bytes = "picklerick" ** 20000;
    const blobs = try trusted.bytesToBlobs(std.testing.allocator, bytes);
    defer std.testing.allocator.free(blobs);

    const commitments = try trusted.blobsToKZGCommitment(std.testing.allocator, blobs);
    defer std.testing.allocator.free(commitments);

    const hashes = try trusted.commitmentsToVersionedHash(std.testing.allocator, commitments, null);
    defer std.testing.allocator.free(hashes);
}
test "BytesToBlob" {
    const bytes = "Baby don't hurt me no more" ** 10000;
    var trusted: KZG4844 = .{};

    const blobs = try trusted.bytesToBlobs(std.testing.allocator, bytes);
    defer std.testing.allocator.free(blobs);
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
