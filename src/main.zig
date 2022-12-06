const std = @import("std");
const clap = @import("clap");
const mpd = @cImport(@cInclude("mpdecimal.h"));


const debug = std.debug;
const io = std.io;

const exec = std.ChildProcess.exec;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();



const appName = "brightnessctl";
const stateDir = "/var/lib";





fn parseU16(buf: []const u8) !u16 { return try std.fmt.parseUnsigned(u16, buf, 10); }


const BrightnessInfo = struct {
    class: [] const u8,
    device: [] const u8,
    curVal: u16,
    maxVal: u16,

    fn getPercent(self: *const Cmd, exponent: f64) !f64 {
        _ = exponent;
        return self.curVal / self.maxVal;
    }
};

const Cmd = struct {
    class: ?[] const u8,
    device: ?[] const u8,


    fn getBrightnessInfo(self: *const Cmd) !BrightnessInfo {
        var cmdLine = std.ArrayList([]const u8).init(allocator);
        defer cmdLine.deinit();
        try cmdLine.appendSlice(&[_][] const u8 {
            appName,
            "--machine-readable",
            "info",
        });
        if (self.class) |class| {
            try cmdLine.appendSlice(&[_][] const u8 { " --class ", class });
        }
        if (self.device) |device| {
            try cmdLine.appendSlice(&[_][] const u8 { " --device ", device });
        }
        debug.print("command line: {s}\n", .{cmdLine.items});
        const cmdResult = try exec(.{
            .allocator = allocator,
            .argv = cmdLine.items,
        });

        var tokens: [5][]const u8 = undefined;
        var iter = std.mem.tokenize(u8, cmdResult.stdout, ",");
        var ind: u8 = 0;
        while (ind < tokens.len) : (ind += 1) {
            if (iter.next()) |token| {
                tokens[ind] = token;
            } else {
                return error.TokenError;
            }
        }
        tokens[tokens.len - 1] = std.mem.trimRight(u8, tokens[tokens.len - 1], "\n");

        return .{
            .class = tokens[0],
            .device = tokens[1],
            .curVal = try parseU16(tokens[2]),
            .maxVal = try parseU16(tokens[4]),
        };
    }
};

const Bar = struct {
    name: []const u8,
    signalNum: u8,
};

const Params = struct {
    change: i8,
    exponent: *mpd.mpd_t,
    minValue: u16,
    cmdParams: Cmd,
    barParams: ?Bar,
};









fn parserError(comptime msg: []const u8) error{InvalidParameter}!void {
    debug.print(msg ++ "\n", .{});
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
        \\<i8>                          percent value to change brightness
    );


    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{.diagnostic = &diag})
            catch |err| {
                diag.report(io.getStdErr().writer(), err) catch {};
                return err;
            };
    defer res.deinit();

    if (res.args.help) {
        return clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});
    }
    if (res.positionals.len != 1) {
        return parserError("Error while parsing arguments: "
                ++ "Must have exactly one positional argument for brightness change value"
                );
    }

    const change: i8 = res.positionals[0];

    var context: mpd.mpd_context_t = undefined;
    mpd.mpd_defaultcontext(&context);

    const exponent = mpd.mpd_new(&context);
    defer mpd.mpd_del(exponent);
    mpd.mpd_set_string(exponent, @ptrCast([*c]const u8, res.args.exponent orelse "1"), &context);
    if (mpd.mpd_getstatus(&context) & mpd.MPD_Invalid_operation != 0
            or !(mpd.mpd_ispositive(exponent) == 1 and mpd.mpd_isfinite(exponent) == 1)) {
        return parserError("Error while parsing arguments: `--exponent` must be a positive number");
    }

    if (try std.math.absInt(change) > 100) {
        return parserError("Error while parsing arguments: "
                ++ "brightness change value cannot be over 100%",
                );
    }
    if ((res.args.@"bar-process-name" == null) != (res.args.@"signal-num" == null)) {
        return parserError("Error while parsing arguments: "
                ++ "`--bar-process-name` and `--signal-num` must be both present or absent",
                );
    }
    const p: Params = .{
        .change = change,
        .exponent = exponent,
        .minValue = res.args.@"min-value" orelse 1,
        .cmdParams = .{
            .class = res.args.class,
            .device = res.args.device,
        },
        .barParams = if (res.args.@"bar-process-name" == null) null else .{
            .name = res.args.@"bar-process-name".?,
            .signalNum = res.args.@"signal-num".?,
        },
    };

    const b = try p.cmdParams.getBrightnessInfo();
    debug.print("class: {s} ({d}), device: {s} ({d})\n", .{b.class, b.class.len, b.device, b.device.len});






}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
