const std = @import("std");
const c = @import("c.zig");




const Allocator = std.mem.Allocator;

const app_name = "brightnessctl";
const exec = std.ChildProcess.exec;


pub fn mpdError(status: *u32) bool {
    const output: bool = status.* & c.MPD_Errors != 0;
    status.* = 0;
    return output;
}
pub fn mpdAssert(status: *u32) !void {
    if (mpdError(status)) {
        return error.MPDecError;
    }
}



fn parseU16(buf: []const u8) !u16 {
    return try std.fmt.parseUnsigned(u16, buf, 10);
}

pub const BrightnessInfo = struct {
    allocator: Allocator,
    class: []const u8,
    device: []const u8,
    cur_val: u16,
    max_val: u16,

    fn getPercent(
        self: *const @This(),
        exponent: *const c.mpd_t,
        context: *const c.mpd_context_t,
    ) !*c.mpd_t {
        const output = c.mpd_new(context);
        errdefer c.mpd_del(output);

        {
            var status: u32 = 0;
            const simple_percent = c.mpd_new(context);
            const inverse = c.mpd_new(context);
            defer c.mpd_del(simple_percent);
            defer c.mpd_del(inverse);
            {
                const cur_val = c.mpd_new(context);
                defer c.mpd_del(cur_val);
                c.mpd_set_u32(cur_val, self.cur_val, context);
                c.mpd_qdiv_u32(simple_percent, cur_val, self.max_val, context, &status);
                try mpdAssert(&status);
            }
            {
                const one = c.mpd_new(context);
                defer c.mpd_del(one);
                c.mpd_set_u32(one, 1, context);
                c.mpd_qdiv(inverse, one, exponent, context, &status);
                try mpdAssert(&status);
            }
            c.mpd_qexp(output, simple_percent, inverse, context, &status);
            try mpdAssert(&status);
        }

        return output;
    }


    pub fn deinit(self: *const @This()) void {
        self.allocator.free(self.class);
        self.allocator.free(self.device);
    }

};

pub fn brightnessctlInfo(allocator: Allocator, device: ?[]const u8, class: ?[]const u8) !BrightnessInfo {

    var cmd_line = std.ArrayList([]const u8).init(allocator);
    defer cmd_line.deinit();
    try cmd_line.appendSlice(&[_][]const u8{
        app_name,
        "--machine-readable",
        "info",
    });
    if (device) |device_str| {
        try cmd_line.appendSlice(&[_][]const u8{ " --device ", device_str });
    }
    if (class) |class_str| {
        try cmd_line.appendSlice(&[_][]const u8{ " --class ", class_str });
    }
    const cmd_result = try exec(.{
        .allocator = allocator,
        .argv = cmd_line.items,
    });
    defer {
        allocator.free(cmd_result.stdout);
        allocator.free(cmd_result.stderr);
    }

    var tokens: [5][]const u8 = undefined;
    if (std.mem.count(u8, cmd_result.stdout, ",") != tokens.len - 1) return error.TokenError;
    var iter = std.mem.tokenize(u8, cmd_result.stdout, ",");
    for (tokens) |*token| {
        token.* = iter.next().?;
    }

    const device_val = try allocator.dupe(u8, tokens[0]);
    errdefer allocator.free(device_val);
    const class_val = try allocator.dupe(u8, tokens[1]);
    errdefer allocator.free(class_val);

    return BrightnessInfo {
        .allocator = allocator,
        .device = device_val,
        .class = class_val,
        .cur_val = try parseU16(tokens[2]),
        .max_val = try parseU16(std.mem.trimRight(u8, tokens[4], "\n")),
    };
}
