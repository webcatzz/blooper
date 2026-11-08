//! Allows editing a pattern in a track.

const Ctx = @import("../Ctx.zig");
const math = @import("../core/math.zig");
const pitch_util = @import("../../synth/pitch.zig");
const std = @import("std");
const Track = @import("../../synth/Track.zig");
const Ui = @import("../Ui.zig");

const PianoRoll = @This();

/// The current scroll amount.
scroll: math.Vec2(f32) = .{ .x = 0, .y = pitch_util.c4 * pitch_height },
/// The current user selection.
sel: Selection = .none,
/// The index of the current pattern.
pat_i: ?u16 = null,

/// The width used to represent a tick, in pixels.
const tick_width = 1;
/// The height used to represent a pitch, in pixels.
const pitch_height = 6;
/// The minimum pitch permitted by the piano roll.
const min_pitch = 0;
/// The maximum pitch permitted by the piano roll.
const max_pitch = std.math.maxInt(u7);
/// The maximum distance from the horizontal edges of a note that, when
/// receiving input, will begin resizing the note rather than moving it.
const note_edge_width = 2;
/// The full height of the piano roll.
const full_h = max_pitch * pitch_height;

/// "Floating" coordinates in the pattern.
const Coords = struct { tick: u16, pitch: u7 };

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

/// Draws the piano roll.
pub fn draw(self: *const PianoRoll, ctx: Ctx, ui: *Ui) !void {
    const pat_i = self.pat_i orelse {
        try ui.inset();
        return;
    };

    try ui.addScrollbar(.y, @trunc(self.scroll.y), @max(ui.rect.y, full_h), .wrapCtx(@constCast(self), respondVScrollbar));
    try ui.addScrollbar(.x, @trunc(self.scroll.x), @max(ui.rect.x, fullW(ctx.edit.track.patterns[pat_i]), @as(i32, @trunc(self.scroll.x))), .wrapCtx(@constCast(self), respondHScrollbar));

    try ui.inset();
    try ui.clip(ui.rect);
    try ui.flag(ui.rect, .wrapCtx(@constCast(self), respond));

    if (ui.rect.contains(ctx.input.cur_pos)) {
        const pitch = self.pitchFromY(ctx.input.cur_pos.y, ui.rect.y);
        const pitch_y = self.yFromPitch(pitch, ui.rect.y);

        try ui.queue.drawSpriteStretch(.pitch_highlight, .{
            .x = ui.rect.x,
            .y = pitch_y,
            .w = ui.rect.w,
            .h = pitch_height,
        });

        var name_buf: [4]u8 = undefined;
        try ui.queue.drawText(
            pitch_util.name(pitch, &name_buf),
            .{ .x = ui.rect.x, .y = pitch_y },
        );
    }

    for (ctx.edit.track.patterns[pat_i].notes) |note|
        try ui.queue.drawSprite9Patch(.note_red, .{
            .x = self.xFromTick(note.first_tick, ui.rect.x),
            .y = self.yFromPitch(note.pitch, ui.rect.y),
            .w = widthFromTicks(note.last_tick - note.first_tick),
            .h = pitch_height,
        });

    switch (self.sel) {
        .none => {},

        .note, .note_start, .note_end => |note_i| {
            const note = ctx.edit.track.patterns[pat_i].notes[note_i];
            try ui.queue.drawSprite9Patch(.outline, .{
                .x = self.xFromTick(note.first_tick, ui.rect.x) - 2,
                .y = self.yFromPitch(note.pitch, ui.rect.y) - 2,
                .w = widthFromTicks(note.last_tick - note.first_tick) + 4,
                .h = pitch_height + 4,
            });
        },
    }

    try ui.unclip();
}

fn respond(self: *PianoRoll, ctx: *Ctx, rect: math.Rect(i32)) !void {
    const pat_i = self.pat_i orelse return;

    switch (ctx.input.last_event) {
        .button => {
            if (ctx.input.wasJustActivated(.accept))
                switch (self.pick(ctx.edit.track.patterns[pat_i], ctx.input.cur_pos, rect.pos())) {
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
            if (ctx.input.isActive(.accept))
                switch (self.sel) {
                    .note => |note_i| {
                        const note = &ctx.edit.track.patterns[pat_i].notes[note_i];
                        if (ctx.input.cur_motion.x < 0) {
                            const tick_offset = @min(note.first_tick, ticksFromWidth(ctx.input.cur_motion.x));
                            note.first_tick -= tick_offset;
                            note.last_tick -= tick_offset;
                        } else {
                            const tick_offset = ticksFromWidth(ctx.input.cur_motion.x);
                            note.first_tick += tick_offset;
                            note.last_tick += tick_offset;
                        }
                    },

                    .note_start => |note_i| {
                        const note = &ctx.edit.track.patterns[pat_i].notes[note_i];
                        note.first_tick = @min(note.last_tick, self.tickFromX(ctx.input.cur_pos.x, rect.x));
                    },

                    .note_end => |note_i| {
                        const note = &ctx.edit.track.patterns[pat_i].notes[note_i];
                        note.last_tick = @max(note.first_tick, self.tickFromX(ctx.input.cur_pos.x, rect.x));
                    },

                    else => {},
                };
        },

        .scroll => |event| {
            self.scroll.x = @max(0, self.scroll.x - event.amount.x);
            self.scroll.y = @max(0, @min(full_h, self.scroll.y - event.amount.y));
        },

        else => {},
    }
}

fn respondVScrollbar(self: *PianoRoll, ctx: *Ctx, rect: math.Rect(i32)) !void {
    if (ctx.input.isActive(.accept))
        self.scroll.y = @floatFromInt(@divTrunc((ctx.input.cur_pos.y - rect.y) * full_h, rect.h));
}

fn respondHScrollbar(self: *PianoRoll, ctx: *Ctx, rect: math.Rect(i32)) !void {
    if (ctx.input.isActive(.accept)) {
        if (self.pat_i) |pat_i|
            self.scroll.x = @floatFromInt(@divTrunc((ctx.input.cur_pos.x - rect.x) * fullW(ctx.edit.track.patterns[pat_i]), rect.w));
    }
}

/// Returns the full width of a piano roll displaying the given pattern.
fn fullW(pattern: Track.Pattern) i32 {
    var last_tick: u64 = 0;
    for (pattern.notes) |note|
        last_tick = @max(last_tick, note.last_tick);

    return @trunc(@as(f32, @floatFromInt(last_tick)) * tick_width);
}

/// Returns the cursor target at the given position.
fn pick(self: PianoRoll, pat: Track.Pattern, pos: math.Vec2(i32), off: math.Vec2(i32)) Target {
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

/// Converts the given width to a duration in ticks.
///
/// Widths are converted to their absolute value.
fn ticksFromWidth(w: i32) u16 {
    return @trunc(@as(f32, @floatFromInt(@abs(w))) / tick_width);
}

/// Converts the given duration to a width.
fn widthFromTicks(ticks: u16) i32 {
    return @trunc(@as(f32, ticks) * tick_width);
}

/// Returns the tick at the given x-coordinate.
fn tickFromX(self: PianoRoll, x: i32, rect_x: i32) u16 {
    return ticksFromWidth(x - rect_x + @as(i32, @trunc(self.scroll.x)));
}

/// Returns the x-coordinate of the given tick.
fn xFromTick(self: PianoRoll, tick: u16, rect_x: i32) i32 {
    return rect_x - @as(i32, @trunc(self.scroll.x)) + @as(i32, @trunc(@as(f32, tick) * tick_width));
}

/// Returns the pitch at the given y-coordinate.
fn pitchFromY(self: PianoRoll, y: i32, rect_y: i32) u7 {
    return @intCast(max_pitch -| @max(min_pitch, (y - rect_y + @as(i32, @trunc(self.scroll.y)))) / pitch_height);
}

/// Returns the y-coordinate of the given pitch.
fn yFromPitch(self: PianoRoll, pitch: u7, rect_y: i32) i32 {
    return rect_y - @as(i32, @trunc(self.scroll.y)) + @as(i32, max_pitch - pitch) * pitch_height;
}
