//! Codec for the TypeSafe /v1/systemone API (see schema/openapi.json).
//!
//! deslop posts `SystemOneRequest`s to $SYSTEMONE_URL (questions batched at
//! `max_questions` per request) and parses the `SystemOneResponse`s back out;
//! no agent lifecycle involved.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

/// Model alias used when $DESLOP_MODEL is unset (see GET /v1/models).
pub const default_model = "jev-latest";

/// Questions per request: the /v1/systemone proxy accepts at most 64 per
/// request (`MAX_QUESTIONS`); we batch at 32 to stay safely under it.
pub const max_questions: usize = 32;

/// Resolve the /v1/systemone `model` field: $DESLOP_MODEL or `default_model`.
pub fn modelFromEnv(env: *std.process.Environ.Map) []const u8 {
    if (env.get("DESLOP_MODEL")) |m| {
        if (m.len > 0) return m;
    }
    return default_model;
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

/// Build a `SystemOneRequest` as a `std.json.Value` tree and serialize it with
/// `std.json.Stringify` (the library owns all JSON syntax and escaping).
/// `state` = the whole source; questions are one per line named `line_N` with
/// absolute 1-based numbering so batches merge trivially. Default mode asks a
/// noul good-vs-bad question per line; with `ladder`, a choice question
/// restricted to the ladder tags. `only` (from -n) restricts the request to a
/// single line. `offset` is the 0-based first line of the batch and `limit`
/// the maximum number of lines to include; callers batch with `max_questions`.
pub fn buildRequest(
    arena: Allocator,
    model: []const u8,
    source: []const u8,
    ladder: ?[]const []const u8,
    only: ?u32,
    offset: usize,
    limit: usize,
) Allocator.Error![]u8 {
    var questions: std.json.ObjectMap = .empty;
    const n = countLines(source);
    const last = @min(offset +| limit, n);
    var i: usize = offset + 1;
    while (i <= last) : (i += 1) {
        if (only) |o| {
            if (o != i) continue;
        }
        const line = lineAt(source, i);
        var q: std.json.ObjectMap = .empty;
        if (ladder) |tags| {
            const instr = try std.fmt.allocPrint(
                arena,
                "Line {d} of the source: `{s}`. " ++ categorical_question,
                .{ i, line },
            );
            try q.put(arena, "type", .{ .string = "choice" });
            try q.put(arena, "instructions", .{ .string = instr });
            var criteria: std.json.ObjectMap = .empty;
            for (tags) |tag| try criteria.put(arena, tag, .null);
            try q.put(arena, "criteria", .{ .object = criteria });
        } else {
            const instr = try std.fmt.allocPrint(
                arena,
                "Line {d} of the source: `{s}`. " ++ good_question,
                .{ i, line },
            );
            try q.put(arena, "type", .{ .string = "noul" });
            try q.put(arena, "instructions", .{ .string = instr });
        }
        const name = try std.fmt.allocPrint(arena, "line_{d}", .{i});
        try questions.put(arena, name, .{ .object = q });
    }
    var root: std.json.ObjectMap = .empty;
    try root.put(arena, "model", .{ .string = model });
    try root.put(arena, "state", .{ .string = source });
    try root.put(arena, "questions", .{ .object = questions });
    return std.json.Stringify.valueAlloc(arena, std.json.Value{ .object = root }, .{});
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

pub const default_endpoint = "http://localhost:8080/v1/systemone";

/// Resolve the /v1/systemone endpoint: $SYSTEMONE_URL or `default_endpoint`.
pub fn endpointFromEnv(env: *std.process.Environ.Map) []const u8 {
    if (env.get("SYSTEMONE_URL")) |u| {
        if (u.len > 0) return u;
    }
    return default_endpoint;
}

/// Optional Bearer token: $TYPESAFE_API_KEY (null when unset/empty).
pub fn bearerFromEnv(env: *std.process.Environ.Map) ?[]const u8 {
    if (env.get("TYPESAFE_API_KEY")) |t| {
        if (t.len > 0) return t;
    }
    return null;
}

/// One-shot HTTP POST: send `body` (a SystemOneRequest) to `endpoint` and
/// return the response body. Requires HTTP 200; any other status is
/// `error.UnexpectedStatus`.
pub fn postJson(
    arena: Allocator,
    io: Io,
    endpoint: []const u8,
    bearer: ?[]const u8,
    body: []const u8,
) ![]u8 {
    var client: std.http.Client = .{ .allocator = arena, .io = io };
    defer client.deinit();

    var aw: Io.Writer.Allocating = .init(arena);
    defer aw.deinit();

    const auth = if (bearer) |t| try std.fmt.allocPrint(arena, "Bearer {s}", .{t}) else null;
    const result = try client.fetch(.{
        .location = .{ .url = endpoint },
        .method = .POST,
        .payload = body,
        .response_writer = &aw.writer,
        .headers = .{
            .content_type = .{ .override = "application/json" },
            .authorization = if (auth) |a| .{ .override = a } else .default,
        },
    });
    if (result.status != .ok) return error.UnexpectedStatus;
    return aw.toOwnedSlice();
}

test "buildRequest default mode round-trips" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const req = try buildRequest(arena, "m", "a\nb\n", null, null, 0, max_questions);
    const v = try std.json.parseFromSliceLeaky(std.json.Value, arena, req, .{});
    try std.testing.expectEqualStrings("m", v.object.get("model").?.string);
    try std.testing.expectEqualStrings("a\nb\n", v.object.get("state").?.string);
    const qs = v.object.get("questions").?.object;
    try std.testing.expectEqual(@as(usize, 2), qs.count());
    try std.testing.expect(qs.get("line_3") == null);
    const q1 = qs.get("line_1").?.object;
    try std.testing.expectEqualStrings("noul", q1.get("type").?.string);
    try std.testing.expect(std.mem.indexOf(u8, q1.get("instructions").?.string, "`a`") != null);
}

test "buildRequest categorical and only" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const req = try buildRequest(arena, "m", "x\ny\nz\n", &.{ "good", "bad" }, 2, 0, max_questions);
    const v = try std.json.parseFromSliceLeaky(std.json.Value, arena, req, .{});
    const qs = v.object.get("questions").?.object;
    try std.testing.expectEqual(@as(usize, 1), qs.count());
    const q = qs.get("line_2").?.object;
    try std.testing.expectEqualStrings("choice", q.get("type").?.string);
    const criteria = q.get("criteria").?.object;
    try std.testing.expectEqual(@as(usize, 2), criteria.count());
    try std.testing.expect(criteria.get("good").? == .null);
}

test "buildRequest batches by offset and limit" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const req = try buildRequest(arena, "m", "a\nb\nc\nd\n", null, null, 2, 2);
    const v = try std.json.parseFromSliceLeaky(std.json.Value, arena, req, .{});
    // state always carries the whole source; only line_3/line_4 are asked.
    try std.testing.expectEqualStrings("a\nb\nc\nd\n", v.object.get("state").?.string);
    const qs = v.object.get("questions").?.object;
    try std.testing.expectEqual(@as(usize, 2), qs.count());
    try std.testing.expect(qs.get("line_2") == null);
    try std.testing.expect(qs.get("line_3") != null);
    try std.testing.expect(qs.get("line_4") != null);
    try std.testing.expect(qs.get("line_5") == null);
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
