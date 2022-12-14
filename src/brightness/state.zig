const std = @import("std");
const c = @import("c.zig");

const Allocator = std.mem.Allocator;



const state_dir = "/var/lib/brightness";




pub fn ensureDeviceDir(allocator: Allocator, device: []const u8, class: []const u8) !void {

    const device_dir = try std.fs.path.join(allocator, &[_][]const u8{
        state_dir, class, device,
    });
    defer allocator.free(device_dir);

    var ind: usize = std.fs.path.sep_str.len;
    while (ind < device_dir.len) {
        const upper_ind = std.mem.indexOfPosLinear(u8, device_dir, ind, std.fs.path.sep_str) orelse
            device_dir.len;
        const path = device_dir[0..upper_ind];
        std.fs.makeDirAbsolute(path) catch |err| {
            if (err != std.os.MakeDirError.PathAlreadyExists) return err;
        };
        {
            var path_dir = try std.fs.openDirAbsolute(path, .{});
            defer path_dir.close();
            var permissions = (try path_dir.metadata()).permissions();
            permissions.inner.unixSet(std.fs.File.PermissionsUnix.Class.user, .{.execute = true});
            permissions.inner.unixSet(std.fs.File.PermissionsUnix.Class.group, .{.execute = true});
            permissions.inner.unixSet(std.fs.File.PermissionsUnix.Class.other, .{.execute = true});
            try path_dir.setPermissions(permissions);
        }
        ind = upper_ind + std.fs.path.sep_str.len;
    }
}

// pub fn percentState(device_dir: []const u8, : BrightnessInfo, change: *const c.mpd_t) !?*c.mpd_t {
// 
// }
