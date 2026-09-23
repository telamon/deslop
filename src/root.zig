//! By convention, root.zig is the root source file when making a package.
const std = @import("std");
const Io = std.Io;

/// The harness binary to use when `HARNESS_BIN` is not explicitly set.
/// A bare name is resolved through `PATH` at spawn time.
pub const default_harness_bin: []const u8 = "harness";

/// Resolve the path of the harness binary.
///
/// An explicitly set, non-empty `HARNESS_BIN` environment variable
/// overrides the default; otherwise `default_harness_bin` is returned.
pub fn harnessBin(env: *std.process.Environ.Map) []const u8 {
    if (env.get("HARNESS_BIN")) |bin| {
        if (bin.len > 0) return bin;
    }
    return default_harness_bin;
}

/// This is a documentation comment to explain the `printAnotherMessage` function below.
///
/// Accepting an `Io.Writer` instance is a handy way to write reusable code.
pub fn printAnotherMessage(writer: *Io.Writer) Io.Writer.Error!void {
    try writer.print("Run `zig build test` to run the tests.\n", .{});
}

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "basic add functionality" {
    try std.testing.expect(add(3, 7) == 10);
}
