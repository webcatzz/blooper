/// The playback rate, in ticks-per-second.
tempo: u16 = 450,
channels: []Channel = &.{},
patterns: []Pattern = &.{},

pub const Channel = struct {
    instrument: Instrument,
    sections: []Section = &.{},
};

pub const Section = struct {
    first_tick: u64,
    last_tick: u64,
    pat_i: u16,
};

pub const Pattern = struct {
    notes: []Note = &.{},
};

pub const Note = struct {
    first_tick: u16,
    last_tick: u16,
    pitch: u8,
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
