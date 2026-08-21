const std = @import("std");
const command = @import("command.zig");

pub fn maxTemperature(allocator: std.mem.Allocator) !u8 {
    var found = false;
    var best: u8 = 0;

    if (readSensors(allocator)) |value| {
        best = value;
        found = true;
    }

    if (!found) {
        if (readIpmi(allocator)) |value| {
            best = value;
            found = true;
        }
    }

    if (!found) return error.NoTemperatureReading;
    return best;
}

pub fn setFanPercent(allocator: std.mem.Allocator, percent: u8) !void {
    try command.run(allocator, &[_][]const u8{
        "ipmitool",
        "raw",
        "0x30",
        "0x30",
        "0x01",
        "0x00",
    });

    var percent_hex: [4]u8 = .{ '0', 'x', '0', '0' };
    const digits = "0123456789abcdef";
    percent_hex[2] = digits[percent >> 4];
    percent_hex[3] = digits[percent & 0x0f];

    try command.run(allocator, &[_][]const u8{
        "ipmitool",
        "raw",
        "0x30",
        "0x30",
        "0x02",
        "0xff",
        percent_hex[0..],
    });
}

fn readSensors(allocator: std.mem.Allocator) ?u8 {
    const output = command.captureStdout(allocator, &[_][]const u8{"sensors"}) catch return null;
    defer allocator.free(output);
    return parseSensorsOutput(output);
}

fn readIpmi(allocator: std.mem.Allocator) ?u8 {
    const output = command.captureStdout(allocator, &[_][]const u8{ "ipmitool", "sdr", "type", "temperature" }) catch return null;
    defer allocator.free(output);
    return parseIpmiOutput(output);
}

fn parseSensorsOutput(output: []const u8) ?u8 {
    var found = false;
    var best: u8 = 0;

    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |line| {
        var tokens = std.mem.tokenizeAny(u8, line, " \t");
        while (tokens.next()) |token| {
            if (parseTemperatureToken(token)) |value| {
                if (!found or value > best) {
                    best = value;
                    found = true;
                }
            }
        }
    }

    if (!found) return null;
    return best;
}

fn parseIpmiOutput(output: []const u8) ?u8 {
    var found = false;
    var best: u8 = 0;

    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |line| {
        if (!isRelevantIpmiLine(line)) continue;

        const degrees_index = std.mem.indexOf(u8, line, " degrees") orelse continue;
        var start: usize = degrees_index;
        while (start > 0) {
            const byte = line[start - 1];
            if (std.ascii.isDigit(byte) or byte == '.' or byte == '+' or byte == '-') {
                start -= 1;
                continue;
            }
            break;
        }

        const value_text = std.mem.trim(u8, line[start..degrees_index], " \t|");
        const value = std.fmt.parseFloat(f64, value_text) catch continue;
        const temp = @as(u8, @intFromFloat(@floor(value)));
        if (!found or temp > best) {
            best = temp;
            found = true;
        }
    }

    if (!found) return null;
    return best;
}

fn isRelevantIpmiLine(line: []const u8) bool {
    return std.mem.indexOf(u8, line, "Temp") != null or
        std.mem.indexOf(u8, line, "Inlet") != null or
        std.mem.indexOf(u8, line, "CPU") != null;
}

fn parseTemperatureToken(token: []const u8) ?u8 {
    var cleaned = std.mem.trimLeft(u8, token, "+");

    while (cleaned.len > 0 and cleaned[cleaned.len - 1] == 'C') {
        cleaned = cleaned[0 .. cleaned.len - 1];
    }

    while (cleaned.len > 0 and cleaned[cleaned.len - 1] >= 128) {
        cleaned = cleaned[0 .. cleaned.len - 1];
    }

    if (cleaned.len == 0) return null;
    const value = std.fmt.parseFloat(f64, cleaned) catch return null;
    if (value < 0) return null;
    return @as(u8, @intFromFloat(@floor(value)));
}
