const std = @import("std");
const Io = std.Io;

const code_xorcery = @import("code_xorcery");

pub fn main(init: std.process.Init) !void {
    // Permanent storage for the whole process lifetime.
    const arena: std.mem.Allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    // argv[0] is the program name, not a user option.
    const cfg = code_xorcery.parseArgs(if (args.len > 0) args[1..] else args) catch |err| {
        std.debug.print("xorcery: {s} — run `xorcery -h` for usage\n", .{@errorName(err)});
        return err;
    };

    if (cfg.help) {
        var help_buffer: [4096]u8 = undefined;
        var stdout_file_writer: Io.File.Writer = .init(.stdout(), init.io, &help_buffer);
        try stdout_file_writer.interface.writeAll(code_xorcery.help_text);
        try stdout_file_writer.interface.flush(); // Don't forget to flush!
        return;
    }

    if (cfg.recursive != null) {
        std.debug.print("xorcery: -r is not implemented yet\n", .{});
        return error.NotImplemented;
    }

    const harness_bin = code_xorcery.harnessBin(init.environ_map);
    std.log.info("harness bin: {s}", .{harness_bin});
    if (cfg.file) |file| std.log.info("file: {s}", .{file});
    if (cfg.line) |line| std.log.info("single line: {d}", .{line});
    if (cfg.tagfile) |tagfile| std.log.info("tagfile: {s}", .{tagfile});
    if (cfg.json) std.log.info("json: true", .{});
    if (cfg.lsp) std.log.info("lsp: true", .{});
}
