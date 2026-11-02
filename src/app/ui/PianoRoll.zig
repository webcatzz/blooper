const Ctx = @import("../Ctx.zig");
const input = @import("../core/input.zig");
const math = @import("../core/math.zig");
const render = @import("../core/render.zig");
const std = @import("std");
const Track = @import("../../synth/Track.zig");

const PianoRoll = @This();

scroll: math.Vec2(f32) = .zero,
/// The current user selection.
sel: Selection = .none,
/// The index of the current pattern.
pat_i: ?u16 = null,

const tick_width = 0.25;
const pitch_height = 6;
const note_edge_width = 4;

/// "Floating" coordinates in the pattern.
const Coords = struct { tick: u16, pitch: u8 };

/// A target of a cursor.
const Target = union(enum) {
    none: Coords,
    note: u16,
    note_start: u16,
    note_end: u16,
};

/// A user selection.
const Selection = union(enum) {
    none,
    note: u16,
    note_start: u16,
    note_end: u16,
};

pub fn respond(self: *PianoRoll, ctx: *Ctx, rect: math.Rect(f32), comptime event_type: input.event.Type, event: input.event.of(event_type)) !void {
    switch (event_type) {
        .button => {
            const pat_i = self.pat_i orelse return;

            if (ctx.input.wasJustActivated(.accept))
                switch (self.pick(ctx.edit.track.patterns[pat_i], ctx.input.cursor_pos, rect.pos())) {
                    .none => |target| {
                        const note_i = try ctx.edit.insertNote(pat_i, .{
                            .first_tick = target.tick,
                            .last_tick = target.tick + 64,
                            .pitch = target.pitch,
                        });
                        self.sel = .{ .note_end = note_i };
                    },

                    .note => |target| self.sel = .{ .note = target },
                    .note_start => |target| self.sel = .{ .note_start = target },
                    .note_end => |target| self.sel = .{ .note_end = target },
                }
            else if (ctx.input.wasJustActivated(.remove))
                switch (self.sel) {
                    .none => {},

                    .note, .note_start, .note_end => |note_i| {
                        ctx.edit.removeNote(pat_i, note_i);
                        self.sel = .none;
                    },
                };
        },

        .cursor => {
            const pat_i = self.pat_i orelse return;

            if (ctx.input.isActive(.accept))
                switch (self.sel) {
                    .note => |note_i| {
                        const note = &ctx.edit.track.patterns[pat_i].notes[note_i];
                        if (ctx.input.cursor_motion.x < 0) {
                            const tick_offset = @min(note.first_tick, @as(u16, @intFromFloat(-ctx.input.cursor_motion.x / tick_width)));
                            note.first_tick -= tick_offset;
                            note.last_tick -= tick_offset;
                        } else {
                            const tick_offset: u16 = @intFromFloat(ctx.input.cursor_motion.x / tick_width);
                            note.first_tick += tick_offset;
                            note.last_tick += tick_offset;
                        }
                    },

                    .note_start => |note_i| {
                        const note = &ctx.edit.track.patterns[pat_i].notes[note_i];
                        note.first_tick = @min(note.last_tick, @as(u16, @trunc((ctx.input.cursor_pos.x - self.scroll.x) / tick_width)));
                    },

                    .note_end => |note_i| {
                        const note = &ctx.edit.track.patterns[pat_i].notes[note_i];
                        note.last_tick = @max(note.first_tick, @as(u16, @trunc((ctx.input.cursor_pos.x - self.scroll.x) / tick_width)));
                    },

                    else => {},
                };
        },

        .scroll => {
            self.scroll.x = @min(self.scroll.x + event.amount.x, 0);
            self.scroll.y = @min(self.scroll.y + event.amount.y, 0);
        },
    }
}

pub fn draw(self: PianoRoll, ctx: Ctx, rect: math.Rect(f32), queue: *render.Queue) !void {
    try queue.drawSprite9Patch(.sect_red, rect);

    const pat_i = self.pat_i orelse return;

    try queue.clip(rect);

    for (ctx.edit.track.patterns[pat_i].notes) |note| {
        const pos = self.project(note.first_tick, note.pitch, rect.pos());
        try queue.drawSprite9Patch(.note_red, .{
            .x = pos.x,
            .y = pos.y,
            .w = @as(f32, note.last_tick - note.first_tick) * tick_width,
            .h = pitch_height,
        });
    }

    switch (self.sel) {
        .none => {},

        .note, .note_start, .note_end => |note_i| {
            const note = ctx.edit.track.patterns[pat_i].notes[note_i];
            const pos = self.project(note.first_tick, note.pitch, rect.pos());
            try queue.drawSprite9Patch(.outline, .{
                .x = pos.x - 2,
                .y = pos.y - 2,
                .w = @as(f32, note.last_tick - note.first_tick) * tick_width + 4,
                .h = pitch_height + 4,
            });
        },
    }

    try queue.unclip();
}

/// Returns the cursor target at the given position.
fn pick(self: PianoRoll, pat: Track.Pattern, pos: math.Vec2(f32), off: math.Vec2(f32)) Target {
    const tick: u16 = @intFromFloat((pos.x - off.x - self.scroll.x) / tick_width);
    const pitch: u8 = @intFromFloat((pos.y - off.y - self.scroll.y) / pitch_height);

    for (pat.notes, 0..) |note, note_i|
        if (note.first_tick <= tick and note.last_tick >= tick and note.pitch == pitch)
            return if (tick - note.first_tick < note_edge_width)
                .{ .note_start = @intCast(note_i) }
            else if (note.last_tick - tick < note_edge_width)
                .{ .note_end = @intCast(note_i) }
            else
                .{ .note = @intCast(note_i) };

    return .{ .none = .{ .tick = tick, .pitch = pitch } };
}

/// Returns the position corresponding to the given tick and pitch.
fn project(self: PianoRoll, tick: u16, pitch: u8, off: math.Vec2(f32)) math.Vec2(f32) {
    return .{
        .x = @as(f32, @floatFromInt(tick)) * tick_width + self.scroll.x + off.x,
        .y = @as(f32, @floatFromInt(pitch)) * pitch_height + self.scroll.y + off.y,
    };
}
