//! Synthesizes audio from track data.

const pitch_util = @import("pitch.zig");
const std = @import("std");
const Track = @import("Track.zig");

const Synth = @This();

/// The synth's current position, in ticks.
tick: u64 = 0,
/// The number of sequential samples synthesized since the last seek operation.
smps_synthed: u64 = 0,
/// The number of samples left in the current tick.
smps_left_in_tick: u32 = 0,

chans: std.ArrayList(Channel) = .empty,

const Channel = struct {
    inst: Track.Instrument = .{ .base = .{ .chip_pulse = 0.5 } },
    /// Currently active notes.
    notes: std.ArrayList(Note) = .empty,

    fn update(self: *Channel, gpa: std.mem.Allocator, chan: Track.Channel, pats: []const Track.Pattern, tick: u64) !void {
        self.inst = chan.instrument;
        self.notes.clearRetainingCapacity();

        const sect = init: {
            for (chan.sections) |sect|
                if (sect.first_tick <= tick and sect.last_tick >= tick)
                    break :init sect;
            return;
        };

        for (pats[sect.pat_i].notes) |note|
            if (sect.first_tick + note.first_tick <= tick and sect.first_tick + note.last_tick >= tick)
                try self.notes.append(gpa, .{ .pitch = note.pitch, .volume = note.volume });
    }

    fn synth(self: *Channel, smp_off: usize, smp_rate: u32, output: []f32) void {
        for (self.notes.items) |*note|
            for (output, 0..) |*smp, i| {
                const phase = @as(f32, @floatFromInt(smp_off + i)) * pitch_util.freq(note.pitch) / @as(f32, @floatFromInt(smp_rate));
                const phase_fract = phase - @trunc(phase);

                smp.* += switch (self.inst.base) {
                    .chip_pulse => |duty| chipPulse(phase_fract, duty),
                    .chip_triangle => chipTriangle(phase_fract),
                    .chip_sine => chipSine(phase_fract),
                } * @as(f32, @floatFromInt(note.volume)) / 0xff;
            };
    }
};

const Note = struct {
    pitch: u8,
    volume: u8,
};

/// Frees the synth.
///
/// The synth should not be used after this function is called.
pub fn deinit(self: *Synth, gpa: std.mem.Allocator) void {
    for (self.chans.items) |*chan|
        chan.notes.deinit(gpa);
    self.chans.deinit(gpa);
}

/// Synthesizes audio from `track` into `output`.
///
/// If this function is called, the synth should be freed by calling `deinit`.
pub fn run(self: *Synth, gpa: std.mem.Allocator, track: Track, smp_rate: u32, output: []f32) !void {
    // Resizes channels to accomodate track

    const old_chan_count = self.chans.items.len;
    if (track.channels.len < self.chans.items.len)
        for (self.chans.items[track.channels.len..]) |*chan|
            chan.notes.deinit(gpa);
    try self.chans.resize(gpa, track.channels.len);
    for (self.chans.items[old_chan_count..]) |*chan|
        chan.notes = .empty;

    var smp_i: u32 = 0;
    while (smp_i < output.len) {
        // Updates if necessary

        if (self.smps_left_in_tick == 0) {
            self.tick += 1;
            self.smps_left_in_tick = smp_rate / track.tempo;

            for (self.chans.items, track.channels) |*synth_chan, track_chan|
                try synth_chan.update(gpa, track_chan, track.patterns, self.tick);
        }

        // Synthesizes

        const run_len = @min(self.smps_left_in_tick, output.len - smp_i);

        for (self.chans.items) |*chan|
            chan.synth(self.smps_synthed, smp_rate, output[smp_i..][0..run_len]);

        smp_i += run_len;
        self.smps_synthed += run_len;
        self.smps_left_in_tick -= run_len;
    }
}

/// Seeks to the given position, in ticks.
pub fn seek(self: *Synth, tick: u64) void {
    self.tick = tick;
    self.smps_synthed = 0;
}

/// Samples a pulse wave with the given duty cycle at the given phase.
///
/// - `phase` should be a value in \[0.0, 1.0).
/// - `duty` should be a value in \[0.0, 1.0) representing the ratio of the
///   pulse duration to the total period, e.g. `0.25` for a 1/4 pulse or `0.5`
///   for a square wave.
pub fn chipPulse(phase: f32, duty: f32) f32 {
    return @floatFromInt(@intFromBool(phase <= duty));
}

/// Samples a triangle wave at the given phase.
///
/// - `phase` should be a value in \[0.0, 1.0).
pub fn chipTriangle(phase: f32) f32 {
    return @abs(phase - @floor(phase + 0.5)) * 2.0;
}

/// Samples a sine wave at the given phase.
///
/// - `phase` should be a value in \[0.0, 1.0).
pub fn chipSine(phase: f32) f32 {
    return @sin(phase * std.math.tau);
}
