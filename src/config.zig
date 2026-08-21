const std = @import("std");

pub const Config = struct {
    high_temp: u8 = 60,
    mid_temp: u8 = 40,
    low_fan: u8 = 15,
    mid_fan: u8 = 50,
    high_fan: u8 = 100,
    interval_seconds: u32 = 5,
};

pub fn load(allocator: std.mem.Allocator, path: []const u8) !Config {
    var config = Config{};

    const file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return config,
        else => return err,
    };
    defer file.close();

    const source = try file.readToEndAlloc(allocator, 16 * 1024);
    defer allocator.free(source);

    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;

        const separator = std.mem.indexOfScalar(u8, line, '=') orelse return error.InvalidConfig;
        const key = std.mem.trim(u8, line[0..separator], " \t");
        const value = std.mem.trim(u8, line[separator + 1 ..], " \t");

        if (std.mem.eql(u8, key, "high_temp")) {
            config.high_temp = try parseU8(value);
        } else if (std.mem.eql(u8, key, "mid_temp")) {
            config.mid_temp = try parseU8(value);
        } else if (std.mem.eql(u8, key, "low_fan")) {
            config.low_fan = try parseU8(value);
        } else if (std.mem.eql(u8, key, "mid_fan")) {
            config.mid_fan = try parseU8(value);
        } else if (std.mem.eql(u8, key, "high_fan")) {
            config.high_fan = try parseU8(value);
        } else if (std.mem.eql(u8, key, "interval_seconds")) {
            config.interval_seconds = try parseU32(value);
        } else {
            return error.InvalidConfig;
        }
    }

    return config;
}

fn parseU8(value: []const u8) !u8 {
    return std.fmt.parseInt(u8, value, 10);
}

fn parseU32(value: []const u8) !u32 {
    return std.fmt.parseInt(u32, value, 10);
}
