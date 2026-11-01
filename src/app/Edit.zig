//! An editable track.

const std = @import("std");
const Track = @import("../synth/Track.zig");

const Edit = @This();

/// The track data.
///
/// Backed by allocated buffers.
track: Track,

/// The capacity of the backing buffer used to store channels.
chan_cap: usize = 0,
/// The capacities of the backing buffers used to store sections.
///
/// Of length `chan_cap`.
sect_caps: []usize = &.{},
/// The capacity of the backing buffer used to store patterns.
pat_cap: usize = 0,
/// The capacities of the backing buffers used to store notes.
///
/// Of length `pat_cap`.
note_caps: []usize = &.{},

/// A stack of changes that undo recent changes.
undo_stack: std.ArrayList(Change),
/// A stack of changes that redo recently undone changes.
redo_stack: std.ArrayList(Change),

/// The allocator used by the edit.
gpa: std.mem.Allocator,

/// A discrete change in a track.
pub const Change = union(enum) {
    insert_chan: struct { chan_i: u16, chan: Track.Channel },
    remove_chan: struct { chan_i: u16 },

    insert_sect: struct { chan_i: u16, sect: Track.Section },
    remove_sect: struct { chan_i: u16, sect_i: u16 },

    insert_pat: struct { pat_i: u16, pat: Track.Pattern },
    remove_pat: struct { pat_i: u16 },

    insert_note: struct { pat_i: u16, note: Track.Note },
    remove_note: struct { pat_i: u16, note_i: u16 },
    set_note_first_tick: struct { pat_i: u16, note_i: u16, first_tick: u16 },
    set_note_last_tick: struct { pat_i: u16, note_i: u16, last_tick: u16 },
    set_note_pitch: struct { pat_i: u16, note_i: u16, pitch: u8 },
    set_note_volume: struct { pat_i: u16, note_i: u16, volume: u4 },
};

/// Options for inserting a channel.
const ChannelOptions = struct {
    instrument: Track.Instrument,
};

/// Returns a new edit.
///
/// The edit is owned by the caller and should be freed by calling `deinit`.
pub fn init(gpa: std.mem.Allocator) !Edit {
    var undo_stack: std.ArrayList(Change) = try .initCapacity(gpa, 32);
    errdefer undo_stack.deinit(gpa);

    var redo_stack: std.ArrayList(Change) = try .initCapacity(gpa, 32);
    errdefer redo_stack.deinit(gpa);

    return .{
        .track = .{
            .tempo = 450,
        },
        .undo_stack = undo_stack,
        .redo_stack = redo_stack,
        .gpa = gpa,
    };
}

/// Frees the edit.
///
/// The edit should not be used after calling this function.
pub fn deinit(self: *Edit) void {
    const chan_buf = self.track.channels.ptr[0..self.chan_cap];
    for (chan_buf, self.sect_caps) |chan, sect_cap|
        self.gpa.free(chan.sections.ptr[0..sect_cap]);
    self.gpa.free(chan_buf);
    self.gpa.free(self.sect_caps);
    const pat_buf = self.track.patterns.ptr[0..self.pat_cap];
    for (pat_buf, self.note_caps) |pat, note_cap|
        self.gpa.free(pat.notes.ptr[0..note_cap]);
    self.gpa.free(pat_buf);
    self.gpa.free(self.note_caps);

    self.undo_stack.deinit(self.gpa);
    self.redo_stack.deinit(self.gpa);

    self.* = undefined;
}

/// Inserts an empty channel at the given index.
pub fn insertChannel(self: *Edit, chan_i: u16, opts: ChannelOptions) !void {
    if (self.track.channels.len >= std.math.maxInt(u16) - 1) {
        @branchHint(.cold);
        return error.IndexOverflow;
    }

    if (self.track.channels.len >= self.chan_cap) {
        const old_cap = self.chan_cap;

        const chan_buf: []Track.Channel = try self.gpa.realloc(
            self.track.channels.ptr[0..self.chan_cap],
            std.ArrayList(Track.Channel).growCapacity(old_cap + 1),
        );
        self.track.channels.ptr = chan_buf.ptr;
        self.chan_cap = chan_buf.len;

        self.sect_caps = try self.gpa.realloc(self.sect_caps, chan_buf.len);
        @memset(self.sect_caps[old_cap..], 0);
    }

    self.track.channels.len += 1;
    sliceInsert(Track.Channel, self.track.channels, chan_i, .{
        .instrument = opts.instrument,
        .sections = &.{},
    });
}

/// Inserts the given section into the channel with the given index. Returns the
/// new index of the section.
pub fn insertSection(self: *Edit, chan_i: u16, sect: Track.Section) !u16 {
    if (self.track.channels[chan_i].sections.len >= std.math.maxInt(u16) - 1) {
        @branchHint(.cold);
        return error.IndexOverflow;
    }

    if (self.track.channels[chan_i].sections.len >= self.sect_caps[chan_i]) {
        const old_cap = self.sect_caps[chan_i];

        const sect_buf: []Track.Section = try self.gpa.realloc(
            self.track.channels[chan_i].sections.ptr[0..old_cap],
            std.ArrayList(Track.Section).growCapacity(old_cap + 1),
        );
        self.track.channels[chan_i].sections.ptr = sect_buf.ptr;
        self.sect_caps[chan_i] = sect_buf.len;
    }

    const idx: u16 = @truncate(self.track.channels[chan_i].sections.len);
    self.track.channels[chan_i].sections.len += 1;
    self.track.channels[chan_i].sections[idx] = sect;
    return idx;
}

/// Removes the section with the given index from the channel with the given
/// index.
pub fn removeSection(self: *Edit, chan_i: u16, sect_i: u16) void {
    const sects = &self.track.channels[chan_i].sections;
    @memmove(sects.*[sect_i .. sects.len - 1], sects.*[sect_i + 1 ..]);
    sects.len -= 1;
}

/// Inserts an empty pattern. Returns the new index of the pattern.
pub fn insertPattern(self: *Edit) !u16 {
    if (self.track.patterns.len >= std.math.maxInt(u16) - 1) {
        @branchHint(.cold);
        return error.IndexOverflow;
    }

    if (self.track.patterns.len >= self.pat_cap) {
        const old_cap = self.pat_cap;

        const pat_buf = try self.gpa.realloc(
            self.track.patterns.ptr[0..old_cap],
            std.ArrayList(Track.Channel).growCapacity(old_cap + 1),
        );
        self.track.patterns.ptr = pat_buf.ptr;
        self.pat_cap = pat_buf.len;

        self.note_caps = try self.gpa.realloc(self.note_caps, pat_buf.len);
        @memset(self.note_caps[old_cap..], 0);
    }

    const idx: u16 = @intCast(self.track.patterns.len);
    self.track.patterns.len += 1;
    sliceInsert(Track.Pattern, self.track.patterns, idx, .{});
    return idx;
}

pub fn undo(self: *Edit) bool {
    _ = self;
}

pub fn redo(self: *Edit) bool {
    _ = self;
}

/// Inserts `value` into `slice` at the given index, overwriting the last
/// element of `slice`.
fn sliceInsert(comptime T: type, slice: []T, index: usize, value: T) void {
    @memmove(slice[index + 1 ..], slice[index .. slice.len - 1]);
    slice[index] = value;
}
