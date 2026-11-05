//! Pitch.
//!
//! Constants' values correspond to the MIDI standard.

const std = @import("std");

pub const c0 = 12;
pub const c0_sharp = 13;
pub const d0 = 14;
pub const d0_sharp = 15;
pub const e0 = 16;
pub const f0 = 17;
pub const f0_sharp = 18;
pub const g0 = 19;
pub const g0_sharp = 20;
pub const a0 = 21;
pub const a0_sharp = 22;
pub const b0 = 23;
pub const c1 = 24;
pub const c1_sharp = 25;
pub const d1 = 26;
pub const d1_sharp = 27;
pub const e1 = 28;
pub const f1 = 29;
pub const f1_sharp = 30;
pub const g1 = 31;
pub const g1_sharp = 32;
pub const a1 = 33;
pub const a1_sharp = 34;
pub const b1 = 35;
pub const c2 = 36;
pub const c2_sharp = 37;
pub const d2 = 38;
pub const d2_sharp = 39;
pub const e2 = 40;
pub const f2 = 41;
pub const f2_sharp = 42;
pub const g2 = 43;
pub const g2_sharp = 44;
pub const a2 = 45;
pub const a2_sharp = 46;
pub const b2 = 47;
pub const c3 = 48;
pub const c3_sharp = 49;
pub const d3 = 50;
pub const d3_sharp = 51;
pub const e3 = 52;
pub const f3 = 53;
pub const f3_sharp = 54;
pub const g3 = 55;
pub const g3_sharp = 56;
pub const a3 = 57;
pub const a3_sharp = 58;
pub const b3 = 59;
pub const c4 = 60;
pub const c4_sharp = 61;
pub const d4 = 62;
pub const d4_sharp = 63;
pub const e4 = 64;
pub const f4 = 65;
pub const f4_sharp = 66;
pub const g4 = 67;
pub const g4_sharp = 68;
pub const a4 = 69;
pub const a4_sharp = 70;
pub const b4 = 71;
pub const c5 = 72;
pub const c5_sharp = 73;
pub const d5 = 74;
pub const d5_sharp = 75;
pub const e5 = 76;
pub const f5 = 77;
pub const f5_sharp = 78;
pub const g5 = 79;
pub const g5_sharp = 80;
pub const a5 = 81;
pub const a5_sharp = 82;
pub const b5 = 83;
pub const c6 = 84;
pub const c6_sharp = 85;
pub const d6 = 86;
pub const d6_sharp = 87;
pub const e6 = 88;
pub const f6 = 89;
pub const f6_sharp = 90;
pub const g6 = 91;
pub const g6_sharp = 92;
pub const a6 = 93;
pub const a6_sharp = 94;
pub const b6 = 95;
pub const c7 = 96;
pub const c7_sharp = 97;
pub const d7 = 98;
pub const d7_sharp = 99;
pub const e7 = 100;
pub const f7 = 101;
pub const f7_sharp = 102;
pub const g7 = 103;
pub const g7_sharp = 104;
pub const a7 = 105;
pub const a7_sharp = 106;
pub const b7 = 107;
pub const c8 = 108;
pub const c8_sharp = 109;
pub const d8 = 110;
pub const d8_sharp = 111;
pub const e8 = 112;
pub const f8 = 113;
pub const f8_sharp = 114;
pub const g8 = 115;
pub const g8_sharp = 116;
pub const a8 = 117;
pub const a8_sharp = 118;
pub const b8 = 119;
pub const c9 = 120;
pub const c9_sharp = 121;
pub const d9 = 122;
pub const d9_sharp = 123;
pub const e9 = 124;
pub const f9 = 125;
pub const f9_sharp = 126;
pub const g9 = 127;

/// Converts from pitch to frequency.
pub fn freq(pitch: u8) f32 {
    return 440.0 * @exp2((@as(f32, @floatFromInt(pitch)) - 69.0) / 12.0);
}

/// Returns the octave the pitch belongs to.
pub fn octave(pitch: u8) u8 {
    return pitch / 12;
}

/// Returns the pitch class the pitch belongs to.
pub fn class(pitch: u8) enum { c, c_sharp, d, d_sharp, e, f, f_sharp, g, g_sharp, a, a_sharp, b } {
    return @fromBackingInt(@truncate(pitch % 12));
}

/// Returns the color of the piano key corresponding to the given pitch.
pub fn color(pitch: u8) enum { white, black } {
    return switch (pitch % 12) {
        1, 3, 6, 8, 10 => .black,
        else => .white,
    };
}

/// Returns a human-readable name for the given pitch.
///
/// Stores the resulting string in `buf` and returns a slice containing it.
pub fn name(pitch: u8, buf: *[4]u8) []u8 {
    const class_str = switch (class(pitch)) {
        .c => "C",
        .c_sharp => "C#",
        .d => "D",
        .d_sharp => "D#",
        .e => "E",
        .f => "F",
        .f_sharp => "F#",
        .g => "G",
        .g_sharp => "G#",
        .a => "A",
        .a_sharp => "A#",
        .b => "B",
    };

    return std.mem.print(buf, "{s}{}", .{ class_str, octave(pitch) }) catch
        unreachable;
}
