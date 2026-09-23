//! Codec for the TypeSafe /v1/systemone API (see schema/openapi.json).
//!
//! In this initial variant the request JSON is piped raw to the harness
//! (`harness -R -T -r`) and the model's raw output is expected to be a
//! `SystemOneResponse`.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

/// Model alias used when $UNSLOP_MODEL is unset (see GET /v1/models).
pub const default_model = "jev-latest";

/// Resolve the /v1/systemone `model` field: $UNSLOP_MODEL or `default_model`.
pub fn modelFromEnv(env: *std.process.Environ.Map) []const u8 {
    if (env.get("UNSLOP_MODEL")) |m| {
        if (m.len > 0) return m;
    }
    return default_model;
}

/// Write `s` as a complete JSON string literal (with quotes), escaping per
/// RFC 8259. Bytes >= 0x20 pass through unchanged (UTF-8 safe).
pub fn writeJsonString(out: *Io.Writer, s: []const u8) Io.Writer.Error!void {
    try out.writeByte('"');
    for (s) |c| {
        switch (c) {
            '"' => try out.writeAll("\\\""),
            '\\' => try out.writeAll("\\\\"),
            0x08 => try out.writeAll("\\b"),
            0x0c => try out.writeAll("\\f"),
            '\n' => try out.writeAll("\\n"),
            '\r' => try out.writeAll("\\r"),
            '\t' => try out.writeAll("\\t"),
            else => {
                if (c < 0x20) {
                    try out.print("\\u{x:0>4}", .{c});
                } else {
                    try out.writeByte(c);
                }
            },
        }
    }
    try out.writeByte('"');
}

/// Source with exactly one trailing '\n' removed (same rule as the renderer).
fn trimmedSource(source: []const u8) []const u8 {
    return if (std.mem.endsWith(u8, source, "\n")) source[0 .. source.len - 1] else source;
}

/// Number of lines the renderer shows for `source`.
pub fn countLines(source: []const u8) usize {
    var n: usize = 0;
    var it = std.mem.splitScalar(u8, trimmedSource(source), '\n');
    while (it.next()) |_| n += 1;
    return n;
}

/// The 1-based `index` line of `source` ("" when out of range).
pub fn lineAt(source: []const u8, index: usize) []const u8 {
    var it = std.mem.splitScalar(u8, trimmedSource(source), '\n');
    var i: usize = 1;
    while (it.next()) |l| : (i += 1) {
        if (i == index) return l;
    }
    return "";
}

const good_question =
    "Is this line good code (would a competent developer approve it) rather than bad code (slop)?";
const categorical_question =
    "Which of the listed categories best describes this line?";

/// Build a `SystemOneRequest`: `state` = the whole source, one question per
/// line named `line_N`. Default mode asks a noul good-vs-bad question per
/// line; with `ladder`, a choice question restricted to the ladder tags.
/// `only` (from -n) restricts the request to a single line.
pub fn buildRequest(
    arena: Allocator,
    model: []const u8,
    source: []const u8,
    ladder: ?[]const []const u8,
    only: ?u32,
) (Allocator.Error || Io.Writer.Error)![]u8 {
    var aw: Io.Writer.Allocating = .init(arena);
    defer aw.deinit();
    const w = &aw.writer;

    try w.writeAll("{\"model\":");
    try writeJsonString(w, model);
    try w.writeAll(",\"state\":");
    try writeJsonString(w, source);
    try w.writeAll(",\"questions\":{");

    const n = countLines(source);
    var first = true;
    var i: usize = 1;
    while (i <= n) : (i += 1) {
        if (only) |o| {
            if (o != i) continue;
        }
        if (!first) try w.writeAll(",");
        first = false;
        const line = lineAt(source, i);
        if (ladder) |tags| {
            try w.print("\"line_{d}\":{{\"type\":\"choice\",\"instructions\":", .{i});
            const instr = try std.fmt.allocPrint(
                arena,
                "Line {d} of the source: \"{s}\". " ++ categorical_question,
                .{ i, line },
            );
            try writeJsonString(w, instr);
            try w.writeAll(",\"criteria\":{");
            for (tags, 0..) |tag, ti| {
                if (ti != 0) try w.writeAll(",");
                try writeJsonString(w, tag);
                try w.writeAll(":null");
            }
            try w.writeAll("}}");
        } else {
            try w.print("\"line_{d}\":{{\"type\":\"noul\",\"instructions\":", .{i});
            const instr = try std.fmt.allocPrint(
                arena,
                "Line {d} of the source: \"{s}\". " ++ good_question,
                .{ i, line },
            );
            try writeJsonString(w, instr);
            try w.writeAll("}");
        }
    }
    try w.writeAll("}}");
    return aw.toOwnedSlice();
}

pub const ParseError = error{BadResponse};

/// One per-line answer extracted from a SystemOneResponse.
pub const Answer = struct {
    line: u32,
    noul: ?f64 = null,
    choice: ?[]const u8 = null,
};

fn parseLineKey(key: []const u8) ?u32 {
    const rest = if (std.mem.startsWith(u8, key, "line_")) key["line_".len..] else key;
    return std.fmt.parseInt(u32, rest, 10) catch null;
}

fn asNumber(v: std.json.Value) ?f64 {
    switch (v) {
        .float => |f| return f,
        .integer => |i| return @as(f64, @floatFromInt(i)),
        .number_string => |s| return std.fmt.parseFloat(f64, s) catch null,
        else => return null,
    }
}

/// Parse a `SystemOneResponse` and extract per-line answers keyed `line_N`
/// (plain `N` also accepted). Non-line keys and empty answers are skipped.
/// Note: choice strings reference `bytes`, which must outlive the result.
pub fn parseAnswers(arena: Allocator, bytes: []const u8) (Allocator.Error || ParseError)![]Answer {
    const root = std.json.parseFromSliceLeaky(std.json.Value, arena, bytes, .{}) catch return error.BadResponse;
    if (root != .object) return error.BadResponse;
    const answers_val = root.object.get("answers") orelse return error.BadResponse;
    if (answers_val != .object) return error.BadResponse;

    var list: std.ArrayList(Answer) = .empty;
    var it = answers_val.object.iterator();
    while (it.next()) |entry| {
        const line = parseLineKey(entry.key_ptr.*) orelse continue;
        const val = entry.value_ptr.*;
        if (val != .object) continue;
        var answer = Answer{ .line = line };
        if (val.object.get("noul")) |nv| answer.noul = asNumber(nv);
        if (val.object.get("choice")) |cv| {
            if (cv == .string) answer.choice = cv.string;
        }
        if (answer.noul == null and answer.choice == null) continue;
        try list.append(arena, answer);
    }
    return list.items;
}

test "writeJsonString escapes control characters" {
    var buf: [64]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    try writeJsonString(&w, "a\"b\\c\nd\x01");
    try std.testing.expectEqualStrings("\"a\\\"b\\\\c\\nd\\u0001\"", w.buffered());
}

test "buildRequest default mode round-trips" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const req = try buildRequest(arena, "m", "a\nb\n", null, null);
    const v = try std.json.parseFromSliceLeaky(std.json.Value, arena, req, .{});
    try std.testing.expectEqualStrings("m", v.object.get("model").?.string);
    try std.testing.expectEqualStrings("a\nb\n", v.object.get("state").?.string);
    const qs = v.object.get("questions").?.object;
    try std.testing.expectEqual(@as(usize, 2), qs.count());
    try std.testing.expect(qs.get("line_3") == null);
    const q1 = qs.get("line_1").?.object;
    try std.testing.expectEqualStrings("noul", q1.get("type").?.string);
    try std.testing.expect(std.mem.indexOf(u8, q1.get("instructions").?.string, "\"a\"") != null);
}

test "buildRequest categorical and only" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const req = try buildRequest(arena, "m", "x\ny\nz\n", &.{ "good", "bad" }, 2);
    const v = try std.json.parseFromSliceLeaky(std.json.Value, arena, req, .{});
    const qs = v.object.get("questions").?.object;
    try std.testing.expectEqual(@as(usize, 1), qs.count());
    const q = qs.get("line_2").?.object;
    try std.testing.expectEqualStrings("choice", q.get("type").?.string);
    const criteria = q.get("criteria").?.object;
    try std.testing.expectEqual(@as(usize, 2), criteria.count());
    try std.testing.expect(criteria.get("good").? == .null);
}

test "parseAnswers noul choice and filtering" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const bytes =
        \\{"model":"x","answers":{
        \\"line_1":{"type":"noul","noul":0.5},
        \\"line_2":{"type":"choice","choice":"mediocre"},
        \\"ignored":{"type":"noul","noul":1},
        \\"line_3":{"type":"noul"}},
        \\"usage":{"input_tokens":1,"output_tokens":2}}
    ;
    const answers = try parseAnswers(arena, bytes);
    try std.testing.expectEqual(@as(usize, 2), answers.len);
    try std.testing.expectEqual(@as(u32, 1), answers[0].line);
    try std.testing.expectEqual(@as(f64, 0.5), answers[0].noul.?);
    try std.testing.expectEqual(@as(u32, 2), answers[1].line);
    try std.testing.expectEqualStrings("mediocre", answers[1].choice.?);
}

test "parseAnswers rejects non-objects" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    try std.testing.expectError(error.BadResponse, parseAnswers(arena, "not json"));
    try std.testing.expectError(error.BadResponse, parseAnswers(arena, "[1]"));
    try std.testing.expectError(error.BadResponse, parseAnswers(arena, "{}"));
}
