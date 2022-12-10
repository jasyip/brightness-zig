const std = @import("std");
const clap = @import("clap");

const b = @import("brightness/brightness.zig");
const c = b.c;
usingnamespace b;


const debug = std.debug;

const Allocator = std.mem.Allocator;






fn parseU16(buf: []const u8) !u16 {
    return try std.fmt.parseUnsigned(u16, buf, 10);
}

const app_name = "brightnessctl";

fn brightnessctlInfo(allocator: Allocator, device: ?[]const u8, class: ?[]const u8) !b.BrightnessInfo {

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
    const cmd_result = try std.ChildProcess.exec(.{
        .allocator = allocator,
        .argv = cmd_line.items,
    });
    if (cmd_result.term.Exited != 0) return error.SubcommandError;
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

    return b.BrightnessInfo {
        .allocator = allocator,
        .device = device_val,
        .class = class_val,
        .cur_val = try parseU16(tokens[2]),
        .max_val = try parseU16(std.mem.trimRight(u8, tokens[4], "\n")),
    };
}



fn parserError(comptime msg: []const u8) error{InvalidParameter}!void {
    debug.print("Error while parsing arguments: " ++ msg ++ "\n", .{});
    return error.InvalidParameter;
}

pub fn main() !void {

    // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // const allocator = gpa.allocator();
    const allocator = std.heap.c_allocator;

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
    const p = b.Params{
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

    const brightness_info = try brightnessctlInfo(allocator, p.device, p.class);
    defer brightness_info.deinit();
    // try b.ensureDeviceDir(allocator, brightness_info.device, brightness_info.class);

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

    const brightness_info = try brightnessctlInfo(allocator, null, null);
    defer brightness_info.deinit();

    try expectEqualStrings(brightness_info.device, "intel_backlight");
    try expectEqualStrings(brightness_info.class, "backlight");

}
