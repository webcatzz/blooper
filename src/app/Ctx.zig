//! Application state.

const action = @import("action.zig");
const Edit = @import("Edit.zig");
const std = @import("std");
const Synth = @import("../synth/Synth.zig");

const Ctx = @This();

/// The currently edited track.
edit: Edit,
/// The current input state.
input: action.Map = .{},

/// A synthesizer used to play tracks.
synth: Synth = .{},
/// If `true`, `synth` should play the track in `edit`.
is_playing: bool = false,

gpa: std.mem.Allocator,

/// Returns a new context.
///
/// The context is owned by the caller and should be freed by calling `deinit`.
pub fn init(gpa: std.mem.Allocator) !Ctx {
    var edit: Edit = try .init(gpa);

    const pat_i = try edit.insertPattern();
    try edit.insertChannel(0, .{ .instrument = .{ .base = .{ .chip_pulse = 0.5 } } });
    try edit.insertChannel(1, .{ .instrument = .{ .base = .chip_triangle } });
    _ = try edit.insertSection(0, .{ .first_tick = 0, .last_tick = 255, .pat_i = pat_i });

    return .{
        .edit = edit,
        .gpa = gpa,
    };
}

/// Frees the context.
///
/// The context should not be used after calling this function.
pub fn deinit(self: *Ctx) void {
    self.synth.deinit(self.gpa);
    self.edit.deinit();
    self.* = undefined;
}
