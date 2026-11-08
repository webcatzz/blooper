//! Track data used to synthesize audio.

const std = @import("std");

const Track = @This();

/// The playback rate, in ticks-per-second.
tempo: u16 = 450,
/// The channels in the track.
///
/// There should be no more than 2^16 channels.
channels: []Channel = &.{},
/// The patterns in the track.
///
/// There should be no more than 2^16 patterns.
patterns: []Pattern = &.{},

pub const Channel = struct {
    /// The instrument used to play notes in the channel.
    instrument: Instrument = .{ .base = .{ .chip_pulse = 0.5 } },
    /// The sections in the channel.
    ///
    /// There should be no more than 2^16 sections.
    sections: []Section = &.{},
};

pub const Section = struct {
    first_tick: u64,
    last_tick: u64,
    pat_i: u16,
};

pub const Pattern = struct {
    /// The notes in the channel.
    ///
    /// There should be no more than 2^16 notes.
    notes: []Note = &.{},
};

pub const Note = struct {
    first_tick: u16,
    last_tick: u16,
    pitch: u7,
    volume: u8 = 0xff,
};

pub const Instrument = struct {
    base: Base,

    pub const Base = union(enum) {
        /// A pulse chip with a variable duty cycle.
        chip_pulse: f32,
        /// A triangle chip.
        chip_triangle,
        /// A sine chip.
        chip_sine,
    };
};
