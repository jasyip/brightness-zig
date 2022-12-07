const std = @import("std");
const clap = @import("clap");

const b = @import("brightness/brightness.zig");
const c = b.c;
usingnamespace b;


const debug = std.debug;

const exec = std.ChildProcess.exec;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();


const app_name = "brightnessctl";


fn parseU16(buf: []const u8) !u16 {
    return try std.fmt.parseUnsigned(u16, buf, 10);
}


const Cmd = struct {
    class: ?[]const u8,
    device: ?[]const u8,

    fn getBrightnessInfo(self: *const @This()) !*const b.BrightnessInfo {
        var cmd_line = std.ArrayList([]const u8).init(allocator);
        defer cmd_line.deinit();
        try cmd_line.appendSlice(&[_][]const u8{
            app_name,
            "--machine-readable",
            "info",
        });
        if (self.class) |class| {
            try cmd_line.appendSlice(&[_][]const u8{ " --class ", class });
        }
        if (self.device) |device| {
            try cmd_line.appendSlice(&[_][]const u8{ " --device ", device });
        }
        debug.print("command line: {s}\n", .{cmd_line.items});
        const cmd_result = try exec(.{
            .allocator = allocator,
            .argv = cmd_line.items,
        });

        var tokens: [5][]const u8 = undefined;
        var iter = std.mem.tokenize(u8, cmd_result.stdout, ",");
        var ind: u8 = 0;
        while (ind < tokens.len) : (ind += 1) {
            if (iter.next()) |token| {
                tokens[ind] = token;
            } else {
                return error.TokenError;
            }
        }
        tokens[tokens.len - 1] = std.mem.trimRight(u8, tokens[tokens.len - 1], "\n");

        const output = try allocator.create(b.BrightnessInfo);
        errdefer allocator.destroy(output);
        output.class = tokens[0];
        output.device = tokens[1];
        output.cur_val = try parseU16(tokens[2]);
        output.max_val = try parseU16(tokens[4]);
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

    fn newPercent(brightness_info: *const b.BrightnessInfo) !*c.mpd_t {
        const cur_percent = brightness_info.getPercent();
        defer allocator.destroy(cur_percent);
    }
};

fn parserError(comptime msg: []const u8) error{InvalidParameter}!void {
    debug.print("Error while parsing arguments: " ++ msg ++ "\n", .{});
    return error.InvalidParameter;
}

pub fn main() !void {
    const params = comptime clap.parseParamsComptime(
        \\-h, --help                    Display this help and exit.
        \\-e, --exponent <str>          exponent to use in gamma adjust
        \\-n, --min-value <u16>         minimum integer brightness
        \\-c, --class <str>             class name
        \\-d, --device <str>            device name
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
    defer c.mpd_del(change);
    defer c.mpd_del(exponent);
    var status: u32 = 0;

    c.mpd_qset_string(
        exponent,
        @ptrCast([*c]const u8, res.args.exponent orelse "1"),
        &context,
        &status,
    );
    if (b.mpdError(status) or !(c.mpd_ispositive(exponent) == 1 and c.mpd_isfinite(exponent) == 1)) {
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
    if (b.mpdError(status) or c.mpd_isfinite(change) == 0) return parserError(
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
    const p: Params = .{
        .change = change,
        .exponent = exponent,
        .min_value = res.args.@"min-value" orelse 1,
        .cmd_params = .{
            .class = res.args.class,
            .device = res.args.device,
        },
        .bar_params = if (res.args.@"bar-process-name" == null) null else .{
            .name = res.args.@"bar-process-name".?,
            .signal_num = res.args.@"signal-num".?,
        },
    };

    const brightness_info = try p.cmd_params.getBrightnessInfo();
    defer allocator.destroy(brightness_info);
    debug.print(
        "class: {s} ({d}), device: {s} ({d})\n",
        .{ brightness_info.class, brightness_info.class.len, brightness_info.device, brightness_info.device.len },
    );
    try b.ensureDeviceDir(brightness_info.class, brightness_info.device);

}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
