const std = @import("std");
const zlib = @import("zlib");

const Png = @This();

width: u32,
height: u32,
data: []u8,

/// Reads PNG data from `reader`.
///
/// Purposefully enforces the following limitations:
///
/// - Image data should use a bit depth of 8.
/// - Image data should use the RGBA color type.
/// - Image data should not be interlaced.
pub fn read(gpa: std.mem.Allocator, reader: *std.Io.Reader) !Png {
    // Based on the PNG specification, version 1.2
    // https://www.libpng.org/pub/png/spec/1.2/PNG-Contents.html

    var buf: [32]u8 = undefined;

    // Verifies PNG signature

    try reader.readSliceAll(buf[0..8]);
    if (std.mem.readInt(u64, buf[0..8], .big) != 0x89504e470d0a1a0a)
        return error.InvalidPng;

    // Reads PNG IHDR chunk

    try reader.readSliceAll(buf[0..25]);
    if (std.mem.readInt(u32, buf[0..4], .big) != 13 or
        std.mem.readInt(u32, buf[4..8], .big) != std.mem.readInt(u32, "IHDR", .big)) return error.InvalidPng;

    const width = std.mem.readInt(u32, buf[8..12], .big);
    const height = std.mem.readInt(u32, buf[12..16], .big);

    if (buf[16] != 8) {
        std.log.err("Spritesheet PNG bit depth should be 8, is {}", .{buf[16]});
        return error.UnsupportedPngBitDepth;
    }
    if (buf[17] != 6) {
        std.log.err("Spritesheet color type should be 6, is {}", .{buf[17]});
        return error.UnsupportedPngColorType;
    }
    if (buf[18] != 0) {
        std.log.err("Spritesheet compression method should be 0, is {}", .{buf[18]});
        return error.UnsupportedPngCompressionMethod;
    }
    if (buf[19] != 0) {
        std.log.err("Spritesheet filter method should be 0, is {}", .{buf[19]});
        return error.UnsupportedPngFilterMethod;
    }
    if (buf[20] != 0) {
        std.log.err("Spritesheet interlace method should be 0, is {}", .{buf[20]});
        return error.UnsupportedPngInterlaceMethod;
    }

    // Sets up decompression buffers

    const bytes_per_pixel = 4;
    const bytes_per_row = width * bytes_per_pixel;
    const bytes_per_scanline = bytes_per_row + 1;

    var data = try gpa.alloc(u8, bytes_per_scanline * height);
    errdefer gpa.free(data);

    var data_writer: std.Io.Writer = .fixed(data);

    // Reads following PNG chunks

    while (true) {
        try reader.readSliceAll(buf[0..8]);
        const chunk_len = std.mem.readInt(u32, buf[0..4], .big);
        const chunk_type = std.mem.readInt(u32, buf[4..8], .big);

        switch (chunk_type) {
            std.mem.readInt(u32, "IDAT", .big) => {
                var decompress_buf: [std.compress.flate.max_window_len]u8 = undefined;
                var decompressor: std.compress.flate.Decompress = .init(reader, .zlib, &decompress_buf);
                _ = try decompressor.reader.streamRemaining(&data_writer);
            },

            std.mem.readInt(u32, "IEND", .big) => break,

            else => if (std.ascii.isUpper(buf[4])) {
                std.log.err("Unknown critical PNG chunk: {s}", .{buf[4..8]});
                return error.UnknownCriticalPngChunk;
            } else {
                try reader.discardAll(chunk_len);
            },
        }

        try reader.discardAll(4); // Discards CRC
    }

    // Reverses per-scanline filters

    for (0..height) |y| {
        const i = y * bytes_per_scanline + 1;

        switch (data[i - 1]) {
            0 => {},
            // Sub
            1 => for (bytes_per_pixel..bytes_per_scanline - 1) |x| {
                data[i + x] +%=
                    data[i + x - bytes_per_pixel];
            },
            // Up
            2 => if (y > 0) for (0..bytes_per_scanline - 1) |x| {
                data[i + x] +%=
                    data[i + x - bytes_per_scanline];
            },
            // Average
            3 => for (0..bytes_per_scanline - 1) |x| {
                data[i + x] +%=
                    ((if (x < bytes_per_pixel) 0 else data[i + x - bytes_per_pixel]) +
                        (if (y == 0) 0 else data[i + x - bytes_per_scanline])) / 2;
            },
            // Paeth
            4 => for (0..bytes_per_scanline - 1) |x| {
                const a = if (x < bytes_per_pixel) 0 else data[i + x - bytes_per_pixel];
                const b = if (y == 0) 0 else data[i + x - bytes_per_scanline];
                const c = if (x < bytes_per_pixel or y == 0) 0 else data[i + x - bytes_per_scanline - bytes_per_pixel];

                const p = @as(i32, a) + b - c;
                const pa = @abs(p - a);
                const pb = @abs(p - b);
                const pc = @abs(p - c);

                data[i + x] +%= if (pa <= pb and pa <= pc) a else if (pb <= pc) b else c;
            },

            else => |filter_type| {
                std.log.err("Unsupported PNG scanline filter type: {}", .{filter_type});
                return error.UnsupportedPngScanlineFilterType;
            },
        }
    }

    // Removes filter bytes

    for (0..height) |y|
        @memmove(
            data[y * bytes_per_row ..][0..bytes_per_row],
            data[y * bytes_per_scanline + 1 ..][0..bytes_per_row],
        );
    data = try gpa.realloc(data, data.len - height);

    // Returns

    return .{
        .width = width,
        .height = height,
        .data = data,
    };
}
