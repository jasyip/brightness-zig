const std = @import("std");
const info = @import("info.zig");
const c = @import("c.zig");


const Allocator = std.mem.Allocator;

pub const Bar = struct {
    name: []const u8,
    signal_num: u8,
};

pub const Params = struct {
    change: *const c.mpd_t,
    exponent: *const c.mpd_t,
    min_value: u16,
    device: ?[]const u8,
    class: ?[]const u8,
    bar_params: ?Bar,

    fn newPercent(self: *const @This(), allocator: Allocator, brightness_info: *const info.RawBrightnessInfo) !*c.mpd_t {
        _ = self;
        const cur_percent = brightness_info.getPercent(allocator);
        defer allocator.destroy(cur_percent);
    }
};

