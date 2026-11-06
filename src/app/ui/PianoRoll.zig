const Ctx = @import("../Ctx.zig");
const input = @import("../core/input.zig");
const math = @import("../core/math.zig");
const pitch_util = @import("../../synth/pitch.zig");
const render = @import("../core/render.zig");
const std = @import("std");
const Track = @import("../../synth/Track.zig");

const PianoRoll = @This();

scroll: math.Vec2(f32) = .{ .x = 0, .y = -pitch_util.c4 * pitch_height },
/// The current user selection.
sel: Selection = .none,
/// The index of the current pattern.
pat_i: ?u16 = null,

const tick_width = 0.25;
const pitch_height = 6;
const note_edge_width = 2;

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

pub fn respond(self: *PianoRoll, ctx: *Ctx, pos: math.Vec2(f32), comptime event_type: input.event.Type, event: input.event.of(event_type)) !void {
    switch (event_type) {
        .button => {
            const pat_i = self.pat_i orelse return;

            if (ctx.input.wasJustActivated(.accept))
                switch (self.pick(ctx.edit.track.patterns[pat_i], ctx.input.cursor_pos, pos)) {
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
                        note.first_tick = @min(note.last_tick, self.tickFromX(ctx.input.cursor_pos.x, pos.x));
                    },

                    .note_end => |note_i| {
                        const note = &ctx.edit.track.patterns[pat_i].notes[note_i];
                        note.last_tick = @max(note.first_tick, self.tickFromX(ctx.input.cursor_pos.x, pos.x));
                    },

                    else => {},
                };
        },

        .scroll => {
            self.scroll.x = @max(self.scroll.x - event.amount.x, 0);
            self.scroll.y = @min(self.scroll.y - event.amount.y, 0);
        },

        else => {},
    }
}

pub fn draw(self: PianoRoll, ctx: Ctx, rect: math.Rect(f32), queue: *render.Queue) !void {
    const pat_i = self.pat_i orelse return;

    try queue.clip(rect);

    if (rect.contains(ctx.input.cursor_pos)) {
        const pitch = self.pitchFromY(ctx.input.cursor_pos.y, rect.y);
        var name_buf: [4]u8 = undefined;
        try queue.drawText(
            pitch_util.name(pitch, &name_buf),
            .{ .x = rect.x, .y = self.yFromPitch(pitch, rect.y) },
        );
    }

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

pub fn totalSize(_: Ctx) math.Vec2(f32) {
    return .{
        .x = @as(f32, std.math.maxInt(u16)) * tick_width,
        .y = @as(f32, std.math.maxInt(u8)) * pitch_height,
    };
}

/// Returns the cursor target at the given position.
fn pick(self: PianoRoll, pat: Track.Pattern, pos: math.Vec2(f32), off: math.Vec2(f32)) Target {
    const tick = self.tickFromX(pos.x, off.x);
    const pitch = self.pitchFromY(pos.y, off.y);

    for (pat.notes, 0..) |note, note_i|
        if (note.first_tick <= tick and note.last_tick >= tick and note.pitch == pitch)
            return if (tick - note.first_tick < note_edge_width / tick_width)
                .{ .note_start = @intCast(note_i) }
            else if (note.last_tick - tick < note_edge_width / tick_width)
                .{ .note_end = @intCast(note_i) }
            else
                .{ .note = @intCast(note_i) };

    return .{ .none = .{ .tick = tick, .pitch = pitch } };
}

/// Returns the position corresponding to the given tick and pitch.
fn project(self: PianoRoll, tick: u16, pitch: u8, off: math.Vec2(f32)) math.Vec2(f32) {
    return .{
        .x = self.xFromTick(tick, off.x),
        .y = self.yFromPitch(pitch, off.y),
    };
}

fn tickFromX(self: PianoRoll, x: f32, rect_x: f32) u16 {
    return @trunc(@max(x - rect_x + self.scroll.x, 0) / tick_width);
}

fn xFromTick(self: PianoRoll, tick: u16, rect_x: f32) f32 {
    return rect_x - self.scroll.x + @as(f32, tick) * tick_width;
}

fn pitchFromY(self: PianoRoll, y: f32, rect_y: f32) u8 {
    return @as(u8, @trunc(@max(-y + rect_y - self.scroll.y, 0) / pitch_height)) + 1;
}

fn yFromPitch(self: PianoRoll, pitch: u8, rect_y: f32) f32 {
    return rect_y - self.scroll.y - @as(f32, pitch) * pitch_height;
}
