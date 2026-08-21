const std = @import("std");
const config_mod = @import("config.zig");
const controller_mod = @import("controller.zig");

const usage_text =
    "Usage: temp-control [--daemon] [--config PATH]\n" ++
    "\n" ++
    "Options:\n" ++
    "  --daemon       Run continuously on the configured interval.\n" ++
    "  --config PATH  Read key=value settings from PATH.\n" ++
    "  --help         Show this help text.";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var daemon = false;
    var config_path: []const u8 = "/etc/temp-control.conf";

    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--daemon")) {
            daemon = true;
        } else if (std.mem.eql(u8, arg, "--config")) {
            index += 1;
            if (index >= args.len) return error.MissingConfigPath;
            config_path = args[index];
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            std.debug.print("{s}\n", .{usage_text});
            return;
        } else {
            return error.InvalidArguments;
        }
    }

    const config = try config_mod.load(allocator, config_path);
    var controller = controller_mod.FanController.init(config);

    if (daemon) {
        try controller.runDaemon(allocator);
    } else {
        try controller.runOnce(allocator);
    }
}
