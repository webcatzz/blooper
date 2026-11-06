//! State shared by UI elements.

const action = @import("action.zig");
const Edit = @import("Edit.zig");
const std = @import("std");
const Synth = @import("../synth/Synth.zig");

const Ctx = @This();

edit: Edit,
input: action.Map = .{},

/// A synthesizer used to play tracks.
synth: Synth = .{},
/// If `true`, `synth` should play the track in `edit`.
is_playing: bool = false,

gpa: std.mem.Allocator,

pub fn init(gpa: std.mem.Allocator) !Ctx {
    var edit: Edit = try .init(gpa);

    const pat_i = try edit.insertPattern();
    try edit.insertChannel(0, .{ .instrument = .{ .base = .{ .chip_pulse = 0.5 } } });
    try edit.insertChannel(1, .{ .instrument = .{ .base = .{ .chip_pulse = 0.5 } } });
    _ = try edit.insertSection(0, .{ .first_tick = 0, .last_tick = 384, .pat_i = pat_i });

    return .{
        .edit = edit,
        .gpa = gpa,
    };
}

pub fn deinit(self: *Ctx) void {
    self.synth.deinit(self.gpa);
    self.edit.deinit();
}
