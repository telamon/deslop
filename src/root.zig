//! By convention, root.zig is the root source file when making a package.
const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

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
    /// `-X`: dump the SystemOneRequest JSON to stdout and exit.
    dump_request: bool = false,
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
    \\usage: deslop [options] [FILE]
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
    \\  -X                    dumps Json request to stdout and exits
    \\
    \\  deslop POSTs a /v1/systemone request to the endpoint in $SYSTEMONE_URL.
    \\
    \\  Environment options:
    \\
    \\  SYSTEMONE_URL=http://localhost:8080/v1/systemone
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
            } else if (std.mem.eql(u8, arg, "-X")) {
                cfg.dump_request = true;
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

pub fn loadTags(arena: Allocator, io: Io, path: []const u8) ![][]const u8 {
    const file = try Io.Dir.cwd().openFile(io, path, .{ .mode = .read_only });
    var buf: [4096]u8 = undefined;
    var file_reader: Io.File.Reader = .init(file, io, &buf);
    const data = try file_reader.interface.allocRemaining(arena, .limited(1 << 20));
    var tags: std.ArrayList([]const u8) = .empty;
    var it = std.mem.tokenizeAny(u8, data, " \t\r\n");
    while (it.next()) |t| try tags.append(arena, t);
    if (tags.items.len == 0) return error.EmptyTagFile;
    return tags.items;
}

/// Map a fitness in [-1.0, 1.0] onto the tag ladder (index 0 = best).
pub fn fitnessToTagIndex(fitness: f64, ladder_len: usize) usize {
    if (ladder_len <= 1) return 0;
    const span: f64 = @floatFromInt(ladder_len - 1);
    const raw: f64 = (1.0 - fitness) / 2.0 * span;
    return @intFromFloat(@max(0.0, @min(span, raw)));
}

/// Render default mode: `N | X.XX | <line>`.
pub fn renderFitness(
    out: *Io.Writer,
    lines: []const []const u8,
    scores: []const f64,
    only: ?u32,
) Io.Writer.Error!void {
    for (lines, scores, 1..) |text, score, n| {
        if (only) |l| {
            if (n != @as(usize, l)) continue;
        }
        try out.print("{d} | {d:.2} | {s}\n", .{ n, score, text });
    }
}

/// Render categorical mode: `N | tag | <line>`, tag column padded to `width`.
pub fn renderTags(
    out: *Io.Writer,
    lines: []const []const u8,
    assigned: []const []const u8,
    width: usize,
    only: ?u32,
) Io.Writer.Error!void {
    for (lines, assigned, 1..) |text, tag, n| {
        if (only) |l| {
            if (n != @as(usize, l)) continue;
        }
        try out.print("{d} | {s}", .{ n, tag });
        var pad: usize = width - tag.len;
        while (pad > 0) : (pad -= 1) try out.writeAll(" ");
        try out.print(" | {s}\n", .{text});
    }
}

/// Render structured JSON: one object per line.
pub fn renderJson(
    out: *Io.Writer,
    lines: []const []const u8,
    scores: []const f64,
    assigned: []const []const u8,
    categorical: bool,
    only: ?u32,
) Io.Writer.Error!void {
    for (lines, 1..) |_, n| {
        if (only) |l| {
            if (n != @as(usize, l)) continue;
        }
        if (categorical) {
            try out.print("{{\"line\":{d},\"tag\":\"{s}\"}}\n", .{ n, assigned[n - 1] });
        } else {
            try out.print("{{\"line\":{d},\"fitness\":{d:.2}}}\n", .{ n, scores[n - 1] });
        }
    }
}

test "fitnessToTagIndex" {
    try std.testing.expectEqual(@as(usize, 0), fitnessToTagIndex(1.0, 10));
    try std.testing.expectEqual(@as(usize, 4), fitnessToTagIndex(0.0, 10));
    try std.testing.expectEqual(@as(usize, 9), fitnessToTagIndex(-1.0, 10));
    try std.testing.expectEqual(@as(usize, 0), fitnessToTagIndex(0.89, 10));
    try std.testing.expectEqual(@as(usize, 3), fitnessToTagIndex(0.12, 10));
}

test "renderFitness format" {
    var buf: [256]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    try renderFitness(&w, &.{ "x", "" }, &.{ 1.0, -0.5 }, null);
    try std.testing.expectEqualStrings("1 | 1.00 | x\n2 | -0.50 | \n", w.buffered());
}

pub const systemone = @import("systemone.zig");

test "parseArgs: -X dumps request" {
    const cfg = try parseArgs(&.{"-X"});
    try std.testing.expect(cfg.dump_request);
}
