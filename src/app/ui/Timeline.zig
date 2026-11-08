//! Allows editing a track's channels and sections.

const Ctx = @import("../Ctx.zig");
const math = @import("../core/math.zig");
const Track = @import("../../synth/Track.zig");
const Ui = @import("../Ui.zig");

const Timeline = @This();

/// The current scroll amount.
scroll: math.Vec2(f32) = .zero,
/// The current user selection.
sel: Selection = .none,

/// The width used to represent a tick, in pixels.
const tick_width = 0.5;
/// The height used to represent a channel, in pixels.
const chan_height = 32;
/// The maximum distance from the horizontal edges of a section that, when
/// receiving input, will begin resizing the section rather than moving it.
const sect_edge_width = 2;

/// A position in a channel.
const ChannelPos = struct { chan_i: u16, tick: u64 };
/// Coordinates of a section.
const SectionCoords = struct { chan_i: u16, sect_i: u16 };

/// A target of a cursor.
const Target = union(enum) {
    none,
    chan: ChannelPos,
    sect: SectionCoords,
    sect_start: SectionCoords,
    sect_end: SectionCoords,
};

/// A user selection.
const Selection = union(enum) {
    none,
    sect: SectionCoords,
    sect_start: SectionCoords,
    sect_end: SectionCoords,
};

/// Draws the timeline.
pub fn draw(self: *const Timeline, ctx: Ctx, ui: *Ui) !void {
    ui.split(.y, Ui.icon_button_h);

    try ui.addIconButton(if (ctx.is_playing) .button_icon_stop else .button_icon_play, .wrap(respondPlayButton));

    ui.next();

    try ui.addScrollbar(.y, @trunc(self.scroll.y), @max(ui.rect.y, fullH(ctx.edit.track)), .wrapCtx(@constCast(self), respondVScrollbar));
    try ui.addScrollbar(.x, @trunc(self.scroll.x), @max(ui.rect.x, fullW(ctx.edit.track), @as(i32, @trunc(self.scroll.x))), .wrapCtx(@constCast(self), respondHScrollbar));

    try ui.inset();
    try ui.clip(ui.rect);
    try ui.flag(ui.rect, .wrapCtx(@constCast(self), respond));

    const min_chan_i: u16 = @trunc(self.scroll.y / chan_height);
    const max_chan_i = @min(min_chan_i + @as(u16, @intCast(@divTrunc(ui.rect.h, chan_height))) + 1, ctx.edit.track.channels.len);

    for (ctx.edit.track.channels[min_chan_i..max_chan_i], min_chan_i..) |chan, chan_i| {
        for (chan.sections) |sect| {
            const x = self.xFromTick(sect.first_tick, ui.rect.x);
            const y = self.yFromChannel(@intCast(chan_i), ui.rect.y);
            const sect_w = widthFromTicks(sect.last_tick - sect.first_tick);

            try ui.queue.drawSprite9Patch(.sect_red, .{
                .x = x,
                .y = y,
                .w = sect_w,
                .h = chan_height,
            });

            const notes = ctx.edit.track.patterns[sect.pat_i].notes;
            if (notes.len == 0) continue;

            var min_pitch = notes[0].pitch;
            var max_pitch = min_pitch;
            for (notes[1..]) |note| {
                min_pitch = @min(min_pitch, note.pitch);
                max_pitch = @max(max_pitch, note.pitch);
            }

            const inner_y = y + 3;
            const inner_h = chan_height - 6;
            const pitch_height = inner_h / @as(f32, max_pitch - min_pitch + 1);

            try ui.clip(.{
                .x = x,
                .y = inner_y,
                .w = sect_w,
                .h = inner_h,
            });

            for (notes) |note|
                if (note.first_tick <= sect.last_tick - sect.first_tick)
                    try ui.queue.drawSprite9Patch(.sect_note_red, .{
                        .x = x + widthFromTicks(note.first_tick),
                        .y = inner_y + @as(i32, @trunc((max_pitch - note.pitch) * pitch_height)),
                        .w = widthFromTicks(note.last_tick - note.first_tick),
                        .h = @trunc(pitch_height),
                    });

            try ui.unclip();
        }
    }

    switch (self.sel) {
        .none => {},

        .sect, .sect_start, .sect_end => |coords| {
            const sect = ctx.edit.track.channels[coords.chan_i].sections[coords.sect_i];
            try ui.queue.drawSprite9Patch(.outline, .{
                .x = self.xFromTick(sect.first_tick, ui.rect.x) - 2,
                .y = self.yFromChannel(coords.chan_i, ui.rect.y) - 2,
                .w = widthFromTicks(sect.last_tick - sect.first_tick) + 4,
                .h = chan_height + 4,
            });
        },
    }

    if (ctx.is_playing)
        try ui.queue.drawSpriteStretch(.playhead, .{
            .x = self.xFromTick(ctx.synth.tick, ui.rect.x),
            .y = ui.rect.y,
            .w = 3,
            .h = ui.rect.h,
        });

    try ui.unclip();
}

/// Called when the timeline receives input.
pub fn respond(self: *Timeline, ctx: *Ctx, rect: math.Rect(i32)) !void {
    switch (ctx.input.last_event) {
        .button => {
            if (ctx.input.wasJustActivated(.accept))
                switch (self.pick(ctx.edit.track, ctx.input.cur_pos, rect.pos())) {
                    .none => self.sel = .none,

                    .chan => |chan_pos| {
                        const sect_i = try ctx.edit.insertSection(chan_pos.chan_i, .{
                            .first_tick = chan_pos.tick,
                            .last_tick = chan_pos.tick + 64,
                            .pat_i = 0,
                        });
                        self.sel = .{ .sect_end = .{ .chan_i = chan_pos.chan_i, .sect_i = sect_i } };
                    },

                    .sect => |sect_coords| self.sel = .{ .sect = sect_coords },
                    .sect_start => |sect_coords| self.sel = .{ .sect_start = sect_coords },
                    .sect_end => |sect_coords| self.sel = .{ .sect_end = sect_coords },
                }
            else if (ctx.input.wasJustActivated(.remove))
                switch (self.sel) {
                    .sect, .sect_start, .sect_end => |sect_coords| {
                        ctx.edit.removeSection(sect_coords.chan_i, sect_coords.sect_i);
                        self.sel = .none;
                    },

                    else => {},
                };
        },

        .cursor => {
            if (ctx.input.isActive(.accept))
                switch (self.sel) {
                    .sect => |sect_coords| {
                        const sect = &ctx.edit.track.channels[sect_coords.chan_i].sections[sect_coords.sect_i];
                        if (ctx.input.cur_motion.x < 0) {
                            const tick_offset = @min(sect.first_tick, ticksFromWidth(ctx.input.cur_motion.x));
                            sect.first_tick -= tick_offset;
                            sect.last_tick -= tick_offset;
                        } else {
                            const tick_offset = ticksFromWidth(ctx.input.cur_motion.x);
                            sect.first_tick += tick_offset;
                            sect.last_tick += tick_offset;
                        }
                    },

                    .sect_start => |sect_coords| {
                        const sect = &ctx.edit.track.channels[sect_coords.chan_i].sections[sect_coords.sect_i];
                        sect.first_tick = @min(sect.last_tick, self.tickFromX(ctx.input.cur_pos.x, rect.x));
                    },

                    .sect_end => |sect_coords| {
                        const sect = &ctx.edit.track.channels[sect_coords.chan_i].sections[sect_coords.sect_i];
                        sect.last_tick = @max(sect.first_tick, self.tickFromX(ctx.input.cur_pos.x, rect.x));
                    },

                    else => {},
                };
        },

        .scroll => |event| {
            self.scroll.x = @max(0, self.scroll.x - event.amount.x);
            self.scroll.y = @max(0, @min(@as(f32, @floatFromInt(fullH(ctx.edit.track))), self.scroll.y - event.amount.y));
        },

        else => {},
    }
}

/// Called when the vertical scrollbar receives input.
fn respondVScrollbar(self: *Timeline, ctx: *Ctx, rect: math.Rect(i32)) !void {
    if (ctx.input.isActive(.accept))
        self.scroll.y = @floatFromInt(@divTrunc((ctx.input.cur_pos.y - rect.y) * fullH(ctx.edit.track), rect.h));
}

/// Called when the horizontal scrollbar receives input.
fn respondHScrollbar(self: *Timeline, ctx: *Ctx, rect: math.Rect(i32)) !void {
    if (ctx.input.isActive(.accept))
        self.scroll.x = @as(f32, @floatFromInt(@divTrunc((ctx.input.cur_pos.x - rect.x) * fullW(ctx.edit.track), rect.w)));
}

/// Called when the play button receives input.
fn respondPlayButton(_: *void, ctx: *Ctx, _: math.Rect(i32)) !void {
    if (ctx.input.wasJustActivated(.accept)) {
        ctx.is_playing = !ctx.is_playing;
        ctx.synth.seek(0);
    }
}

/// Returns the full width of a timeline displaying the given track.
fn fullW(track: Track) i32 {
    var last_tick: u64 = 0;
    for (track.channels) |chan| {
        for (chan.sections) |sect|
            last_tick = @max(last_tick, sect.last_tick);
    }

    return @trunc(@as(f32, @floatFromInt(last_tick)) * tick_width);
}

/// Returns the full height of a timeline displaying the given track.
fn fullH(track: Track) i32 {
    return @as(i32, @intCast(track.channels.len)) * chan_height;
}

/// Returns the cursor target at the given position.
fn pick(self: Timeline, track: Track, pos: math.Vec2(i32), off: math.Vec2(i32)) Target {
    const tick = self.tickFromX(pos.x, off.x);
    const chan_i = self.channelFromY(pos.y, off.y);

    if (chan_i >= track.channels.len)
        return .none;

    const chan = track.channels[chan_i];

    for (chan.sections, 0..) |sect, sect_i|
        if (sect.first_tick <= tick and sect.last_tick >= tick)
            return if (tick - sect.first_tick < sect_edge_width / tick_width)
                .{ .sect_start = .{ .chan_i = chan_i, .sect_i = @intCast(sect_i) } }
            else if (sect.last_tick - tick < sect_edge_width / tick_width)
                .{ .sect_end = .{ .chan_i = chan_i, .sect_i = @intCast(sect_i) } }
            else
                .{ .sect = .{ .chan_i = chan_i, .sect_i = @intCast(sect_i) } };

    return .{ .chan = .{ .chan_i = chan_i, .tick = tick } };
}

/// Converts the given width to a duration in ticks.
///
/// Negative widths are converted to their absolute value.
fn ticksFromWidth(w: i32) u64 {
    return @trunc(@as(f32, @floatFromInt(@abs(w))) / tick_width);
}

/// Converts the given duration to a width.
fn widthFromTicks(ticks: u64) i32 {
    return @trunc(@as(f32, @floatFromInt(ticks)) * tick_width);
}

/// Returns the tick at the given x-coordinate.
fn tickFromX(self: Timeline, x: i32, rect_x: i32) u64 {
    return ticksFromWidth(x - rect_x + @as(i32, @trunc(self.scroll.x)));
}

/// Returns the x-coordinate of the given tick.
fn xFromTick(self: Timeline, tick: u64, rect_x: i32) i32 {
    return rect_x - @as(i32, @trunc(self.scroll.x)) + widthFromTicks(tick);
}

/// Returns the pitch at the given y-coordinate.
fn channelFromY(self: Timeline, y: i32, rect_y: i32) u16 {
    return @truncate(@max(y - rect_y + @as(i32, @trunc(self.scroll.y)), 0) / chan_height);
}

/// Returns the y-coordinate of the given pitch.
fn yFromChannel(self: Timeline, chan_i: u16, rect_y: i32) i32 {
    return rect_y - @as(i32, @trunc(self.scroll.y)) + @as(i32, chan_i) * chan_height;
}
