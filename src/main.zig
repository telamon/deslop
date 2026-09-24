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
    const tag_path: ?[]const u8 = cfg.tagfile orelse cfg.tagfile_scores;
    if (tag_path) |path| {
        const tags = try deslop.loadTags(arena, io, path);
        for (tags) |t| tag_width = @max(tag_width, t.len);
        ladder = tags;
    }

    // Per-line results are neutral-initialized up front so each pass maps its
    // answers into whole-file arrays.
    const scores = try arena.alloc(f64, lines.len);
    @memset(scores, 0.0);
    const assigned_mut = try arena.alloc([]const u8, lines.len);
    if (ladder) |tags| {
        @memset(assigned_mut, tags[deslop.fitnessToTagIndex(0.0, tags.len)]);
    } else {
        @memset(assigned_mut, "");
    }
    const answered = try arena.alloc(bool, lines.len);
    @memset(answered, false);
    const tag_counts = try arena.alloc(usize, if (ladder) |t| t.len else 0);
    @memset(tag_counts, 0);
    const tag_conf = try arena.alloc(f64, tag_counts.len);
    @memset(tag_conf, 0.0);

    // Summary mode (-s, text output only): accumulate instead of per-line
    // rows. With -t this runs two passes over the same full-source `state`:
    // first the choice (tag) questions, then the noul good/bad questions.
    const summary_mode = cfg.summary and !cfg.json;

    // Question batches: `state` carries the full source on every request;
    // questions are chunked at max_questions (-n bypasses batching); -X dumps
    // the first batch's request and exits. `line_N` numbering is absolute, so
    // batches and passes merge trivially by line.
    const passes: usize = if ((summary_mode or cfg.tagfile_scores != null) and ladder != null) 2 else 1;
    const batch_size: usize = if (cfg.line != null) lines.len else systemone.max_questions;
    for (0..passes) |p| {
        const pass_ladder: ?[]const []const u8 = if (p == 1) null else ladder;
        var offset: usize = 0;
        while (offset < lines.len) : (offset += batch_size) {
            const limit = @min(batch_size, lines.len - offset);
            const request = try systemone.buildRequest(arena, model, source, pass_ladder, cfg.line, offset, limit);

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

            // Map this batch's answers; each line belongs to exactly one batch.
            for (try systemone.parseAnswers(arena, raw)) |a| {
                if (a.line < 1 or a.line > lines.len) continue;
                const i = a.line - 1;
                if (pass_ladder) |tags| {
                    if (a.choice) |c| {
                        for (tags, 0..) |lt, ti| {
                            if (std.mem.eql(u8, lt, c)) {
                                assigned_mut[i] = lt;
                                if (summary_mode) {
                                    answered[i] = true;
                                    tag_counts[ti] += 1;
                                    if (a.confidence) |cf| tag_conf[ti] += cf;
                                }
                                break;
                            }
                        }
                    } else if (a.noul) |pn| {
                        const ti = deslop.fitnessToTagIndex(2.0 * pn - 1.0, tags.len);
                        assigned_mut[i] = tags[ti];
                        if (summary_mode) {
                            answered[i] = true;
                            tag_counts[ti] += 1;
                        }
                    }
                } else if (a.noul) |pn| {
                    scores[i] = 2.0 * pn - 1.0;
                    if (summary_mode) answered[i] = true;
                }
            }

            if (summary_mode) continue;
            // -T: scores come from the second (noul) pass; skip pass-0 rows.
            if (passes == 2 and p == 0) continue;

            // Partial render of the rows this batch covers, then flush.
            const rows = lines[offset..][0..limit];
            if (cfg.json) {
                try deslop.renderJson(out, rows, scores[offset..][0..limit], assigned_mut[offset..][0..limit], ladder != null, offset + 1, cfg.line);
            } else if (cfg.tagfile_scores != null) {
                try deslop.renderTagScores(out, rows, assigned_mut[offset..][0..limit], scores[offset..][0..limit], tag_width, offset + 1, cfg.line);
            } else if (ladder != null) {
                try deslop.renderTags(out, rows, assigned_mut[offset..][0..limit], tag_width, offset + 1, cfg.line);
            } else {
                try deslop.renderFitness(out, rows, scores[offset..][0..limit], offset + 1, cfg.line);
            }
            try out.flush();
        }
    }

    if (summary_mode) {
        var good_sum: f64 = 0.0;
        var bad_sum: f64 = 0.0;
        var good_max: ?f64 = null;
        var bad_max: ?f64 = null;
        var total: f64 = 0.0;
        for (scores) |s| {
            total += s;
            if (s > 0.0) {
                good_sum += s;
                good_max = if (good_max) |m| @max(m, s) else s;
            } else if (s < 0.0) {
                bad_sum += s;
                bad_max = if (bad_max) |m| @max(m, s) else s;
            }
        }
        const average: f64 = if (lines.len > 0) total / @as(f64, @floatFromInt(lines.len)) else 0.0;
        // Tag distribution: count desc, ties in ladder order (stable insertion
        // sort over ladder-ordered accumulation). Unanswered lines are counted
        // apart from the table instead of inflating the neutral tag's count.
        var unanswered: usize = 0;
        for (answered) |ok| {
            if (!ok) unanswered += 1;
        }
        var stats: std.ArrayList(deslop.TagStat) = .empty;
        if (ladder) |tags| {
            for (tags, tag_counts, tag_conf) |tag, c, cf| {
                if (c != 0) try stats.append(arena, .{ .tag = tag, .count = c, .conf_sum = cf });
            }
            const items = stats.items;
            var si: usize = 1;
            while (si < items.len) : (si += 1) {
                const cur = items[si];
                var sj = si;
                while (sj > 0 and items[sj - 1].count < cur.count) : (sj -= 1) {
                    items[sj] = items[sj - 1];
                }
                items[sj] = cur;
            }
        }
        const tag_stats: ?[]const deslop.TagStat = if (ladder != null) stats.items else null;
        try deslop.renderSummary(out, lines.len, good_sum, good_max, -bad_sum, bad_max, average, unanswered, tag_stats);
        try out.flush();
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
