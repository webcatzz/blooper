const ase = @import("ase");
const std = @import("std");

/// Opens an Aseprite file, reads its slices, and stores them in a ZON file.
///
/// Expects two command-line arguments: an input path and an output path.
pub fn main(init: std.process.Init) !void {
    var arg_iter = try init.minimal.args.iterateAllocator(init.gpa);
    defer arg_iter.deinit();

    _ = arg_iter.skip();

    const out_path = arg_iter.next() orelse return error.MissingOutPath;
    const in_path = arg_iter.next() orelse return error.MissingInPath;

    // Reads slices

    var file_buf: [64]u8 = undefined;

    const in_file = try std.Io.Dir.cwd().openFile(init.io, in_path, .{});
    defer in_file.close(init.io);

    var in_file_reader = in_file.reader(init.io, &file_buf);

    const img = try ase.read(&in_file_reader.interface, init.gpa, .{ .read_slices = true });
    defer {
        for (img.slices) |slice|
            init.gpa.free(slice.name);
        init.gpa.free(img.slices);
    }

    // Sorts info

    std.sort.block(ase.Slice, img.slices, {}, isNameLt);

    // Opens output file

    const out_file = try std.Io.Dir.cwd().createFile(init.io, out_path, .{});
    defer out_file.close(init.io);

    var out_file_writer = out_file.writer(init.io, &file_buf);
    const writer = &out_file_writer.interface;

    // Writes zon

    try writer.writeAll(".{\n");
    for (img.slices) |slice|
        try writer.print(
            \\    .{s} = .{{
            \\        .rect = .{{ .x = {}, .y = {}, .w = {}, .h = {} }},
            \\        .border = .{{ .left = {}, .right = {}, .top = {}, .bottom = {} }},
            \\    }},
            \\
        , .{
            slice.name,
            slice.x,
            slice.y,
            slice.w,
            slice.h,
            slice.center_x,
            slice.w - (slice.center_x + slice.center_w),
            slice.center_y,
            slice.h - (slice.center_y + slice.center_h),
        });
    try writer.writeAll("}\n");
    try writer.flush();
}

fn isNameLt(_: void, a: ase.Slice, b: ase.Slice) bool {
    return std.mem.order(u8, a.name, b.name) == .lt;
}
