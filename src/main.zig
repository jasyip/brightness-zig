const std = @import("std");
const clap = @import("clap");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

const appName = "brightness";
const stateDir = "/var/lib";





pub fn main() !void {
    const params = comptime clap.parseParamsComptime(
        \\-h, --help | Display this help and exit.
        \\-e, --exponent | exponent to use in gamma adjust
        \\-n, --min-value | minimum integer brightness
        \\-c, --class | class name
        \\-d, --device | device name
        \\-b, --bar-process-name | name of the bar this program should signal upon changing brightness
        \\-s, --signal-num | sends signal of SIGRTMIN+{signalNum} to the bar process
    );

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{.diagnostic = &diag})
            catch |err| {
                diag.report(io.getStdErr().writer(), err) catch {};
                return err;
            };
    defer res.deinit();


}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
