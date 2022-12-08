const std = @import("std");
const clap = @import("clap");

const b = @import("brightness/brightness.zig");
const c = b.c;
usingnamespace b;


const debug = std.debug;

const exec = std.ChildProcess.exec;
const Allocator = std.mem.Allocator;



const app_name = "brightnessctl";


fn parseU16(buf: []const u8) !u16 {
    return try std.fmt.parseUnsigned(u16, buf, 10);
}


const Cmd = struct {
    device: ?[]const u8,
    class: ?[]const u8,

    fn getBrightnessInfo(self: *const @This(), allocator: Allocator) !*const b.BrightnessInfo {
        var cmd_line = std.ArrayList([]const u8).init(allocator);
        defer cmd_line.deinit();
        try cmd_line.appendSlice(&[_][]const u8{
            app_name,
            "--machine-readable",
            "info",
        });
        if (self.device) |device| {
            try cmd_line.appendSlice(&[_][]const u8{ " --device ", device });
        }
        if (self.class) |class| {
            try cmd_line.appendSlice(&[_][]const u8{ " --class ", class });
        }
        const cmd_result = try exec(.{
            .allocator = allocator,
            .argv = cmd_line.items,
        });
        defer {
            allocator.free(cmd_result.stdout);
            allocator.free(cmd_result.stderr);
        }

        const output = try allocator.create(b.BrightnessInfo);
        errdefer allocator.destroy(output);
        output.allocator = allocator;

        var iter = std.mem.tokenize(u8, cmd_result.stdout, ",");

        if (iter.next()) |token| {
            output.device = try allocator.dupe(u8, token);
        } else return error.TokenError;
        errdefer allocator.free(output.device);

        if (iter.next()) |token| {
            output.class = try allocator.dupe(u8, token);
        } else return error.TokenError;
        errdefer allocator.free(output.class);

        if (iter.next()) |token| {
            output.cur_val = try parseU16(token);
        } else return error.TokenError;

        if (iter.next() == null) return error.TokenError;

        if (iter.next()) |token| {
            output.max_val = try parseU16(std.mem.trimRight(u8, token, "\n"));
        } else return error.TokenError;

        return output;
    }
};

const Bar = struct {
    name: []const u8,
    signal_num: u8,
};

const Params = struct {
    change: *c.mpd_t,
    exponent: *c.mpd_t,
    min_value: u16,
    cmd_params: Cmd,
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
        .cmd_params = .{
            .device = res.args.device,
            .class = res.args.class,
        },
        .bar_params = if (res.args.@"bar-process-name" == null) null else .{
            .name = res.args.@"bar-process-name".?,
            .signal_num = res.args.@"signal-num".?,
        },
    };

    const brightness_info = try p.cmd_params.getBrightnessInfo(allocator);
    defer {
        brightness_info.deinit();
        allocator.destroy(brightness_info);
    }
    try b.ensureDeviceDir(allocator, brightness_info.device, brightness_info.class);

}

test "simple test" {
    const allocator = std.testing.allocator;
    const expectEqualStrings = std.testing.expectEqualStrings;

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
        "3",
        &context,
        &status,
    );

    c.mpd_qset_string(
        change,
        "12",
        &context,
        &status,
    );

    const p = Params{
        .change = change,
        .exponent = exponent,
        .min_value = 1,
        .cmd_params = .{
            .class = null,
            .device = null,
        },
        .bar_params = null,
    };
    const brightness_info = try p.cmd_params.getBrightnessInfo(allocator);
    defer {
        brightness_info.deinit();
        allocator.destroy(brightness_info);
    }

    try expectEqualStrings(brightness_info.device, "intel_backlight");
    try expectEqualStrings(brightness_info.class, "backlight");

}
