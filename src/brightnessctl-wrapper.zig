const std = @import("std");
const clap = @import("clap");

const b = @import("brightness/brightness.zig");
const c = b.c;
usingnamespace b;


const debug = std.debug;

const Allocator = std.mem.Allocator;








const Bar = struct {
    name: []const u8,
    signal_num: u8,
};

const Params = struct {
    change: *c.mpd_t,
    exponent: *c.mpd_t,
    min_value: u16,
    device: ?[]const u8,
    class: ?[]const u8,
    bar_params: ?Bar,

    fn newPercent(self: *const @This(), allocator: Allocator, brightness_info: *const b.BrightnessInfo) !*c.mpd_t {
        _ = self;
        const cur_percent = brightness_info.getPercent(allocator);
        defer allocator.destroy(cur_percent);
    }
};

fn parserError(comptime msg: []const u8) error{InvalidParameter}!void {
    debug.print("Error while parsing arguments: " ++ msg ++ "\n", .{});
    return error.InvalidParameter;
}

pub fn main() !void {

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const params = comptime clap.parseParamsComptime(
        \\-h, --help                    Display this help and exit.
        \\-e, --exponent <str>          exponent to use in gamma adjust
        \\-n, --min-value <u16>         minimum integer brightness
        \\-d, --device <str>            device name
        \\-c, --class <str>             device class name
        \\-b, --bar-process-name <str>  name of the bar this program should signal upon changing brightness
        \\-s, --signal-num <u8>         sends signal of SIGRTMIN+{signalNum} to the bar process
        \\<str>                         percent value to change brightness
    );

    var diag = clap.Diagnostic{};
    var res = clap.parse(
        clap.Help,
        &params,
        clap.parsers.default,
        .{ .diagnostic = &diag },
    ) catch |err| {
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();

    if (res.args.help) {
        return clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});
    }
    if (res.positionals.len != 1) {
        return parserError(
            "Must have exactly one positional argument for brightness change value",
        );
    }


    var context: c.mpd_context_t = undefined;
    c.mpd_defaultcontext(&context);

    const change = c.mpd_new(&context);
    const exponent = c.mpd_new(&context);
    defer {
        c.mpd_del(change);
        c.mpd_del(exponent);
    }
    var status: u32 = 0;

    c.mpd_qset_string(
        exponent,
        @ptrCast([*c]const u8, res.args.exponent orelse "1"),
        &context,
        &status,
    );
    if (b.mpdError(&status) or !(c.mpd_ispositive(exponent) == 1 and c.mpd_isfinite(exponent) == 1)) {
        return parserError(
            "`--exponent` must be a positive number",
        );
    }

    c.mpd_qset_string(
        change,
        @ptrCast([*c]const u8, res.positionals[0]),
        &context,
        &status,
    );
    if (b.mpdError(&status) or c.mpd_isfinite(change) == 0) return parserError(
        "brightness change value must be a valid number"
    );
    {
        const hundred = c.mpd_new(&context);
        defer c.mpd_del(hundred);
        c.mpd_set_u32(hundred, 100, &context);
        if (c.mpd_cmp_total_mag(change, hundred) == 1) return parserError(
            "brightness change value cannot be over 100%"
        );
    }

    if ((res.args.@"bar-process-name" == null) != (res.args.@"signal-num" == null)) {
        return parserError(
                "`--bar-process-name` and `--signal-num` must be" ++ "both present or absent"
        );
    }
    const p = Params{
        .change = change,
        .exponent = exponent,
        .min_value = res.args.@"min-value" orelse 1,
        .device = res.args.device,
        .class = res.args.class,
        .bar_params = if (res.args.@"bar-process-name" == null) null else .{
            .name = res.args.@"bar-process-name".?,
            .signal_num = res.args.@"signal-num".?,
        },
    };

    const brightness_info = try b.brightnessctlInfo(allocator, p.device, p.class);
    defer brightness_info.deinit();
    try b.ensureDeviceDir(allocator, brightness_info.device, brightness_info.class);

}

test "simple test" {
    const allocator = std.testing.allocator;
    const expectEqualStrings = std.testing.expectEqualStrings;

    // var context: c.mpd_context_t = undefined;
    // c.mpd_defaultcontext(&context);

    // const change = c.mpd_new(&context);
    // const exponent = c.mpd_new(&context);
    // defer {
    //     c.mpd_del(change);
    //     c.mpd_del(exponent);
    // }
    // var status: u32 = 0;

    // c.mpd_qset_string(
    //     exponent,
    //     "3",
    //     &context,
    //     &status,
    // );

    // c.mpd_qset_string(
    //     change,
    //     "12",
    //     &context,
    //     &status,
    // );

    const brightness_info = try b.brightnessctlInfo(allocator, null, null);
    defer brightness_info.deinit();

    try expectEqualStrings(brightness_info.device, "intel_backlight");
    try expectEqualStrings(brightness_info.class, "backlight");

}
