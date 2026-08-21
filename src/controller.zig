const std = @import("std");
const config_mod = @import("config.zig");
const hardware = @import("hardware.zig");

pub const FanController = struct {
    config: config_mod.Config,
    current_fan: u8 = 0,

    pub fn init(config: config_mod.Config) FanController {
        return .{ .config = config };
    }

    pub fn runOnce(self: *FanController, allocator: std.mem.Allocator) !void {
        const temperature = try hardware.maxTemperature(allocator);
        const target = self.targetFan(temperature);

        std.log.info("max_temp={d}C current_fan={d}% target_fan={d}%", .{
            temperature,
            self.current_fan,
            target,
        });

        if (target != self.current_fan) {
            std.log.info("fan_change old={d}% new={d}%", .{ self.current_fan, target });
            try hardware.setFanPercent(allocator, target);
            self.current_fan = target;
            std.log.info("fan_applied current_fan={d}%", .{self.current_fan});
        } else {
            std.log.info("fan_unchanged current_fan={d}%", .{self.current_fan});
        }
    }

    pub fn runDaemon(self: *FanController, allocator: std.mem.Allocator) !void {
        std.log.info(
            "daemon_start interval={d}s points={d}",
            .{
                self.config.interval_seconds,
                self.config.points.len,
            },
        );

        while (true) {
            self.runOnce(allocator) catch |err| {
                std.log.err("temperature cycle failed: {}", .{err});
            };
            std.Thread.sleep(@as(u64, self.config.interval_seconds) * std.time.ns_per_s);
        }
    }

    fn targetFan(self: FanController, temperature: u8) u8 {
        return config_mod.fanForTemperature(self.config.points, temperature);
    }
};
