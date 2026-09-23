const std = @import("std");
const Io = std.Io;

const deslop = @import("deslop");
const systemone = deslop.systemone;

pub fn main(init: std.process.Init) !void {
    const arena: std.mem.Allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    const cfg = deslop.parseArgs(if (args.len > 0) args[1..] else args) catch |err| {
        std.debug.print("deslop: {s} — run `deslop -h` for usage\n", .{@errorName(err)});
        return err;
    };

    if (cfg.help) {
        var help_buffer: [4096]u8 = undefined;
        var stdout_file_writer: Io.File.Writer = .init(.stdout(), init.io, &help_buffer);
        try stdout_file_writer.interface.writeAll(deslop.help_text);
        try stdout_file_writer.interface.flush();
        return;
    }

    if (cfg.recursive != null) {
        std.debug.print("deslop: -r is not implemented yet\n", .{});
        return error.NotImplemented;
    }

    if (cfg.lsp) {
        std.debug.print("deslop: -l is on hold (see status.md)\n", .{});
        return error.NotImplemented;
    }

    const io = init.io;
    const endpoint = systemone.endpointFromEnv(init.environ_map);
    const bearer = systemone.bearerFromEnv(init.environ_map);
    const model = systemone.modelFromEnv(init.environ_map);

    var stdout_buffer: [8192]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const out = &stdout_file_writer.interface;

    var read_buf: [8192]u8 = undefined;
    const source: []const u8 = if (cfg.file) |path| blk: {
        const file = try Io.Dir.cwd().openFile(io, path, .{});
        var file_reader: Io.File.Reader = .init(file, io, &read_buf);
        break :blk try file_reader.interface.allocRemaining(arena, .limited(16 << 20));
    } else blk: {
        var stdin_file_reader: Io.File.Reader = .init(.stdin(), io, &read_buf);
        break :blk try stdin_file_reader.interface.allocRemaining(arena, .limited(16 << 20));
    };

    // Split into render lines (strip exactly one trailing newline).
    const trimmed = if (std.mem.endsWith(u8, source, "\n"))
        source[0 .. source.len - 1]
    else
        source;
    var lines_list: std.ArrayList([]const u8) = .empty;
    var lit = std.mem.splitScalar(u8, trimmed, '\n');
    while (lit.next()) |l| try lines_list.append(arena, l);
    const lines = lines_list.items;

    var ladder: ?[]const []const u8 = null;
    var tag_width: usize = 0;
    if (cfg.tagfile) |path| {
        const tags = try deslop.loadTags(arena, io, path);
        for (tags) |t| tag_width = @max(tag_width, t.len);
        ladder = tags;
    }

    // Question batches: `state` carries the full source on every request;
    // questions are chunked at max_questions (-n bypasses batching). -X dumps
    // the first batch's request and exits.
    const batch_size: usize = if (cfg.line != null) lines.len else systemone.max_questions;
    var answers_list: std.ArrayList(systemone.Answer) = .empty;
    var offset: usize = 0;
    while (offset < lines.len) : (offset += batch_size) {
        const limit = @min(batch_size, lines.len - offset);
        const request = try systemone.buildRequest(arena, model, source, ladder, cfg.line, offset, limit);

        if (cfg.dump_request) {
            try out.writeAll(request);
            try out.writeAll("\n");
            try out.flush();
            return;
        }

        const raw = systemone.postJson(arena, io, endpoint, bearer, request) catch |err| {
            std.debug.print("deslop: {s} POSTing {s}\n", .{ @errorName(err), endpoint });
            return err;
        };
        try answers_list.appendSlice(arena, try systemone.parseAnswers(arena, raw));
    }
    const answers = answers_list.items;

    const scores = try arena.alloc(f64, lines.len);
    @memset(scores, 0.0);
    var assigned: []const []const u8 = &.{};
    if (ladder) |tags| {
        const assigned_mut = try arena.alloc([]const u8, lines.len);
        const neutral = tags[deslop.fitnessToTagIndex(0.0, tags.len)];
        @memset(assigned_mut, neutral);
        for (answers) |a| {
            if (a.line < 1 or a.line > lines.len) continue;
            const i = a.line - 1;
            if (a.choice) |c| {
                for (tags) |lt| {
                    if (std.mem.eql(u8, lt, c)) {
                        assigned_mut[i] = lt;
                        break;
                    }
                }
            } else if (a.noul) |p| {
                assigned_mut[i] = tags[deslop.fitnessToTagIndex(2.0 * p - 1.0, tags.len)];
            }
        }
        assigned = assigned_mut;
    } else {
        for (answers) |a| {
            if (a.line < 1 or a.line > lines.len) continue;
            if (a.noul) |p| scores[a.line - 1] = 2.0 * p - 1.0;
        }
    }

    if (cfg.json) {
        try deslop.renderJson(out, lines, scores, assigned, ladder != null, cfg.line);
    } else if (ladder != null) {
        try deslop.renderTags(out, lines, assigned, tag_width, cfg.line);
    } else {
        try deslop.renderFitness(out, lines, scores, cfg.line);
    }
    try out.flush();
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa);
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
