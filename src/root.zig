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
    /// `-T TAGFILE`: like `-t`, but the rendered rows include the fitness score.
    tagfile_scores: ?[]const u8 = null,
    /// `-r PATH`: recursive grade (parsed, but not implemented yet).
    recursive: ?[]const u8 = null,
    /// `--json|-j`: structured output.
    json: bool = false,
    /// `-l`: LSP server mode.
    lsp: bool = false,
    /// `-X`: dump the SystemOneRequest JSON to stdout and exit.
    dump_request: bool = false,
    /// `-s`: print a summary instead of per-line output.
    summary: bool = false,
    /// `-h|--help`: print usage and exit.
    help: bool = false,
};

pub const ParseError = error{
    UnknownOption,
    MissingValue,
    InvalidNumber,
    TooManyPositionals,
    ConflictingOptions,
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
    \\  -s                    Output a summary
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
            } else if (std.mem.eql(u8, arg, "-T")) {
                i += 1;
                if (i >= args.len) return error.MissingValue;
                cfg.tagfile_scores = args[i];
            } else if (std.mem.eql(u8, arg, "-r")) {
                i += 1;
                if (i >= args.len) return error.MissingValue;
                cfg.recursive = args[i];
            } else if (std.mem.eql(u8, arg, "-j") or std.mem.eql(u8, arg, "--json")) {
                cfg.json = true;
            } else if (std.mem.eql(u8, arg, "-s")) {
                cfg.summary = true;
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
    if (cfg.tagfile != null and cfg.tagfile_scores != null) return error.ConflictingOptions;
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

/// Render default mode rows: `N | X.XX | <line>`; `first` is the 1-based
/// number of `lines[0]` (pass `offset + 1` for a batch slice).
pub fn renderFitness(
    out: *Io.Writer,
    lines: []const []const u8,
    scores: []const f64,
    first: usize,
    only: ?u32,
) Io.Writer.Error!void {
    for (lines, scores, first..) |text, score, n| {
        if (only) |l| {
            if (n != @as(usize, l)) continue;
        }
        try out.print("{d} | {d:.2} | {s}\n", .{ n, score, text });
    }
}

/// Render categorical mode rows: `N | tag | <line>`, tag column padded to
/// `width`; `first` is the 1-based number of `lines[0]`.
pub fn renderTags(
    out: *Io.Writer,
    lines: []const []const u8,
    assigned: []const []const u8,
    width: usize,
    first: usize,
    only: ?u32,
) Io.Writer.Error!void {
    for (lines, assigned, first..) |text, tag, n| {
        if (only) |l| {
            if (n != @as(usize, l)) continue;
        }
        try out.print("{d} | {s}", .{ n, tag });
        var pad: usize = width - tag.len;
        while (pad > 0) : (pad -= 1) try out.writeAll(" ");
        try out.print(" | {s}\n", .{text});
    }
}

/// Render structured JSON: one object per line (NDJSON); `first` is the
/// 1-based number of `lines[0]`.
pub fn renderJson(
    out: *Io.Writer,
    lines: []const []const u8,
    scores: []const f64,
    assigned: []const []const u8,
    categorical: bool,
    first: usize,
    only: ?u32,
) Io.Writer.Error!void {
    for (lines, first..) |_, n| {
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

/// One row of the `-s` tag distribution (see `renderSummary`).
pub const TagStat = struct {
    tag: []const u8,
    count: usize,
    conf_sum: f64,
};

/// Render the `-s` summary block (draft.md): LOC, good/bad sums with their
/// extremes, average score, then the tag distribution (pre-sorted by the
/// caller: count desc, ladder-order ties). `bad_sum` is a magnitude (>= 0);
/// `good_max`/`bad_max` are null when no line was good/bad; zero-count tags
/// are omitted by the caller.
pub fn renderSummary(
    out: *Io.Writer,
    loc: usize,
    good_sum: f64,
    good_max: ?f64,
    bad_sum: f64,
    bad_max: ?f64,
    average: f64,
    unanswered: usize,
    tags: ?[]const TagStat,
) Io.Writer.Error!void {
    try out.print("LOC: {d}\n", .{loc});
    if (unanswered > 0) try out.print("unanswered: {d}\n", .{unanswered});
    if (good_max) |m| {
        try out.print("Good: {d:.1} sum, max: {d:.2}\n", .{ good_sum, m });
    } else {
        try out.writeAll("Good: 0.0 sum, max: n/a\n");
    }
    if (bad_max) |m| {
        try out.print("Bad: {d:.1} sum, max: {d:.2}\n", .{ bad_sum, m });
    } else {
        try out.writeAll("Bad: 0.0 sum, max: n/a\n");
    }
    try out.print("Average score: {d:.2}\n", .{average});
    const stats = tags orelse return;
    if (stats.len == 0) return;
    try out.writeAll("\n");
    var tag_w: usize = 3;
    for (stats) |s| tag_w = @max(tag_w, s.tag.len);
    try out.writeAll("TAG");
    var pad: usize = tag_w - 3;
    while (pad > 0) : (pad -= 1) try out.writeAll(" ");
    try out.writeAll("  COUNT  AVG CONF\n");
    for (stats) |s| {
        try out.writeAll(s.tag);
        pad = tag_w - s.tag.len;
        while (pad > 0) : (pad -= 1) try out.writeAll(" ");
        try out.print("  {d:>5}", .{s.count});
        if (s.count > 0) {
            const avg = s.conf_sum / @as(f64, @floatFromInt(s.count));
            try out.print("  {d:>8.2}\n", .{avg});
        } else {
            try out.writeAll("       n/a\n");
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
    try renderFitness(&w, &.{ "x", "" }, &.{ 1.0, -0.5 }, 1, null);
    try std.testing.expectEqualStrings("1 | 1.00 | x\n2 | -0.50 | \n", w.buffered());
}

pub const systemone = @import("systemone.zig");

test "parseArgs: -X dumps request" {
    const cfg = try parseArgs(&.{"-X"});
    try std.testing.expect(cfg.dump_request);
}

test "parseArgs: -s summary" {
    const cfg = try parseArgs(&.{"-s"});
    try std.testing.expect(cfg.summary);
}

test "renderSummary format" {
    var buf: [512]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    try renderSummary(&w, 8, 6.3, 1.0, 3.0, -0.46, 0.85, 1, &.{
        .{ .tag = "typesafe", .count = 3, .conf_sum = 0.3 },
        .{ .tag = "mediocre", .count = 3, .conf_sum = 1.53 },
    });
    try std.testing.expectEqualStrings(
        "LOC: 8\nunanswered: 1\nGood: 6.3 sum, max: 1.00\nBad: 3.0 sum, max: -0.46\nAverage score: 0.85\n\nTAG       COUNT  AVG CONF\ntypesafe      3      0.10\nmediocre      3      0.51\n",
        w.buffered(),
    );
}

/// Render `-T` mode rows: `| NNN | tag | score | <line>`; `first` is the
/// 1-based number of `lines[0]`; the tag column is padded to `width`.
pub fn renderTagScores(
    out: *Io.Writer,
    lines: []const []const u8,
    assigned: []const []const u8,
    scores: []const f64,
    width: usize,
    first: usize,
    only: ?u32,
) Io.Writer.Error!void {
    for (lines, assigned, scores, first..) |text, tag, score, n| {
        if (only) |l| {
            if (n != @as(usize, l)) continue;
        }
        try out.print("| {d:0>3} | {s}", .{ n, tag });
        var pad: usize = width - tag.len;
        while (pad > 0) : (pad -= 1) try out.writeAll(" ");
        try out.print(" | {d:5.2} | {s}\n", .{ score, text });
    }
}

test "renderTagScores format" {
    var buf: [256]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    try renderTagScores(&w, &.{ "x", "" }, &.{ "mediocre", "godmode" }, &.{ 0.5, -1.0 }, 8, 9, null);
    try std.testing.expectEqualStrings(
        "| 009 | mediocre |  0.50 | x\n| 010 | godmode  | -1.00 | \n",
        w.buffered(),
    );
}

test "parseArgs: -T tagfile with scores" {
    const cfg = try parseArgs(&.{ "-T", "tags.txt" });
    try std.testing.expectEqualStrings("tags.txt", cfg.tagfile_scores.?);
}

test "parseArgs: -t and -T conflict" {
    try std.testing.expectError(error.ConflictingOptions, parseArgs(&.{ "-t", "a", "-T", "b" }));
}
