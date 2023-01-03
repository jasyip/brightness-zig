const std = @import("std");
const c = @import("c.zig");




const Allocator = std.mem.Allocator;



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




pub const RawBrightnessInfo = struct {
    allocator: Allocator,
    class: []const u8,
    device: []const u8,
    cur_val: u16,
    max_val: u16,
    percent: *c.mpd_t,

    pub fn getPercent(
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
            defer {
                c.mpd_del(simple_percent);
                c.mpd_del(inverse);
            }
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

    pub fn deinit(self: *const @This()) !void {
        c.mpd_del(self.percent);
        self.allocator.free(self.cur_val);
        self.allocator.free(self.max_val);
    }

};


pub fn newBrightessInfo(
    allocator: Allocator,
    class: []const u8,
    device: []const u8,
    cur_val: u16,
    max_val: u16,
) RawBrightnessInfo {
    std.debug.assert(cur_val <= max_val);
    const class_alloc = try allocator.dupe(u8, class);
    errdefer allocator.free(class_alloc);
    const device_alloc = try allocator.dupe(u8, device);
    errdefer allocator.free(device_alloc);
    const mpd_percent = c.mpd_qnew();
    if (@ptrToInt(mpd_percent) == 0) return error.MPD_Malloc_error;
    var output = RawBrightnessInfo {
        .allocator = allocator,
        .class = class_alloc,
        .device = device_alloc,
        .cur_val = cur_val,
        .max_val = max_val,
        .percent = try c.mpdNewZ(),
    };
    return output;
}
