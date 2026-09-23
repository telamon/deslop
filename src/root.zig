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

// ---------------------------------------------------------------------------
// CLI (see draft.md §Manual)
// ---------------------------------------------------------------------------

/// Parsed command line state.
pub const Config = struct {
    /// Positional FILE; null means read STDIN.
    file: ?[]const u8 = null,
    /// `-n NUMBER`: single line run.
    line: ?u32 = null,
    /// `-t TAGFILE`: whitespace delimited tags, ordered good -> bad.
    tagfile: ?[]const u8 = null,
    /// `-r PATH`: recursive grade (parsed, but not implemented yet).
    recursive: ?[]const u8 = null,
    /// `--json|-j`: structured output.
    json: bool = false,
    /// `-l`: LSP server mode.
    lsp: bool = false,
    /// `-h|--help`: print usage and exit.
    help: bool = false,
};

pub const ParseError = error{
    UnknownOption,
    MissingValue,
    InvalidNumber,
    TooManyPositionals,
};

pub const help_text =
    \\usage: xorcery [options] [FILE]
    \\  when no FILE is provided, context is read from STDIN
    \\
    \\  Default mode:
    \\    Good vs. Bad: 1.0 ... -1.0
    \\
    \\  Categorical Mode:
    \\    Takes an additional list of categories as input,
    \\    see tag option "-t"
    \\
    \\  -n NUMBER             Single line run
    \\  -t TAGFILE            Read whitespace delimited tags from TAGFILE
    \\  -r PATH               Recursive grade path (not implemented yet)
    \\  --json|-j             Output structured json
    \\  -l                    Start LSP server mode (-n and FILE ignored)
    \\
    \\  Code-Xorcery uses harness, refer to https://github.com/telamon/harness
    \\  for inference backend configuration.
    \\
    \\  Environment options:
    \\
    \\  HARNESS_BIN=/usr/bin/harness
    \\
;

/// Parse argv (without program name) into a `Config`.
/// Value-taking options require a separate argument (`-n 5`, not `-n5`).
/// `--` ends option parsing; everything after it is positional.
pub fn parseArgs(args: []const []const u8) ParseError!Config {
    var cfg: Config = .{};
    var only_positional = false;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (!only_positional and std.mem.eql(u8, arg, "--")) {
            only_positional = true;
        } else if (!only_positional and arg.len > 1 and arg[0] == '-') {
            if (std.mem.eql(u8, arg, "-n")) {
                i += 1;
                if (i >= args.len) return error.MissingValue;
                const n = std.fmt.parseInt(u32, args[i], 10) catch return error.InvalidNumber;
                if (n == 0) return error.InvalidNumber; // lines are 1-based
                cfg.line = n;
            } else if (std.mem.eql(u8, arg, "-t")) {
                i += 1;
                if (i >= args.len) return error.MissingValue;
                cfg.tagfile = args[i];
            } else if (std.mem.eql(u8, arg, "-r")) {
                i += 1;
                if (i >= args.len) return error.MissingValue;
                cfg.recursive = args[i];
            } else if (std.mem.eql(u8, arg, "-j") or std.mem.eql(u8, arg, "--json")) {
                cfg.json = true;
            } else if (std.mem.eql(u8, arg, "-l")) {
                cfg.lsp = true;
            } else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
                cfg.help = true;
            } else {
                return error.UnknownOption;
            }
        } else {
            if (cfg.file != null) return error.TooManyPositionals;
            cfg.file = arg;
        }
    }
    return cfg;
}

test "parseArgs: defaults" {
    const cfg = try parseArgs(&.{});
    try std.testing.expect(cfg.file == null);
    try std.testing.expect(cfg.line == null);
    try std.testing.expect(cfg.tagfile == null);
    try std.testing.expect(cfg.recursive == null);
    try std.testing.expect(!cfg.json);
    try std.testing.expect(!cfg.lsp);
    try std.testing.expect(!cfg.help);
}

test "parseArgs: positional file" {
    const cfg = try parseArgs(&.{"source.c"});
    try std.testing.expectEqualStrings("source.c", cfg.file.?);
}

test "parseArgs: single line and tagfile" {
    const cfg = try parseArgs(&.{ "-n", "5", "-t", "tags.txt", "src.c" });
    try std.testing.expectEqual(@as(u32, 5), cfg.line.?);
    try std.testing.expectEqualStrings("tags.txt", cfg.tagfile.?);
    try std.testing.expectEqualStrings("src.c", cfg.file.?);
}

test "parseArgs: json and lsp flags" {
    const cfg = try parseArgs(&.{ "--json", "-j", "-l", "--help" });
    try std.testing.expect(cfg.json);
    try std.testing.expect(cfg.lsp);
    try std.testing.expect(cfg.help);
}

test "parseArgs: -r parsed but unimplemented" {
    const cfg = try parseArgs(&.{ "-r", "src/" });
    try std.testing.expectEqualStrings("src/", cfg.recursive.?);
}

test "parseArgs: -- terminator makes the rest positional" {
    const cfg = try parseArgs(&.{ "--", "-x" });
    try std.testing.expectEqualStrings("-x", cfg.file.?);
}

test "parseArgs: errors" {
    try std.testing.expectError(ParseError.UnknownOption, parseArgs(&.{"-x"}));
    try std.testing.expectError(ParseError.MissingValue, parseArgs(&.{"-n"}));
    try std.testing.expectError(ParseError.MissingValue, parseArgs(&.{"-t"}));
    try std.testing.expectError(ParseError.MissingValue, parseArgs(&.{"-r"}));
    try std.testing.expectError(ParseError.InvalidNumber, parseArgs(&.{ "-n", "abc" }));
    try std.testing.expectError(ParseError.InvalidNumber, parseArgs(&.{ "-n", "0" }));
    try std.testing.expectError(ParseError.TooManyPositionals, parseArgs(&.{ "a.c", "b.c" }));
}
