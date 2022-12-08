const std = @import("std");
const c = @import("c.zig");



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



const Allocator = std.mem.Allocator;


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

