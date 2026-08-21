const builtin = @import("builtin");
const std = @import("std");

const linux = std.os.linux;

const ipmi = struct {
    pub const IPMI_SYSTEM_INTERFACE_ADDR_TYPE: c_int = 0x0c;
    pub const IPMI_BMC_CHANNEL: i16 = 0x0f;
    pub const IPMI_MAX_MSG_LENGTH: usize = 272;
    pub const IPMI_RESPONSE_RECV_TYPE: c_int = 1;
    pub const IPMI_CC_NO_ERROR: u8 = 0x00;

    pub const Msg = extern struct {
        netfn: u8,
        cmd: u8,
        data_len: u16,
        data: [*]u8,
    };

    pub const SystemInterfaceAddr = extern struct {
        addr_type: c_int,
        channel: i16,
        lun: u8,
    };

    pub const Req = extern struct {
        addr: [*]u8,
        addr_len: u32,
        msgid: c_long,
        msg: Msg,
    };

    pub const Recv = extern struct {
        recv_type: c_int,
        addr: [*]u8,
        addr_len: u32,
        msgid: c_long,
        msg: Msg,
    };

    pub const SEND_COMMAND = linux.IOCTL.IOR('i', 13, Req);
    pub const RECEIVE_MSG_TRUNC = linux.IOCTL.IOWR('i', 11, Recv);
};

pub fn maxTemperature(allocator: std.mem.Allocator) !u8 {
    if (readHwmon(allocator)) |value| {
        return value;
    }

    return error.NoTemperatureReading;
}

pub fn setFanPercent(allocator: std.mem.Allocator, percent: u8) !void {
    _ = allocator;

    if (builtin.os.tag != .linux) return error.UnsupportedPlatform;

    var state = try IpmiState.open();
    defer state.close();

    try state.sendAndCheck(0x30, 0x30, &[_]u8{ 0x01, 0x00 });
    try state.sendAndCheck(0x30, 0x30, &[_]u8{ 0x02, 0xff, percent });
}

fn readHwmon(allocator: std.mem.Allocator) ?u8 {
    if (builtin.os.tag != .linux) return null;

    var hwmon_dir = std.fs.openDirAbsolute("/sys/class/hwmon", .{ .iterate = true }) catch return null;
    defer hwmon_dir.close();

    var best: ?u8 = null;
    var iter = hwmon_dir.iterate();
    while (iter.next() catch return null) |entry| {
        if (entry.kind != .directory) continue;

        var sensor_dir = hwmon_dir.openDir(entry.name, .{ .iterate = true }) catch continue;
        defer sensor_dir.close();

        const value = readMaxTempInDir(allocator, sensor_dir) catch continue;
        if (value) |temp| {
            if (best == null or temp > best.?) best = temp;
        }
    }

    return best;
}

fn readMaxTempInDir(allocator: std.mem.Allocator, dir: std.fs.Dir) !?u8 {
    var best: ?u8 = null;
    var iter = dir.iterate();
    while (iter.next() catch return null) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.startsWith(u8, entry.name, "temp") or !std.mem.endsWith(u8, entry.name, "_input")) continue;

        const file = dir.openFile(entry.name, .{}) catch continue;
        defer file.close();

        const raw = file.readToEndAlloc(allocator, 64) catch continue;
        defer allocator.free(raw);

        const value = parseMilliCelsius(raw) catch continue;
        if (best == null or value > best.?) best = value;
    }

    return best;
}

fn parseMilliCelsius(bytes: []const u8) !u8 {
    const trimmed = std.mem.trim(u8, bytes, " \t\r\n");
    if (trimmed.len == 0) return error.InvalidTemperatureReading;

    const milli_celsius = try std.fmt.parseInt(i64, trimmed, 10);
    if (milli_celsius < 0) return error.InvalidTemperatureReading;

    return @as(u8, @intCast(@min(@divTrunc(milli_celsius, 1000), 255)));
}

const IpmiState = if (builtin.os.tag == .linux) struct {
    fd: std.posix.fd_t,
    msg_id: c_long = 1,

    fn open() !IpmiState {
        const fd = try std.posix.openZ("/dev/ipmi0", .{ .ACCMODE = .RDWR }, 0);
        return .{ .fd = fd };
    }

    fn close(self: *IpmiState) void {
        std.posix.close(self.fd);
    }

    fn sendAndCheck(self: *IpmiState, netfn: u8, cmd: u8, payload: []const u8) !void {
        var request_addr = ipmi.SystemInterfaceAddr{
            .addr_type = ipmi.IPMI_SYSTEM_INTERFACE_ADDR_TYPE,
            .channel = ipmi.IPMI_BMC_CHANNEL,
            .lun = 0,
        };

        var request_data: [ipmi.IPMI_MAX_MSG_LENGTH]u8 = undefined;
        if (payload.len > request_data.len) return error.MessageTooLong;
        std.mem.copyForwards(u8, request_data[0..payload.len], payload);

        var request = ipmi.Req{
            .addr = @as([*]u8, @ptrCast(&request_addr)),
            .addr_len = @as(u32, @intCast(@sizeOf(ipmi.SystemInterfaceAddr))),
            .msgid = self.msg_id,
            .msg = .{
                .netfn = netfn,
                .cmd = cmd,
                .data_len = @as(u16, @intCast(payload.len)),
                .data = @as([*]u8, @ptrCast(&request_data)),
            },
        };

        try self.ioctlChecked(ipmi.SEND_COMMAND, @intFromPtr(&request));
        try self.waitForResponse(self.msg_id);
        self.msg_id += 1;
    }

    fn waitForResponse(self: *IpmiState, expected_msg_id: c_long) !void {
        var response_addr = ipmi.SystemInterfaceAddr{
            .addr_type = ipmi.IPMI_SYSTEM_INTERFACE_ADDR_TYPE,
            .channel = ipmi.IPMI_BMC_CHANNEL,
            .lun = 0,
        };
        var response_data: [ipmi.IPMI_MAX_MSG_LENGTH]u8 = undefined;
        var response = ipmi.Recv{
            .recv_type = 0,
            .addr = @as([*]u8, @ptrCast(&response_addr)),
            .addr_len = @as(u32, @intCast(@sizeOf(ipmi.SystemInterfaceAddr))),
            .msgid = 0,
            .msg = .{
                .netfn = 0,
                .cmd = 0,
                .data_len = @as(u16, @intCast(response_data.len)),
                .data = @as([*]u8, @ptrCast(&response_data)),
            },
        };

        while (true) {
            response.msg.data_len = @as(u16, @intCast(response_data.len));
            response.recv_type = 0;
            response.msgid = 0;
            try self.ioctlChecked(ipmi.RECEIVE_MSG_TRUNC, @intFromPtr(&response));

            if (response.recv_type != ipmi.IPMI_RESPONSE_RECV_TYPE or response.msgid != expected_msg_id) {
                continue;
            }

            if (response.msg.data_len == 0) return error.InvalidIpmiResponse;
            if (response.msg.data[0] != ipmi.IPMI_CC_NO_ERROR) return error.IpmiCommandFailed;
            return;
        }
    }

    fn ioctlChecked(self: *IpmiState, request: u32, arg: usize) !void {
        while (true) {
            const rc = linux.ioctl(self.fd, request, arg);
            switch (std.posix.errno(rc)) {
                .SUCCESS => return,
                .INTR => continue,
                .AGAIN => continue,
                else => return error.IpmiIoctlFailed,
            }
        }
    }
} else struct {
    fd: void,

    fn open() !IpmiState {
        return error.UnsupportedPlatform;
    }

    fn close(self: *IpmiState) void {
        _ = self;
    }

    fn sendAndCheck(self: *IpmiState, netfn: u8, cmd: u8, payload: []const u8) !void {
        _ = self;
        _ = netfn;
        _ = cmd;
        _ = payload;
        return error.UnsupportedPlatform;
    }
};
