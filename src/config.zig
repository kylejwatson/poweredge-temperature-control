const std = @import("std");

pub const Point = struct {
    temp: u8,
    fan: u8,
};

const default_points = [_]Point{
    .{ .temp = 0, .fan = 15 },
    .{ .temp = 40, .fan = 50 },
    .{ .temp = 60, .fan = 100 },
};

pub const Config = struct {
    points: []const Point = default_points[0..],
    interval_seconds: u32 = 5,
    owned_points: ?[]Point = null,

    pub fn deinit(self: *Config, allocator: std.mem.Allocator) void {
        if (self.owned_points) |points| {
            allocator.free(points);
            self.owned_points = null;
            self.points = default_points[0..];
        }
    }
};

pub fn load(allocator: std.mem.Allocator, path: []const u8) !Config {
    var config = Config{};
    var points: std.ArrayListUnmanaged(Point) = .{};
    defer points.deinit(allocator);
    var points_defined = false;

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

        if (std.mem.eql(u8, key, "point")) {
            try points.append(allocator, try parsePoint(value));
            points_defined = true;
        } else if (std.mem.eql(u8, key, "interval_seconds")) {
            config.interval_seconds = try parseU32(value);
        } else {
            return error.InvalidConfig;
        }
    }

    if (points_defined) {
        if (points.items.len < 2) return error.InvalidConfig;
        const owned_points = try allocator.dupe(Point, points.items);
        sortPoints(owned_points);
        validatePoints(owned_points) catch {
            allocator.free(owned_points);
            return error.InvalidConfig;
        };
        config.points = owned_points;
        config.owned_points = owned_points;
    }

    return config;
}

pub fn fanForTemperature(points: []const Point, temperature: u8) u8 {
    if (points.len == 0) return 0;
    if (temperature <= points[0].temp) return points[0].fan;
    if (temperature >= points[points.len - 1].temp) return points[points.len - 1].fan;

    var index: usize = 0;
    while (index + 1 < points.len) : (index += 1) {
        const left = points[index];
        const right = points[index + 1];
        if (temperature > right.temp) continue;
        if (temperature == left.temp) return left.fan;
        if (temperature == right.temp) return right.fan;

        const span = @as(u32, right.temp - left.temp);
        if (span == 0) return right.fan;

        const offset = @as(u32, temperature - left.temp);
        const fan_delta = @as(i32, @intCast(right.fan)) - @as(i32, @intCast(left.fan));
        const interpolated = @as(i32, @intCast(left.fan)) + @as(i32, @intCast((offset * @as(u32, @intCast(@abs(fan_delta)))) / span)) * @as(i32, if (fan_delta < 0) -1 else 1);
        return clampFan(interpolated);
    }

    return points[points.len - 1].fan;
}

fn parseU8(value: []const u8) !u8 {
    return std.fmt.parseInt(u8, value, 10);
}

fn parseU32(value: []const u8) !u32 {
    return std.fmt.parseInt(u32, value, 10);
}

fn parsePoint(value: []const u8) !Point {
    const separator = std.mem.indexOfScalar(u8, value, ',') orelse return error.InvalidConfig;
    const temp_text = std.mem.trim(u8, value[0..separator], " \t");
    const fan_text = std.mem.trim(u8, value[separator + 1 ..], " \t");
    const temp = try parseU8(temp_text);
    const fan = try parseU8(fan_text);
    if (fan > 100) return error.InvalidConfig;
    return .{ .temp = temp, .fan = fan };
}

fn sortPoints(points: []Point) void {
    var i: usize = 1;
    while (i < points.len) : (i += 1) {
        var j = i;
        while (j > 0 and points[j].temp < points[j - 1].temp) : (j -= 1) {
            const tmp = points[j - 1];
            points[j - 1] = points[j];
            points[j] = tmp;
        }
    }
}

fn validatePoints(points: []const Point) !void {
    var index: usize = 1;
    while (index < points.len) : (index += 1) {
        if (points[index].temp == points[index - 1].temp) return error.InvalidConfig;
    }
}

fn clampFan(value: i32) u8 {
    if (value < 0) return 0;
    if (value > 100) return 100;
    return @as(u8, @intCast(value));
}
