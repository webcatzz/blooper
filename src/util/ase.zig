//! Aseprite file reading.
//!
//! Provides a compile-time configurable function to read Aseprite file data. It
//! is compile-time configurable so it can be used both by the application and
//! the build system for different purposes.

const std = @import("std");

/// Options for reading an Aseprite file.
const Options = struct {
    read_data: bool = false,
    read_slices: bool = false,
};

/// A slice in an Aseprite file.
const Slice = struct {
    name: []const u8,
    x: f32,
    y: f32,
    w: f32,
    h: f32,
    center_x: f32,
    center_y: f32,
    center_w: f32,
    center_h: f32,
};

/// Reads Aseprite file data from `reader`.
///
/// Purposefully enforces the following limitations:
///
/// - Only RGBA sprites (i.e. color depth of 32bpp) are supported.
/// - Only the first frame is read.
/// - Only the bottom layer is read.
/// - Ignores cels' z-indices.
/// - Only reads image data if `opts.read_data` is `true`.
///     - Only supports image cels (not linked or tilemap cels).
/// - Only reads slice chunks if `opts.read_slices` is `true`.
///     - Slices' positions must not be negative (i.e. x >= 0, y >= 0).
/// - Discards all other chunks.
///
/// If `opts.read_data` is true, the returned `data` buffer is owned by the
/// caller. If `opts.read_slices` is true, the returned `slices` buffer as well
/// as the slices' names are owned by the caller.
///
/// Asserts `reader` has a buffer with a capacity of at least 4.
pub fn read(reader: *std.Io.Reader, gpa: std.mem.Allocator, comptime opts: Options) !struct {
    width: if (opts.read_data) u16 else void,
    height: if (opts.read_data) u16 else void,
    data: if (opts.read_data) []u8 else void,
    slices: if (opts.read_slices) []Slice else void,
} {
    // Based on the Aseprite file specs, commit #c9baf29
    // https://github.com/aseprite/aseprite/blob/main/docs/ase-file-specs.md

    const bytes_per_pixel: u32 = 4;

    // Reads header

    try reader.discardAll(4); // Discards file size
    if (try reader.takeInt(u16, .little) != 0xa5e0) // Checks magic number
        return error.InvalidMagicNumber;

    try reader.discardAll(2); // Discards frame count
    const width = try reader.takeInt(u16, .little);
    const height = try reader.takeInt(u16, .little);

    if (try reader.takeInt(u16, .little) != 32) // Checks color depth
        return error.UnsupportedColorDepth;

    try reader.discardAll(114); // Discards rest of header

    // Sets up buffers

    const data =
        if (opts.read_data)
            try gpa.alloc(u8, bytes_per_pixel * width * height)
        else {};
    if (opts.read_data) @memset(data, 0);
    errdefer if (opts.read_data) gpa.free(data);

    const slices =
        if (opts.read_slices)
            std.ArrayList(Slice).empty
        else {};
    errdefer if (opts.read_slices) slices.deinit(gpa);

    // Reads first frame header

    try reader.discardAll(4); // Discards frame byte size
    if (try reader.takeInt(u16, .little) != 0xf1fa) // Checks magic number
        return error.InvalidMagicNumber;

    const chunk_count_old = try reader.takeInt(u16, .little);
    try reader.discardAll(4); // Discards frame duration + reserved bytes
    const chunk_count_new = try reader.takeInt(u32, .little);

    const chunk_count = if (chunk_count_new == 0) chunk_count_old else chunk_count_new;

    // Reads chunks

    for (0..chunk_count) |_| {
        const chunk_size = try reader.takeInt(u32, .little) - 6;
        const chunk_type = try reader.takeInt(u16, .little);

        chunk_switch: switch (chunk_type) {
            0x2005 => { // Cel chunk
                if (!opts.read_data) continue :chunk_switch 0;

                if (try reader.takeInt(u16, .little) != 0) { // Skips cels in other layers
                    try reader.discardAll(chunk_size - 2);
                    continue;
                }

                const cel_x = try reader.takeInt(i16, .little);
                const cel_y = try reader.takeInt(i16, .little);
                try reader.discardAll(1); // Discards opacity
                const cel_type = try reader.takeInt(u16, .little);
                try reader.discardAll(7); // Discards z-index + reserved bytes

                switch (cel_type) {
                    0 => { // Uncompressed image
                        const cel_w = try reader.takeInt(u16, .little);
                        const cel_h = try reader.takeInt(u16, .little);
                        const cel_stride = cel_w * bytes_per_pixel;

                        for (@intCast(cel_y)..cel_h) |y|
                            try reader.readSliceAll(data[(@as(u16, @intCast(cel_x)) + y * width) * bytes_per_pixel ..][0..cel_stride]);
                    },

                    2 => { // Compressed image
                        const cel_w = try reader.takeInt(u16, .little);
                        const cel_h = try reader.takeInt(u16, .little);
                        const cel_stride = cel_w * bytes_per_pixel;

                        var decompression_buf: [std.compress.flate.max_window_len]u8 = undefined;
                        var decompressor: std.compress.flate.Decompress = .init(reader, .zlib, &decompression_buf);

                        for (@intCast(cel_y)..cel_h) |y|
                            try decompressor.reader.readSliceAll(data[(@as(u16, @intCast(cel_x)) + y * width) * bytes_per_pixel ..][0..cel_stride]);
                    },

                    1, 3 => return error.UnsupportedCelType,
                    else => return error.UnknownCelType,
                }
            },

            0x2022 => { // Slice chunk
                if (!opts.read_slices) continue :chunk_switch 0;

                const slice_key_count = try reader.takeInt(u32, .little);
                const slice_flags = try reader.takeInt(u32, .little);
                try reader.discardAll(4); // Discards reserved bytes

                const name_len = try reader.takeInt(u16, .little);
                const name = try reader.readAllocAll(gpa, name_len);

                if (try reader.takeInt(u32, .little) == 0) {
                    var slice: Slice = undefined;

                    try reader.discardAll(4); // Discards frame number
                    slice.x = try reader.takeInt(i32, .little);
                    slice.y = try reader.takeInt(i32, .little);
                    slice.w = try reader.takeInt(u32, .little);
                    slice.h = try reader.takeInt(u32, .little);

                    if (slice.x < 0 or slice.y < 0)
                        return error.NegativeSlicePosition;

                    if (slice_flags & 0b1 != 0) {
                        slice.center_x = try reader.takeInt(i32, .little);
                        slice.center_y = try reader.takeInt(i32, .little);
                        slice.center_w = try reader.takeInt(u32, .little);
                        slice.center_h = try reader.takeInt(u32, .little);
                    } else {
                        slice.center_x = 0;
                        slice.center_y = 0;
                        slice.center_w = 0;
                        slice.center_h = 0;
                    }

                    if (slice_flags & 0b10 != 0)
                        try reader.discardAll(8); // Discards pivot position

                    try slices.append(gpa, slice);
                } else { // Discards slices after first frame
                    gpa.free(name); // Frees name
                    try reader.discardAll(16 +
                        16 * @intFromBool(slice_flags & 0b1 != 0) +
                        8 * @intFromBool(slice_flags & 0b10 != 0)); // Discards rest of slice key
                }

                try reader.discardAll((slice_key_count - 1) * (20 +
                    16 * @intFromBool(slice_flags & 0b1 != 0) +
                    8 * @intFromBool(slice_flags & 0b10 != 0))); // Discards other slice keys
            },

            else => try reader.discardAll(chunk_size), // Discards other chunks
        }
    }

    return .{
        .width = if (opts.read_data) width else {},
        .height = if (opts.read_data) height else {},
        .data = if (opts.read_data) data else {},
        .slices = if (opts.read_slices) slices.toOwnedSlice(gpa) else {},
    };
}
