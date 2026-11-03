const Ctx = @import("../Ctx.zig");
const input = @import("../core/input.zig");
const math = @import("../core/math.zig");
const render = @import("../core/render.zig");
const std = @import("std");
const Track = @import("../../synth/Track.zig");

const Timeline = @This();

scroll: math.Vec2(f32) = .zero,
/// The current user selection.
sel: Selection = .none,

const tick_width = 0.25;
const chan_height = 32;
const sect_edge_width = 4;

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

pub fn respond(self: *Timeline, ctx: *Ctx, rect: math.Rect(f32), comptime event_type: input.event.Type, event: input.event.of(event_type)) !void {
    switch (event_type) {
        .button => {
            if (ctx.input.wasJustActivated(.accept))
                switch (self.pick(ctx.edit.track, ctx.input.cursor_pos, rect.pos())) {
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
                        if (ctx.input.cursor_motion.x < 0) {
                            const tick_offset = @min(sect.first_tick, @as(u64, @intFromFloat(-ctx.input.cursor_motion.x / tick_width)));
                            sect.first_tick -= tick_offset;
                            sect.last_tick -= tick_offset;
                        } else {
                            const tick_offset: u64 = @intFromFloat(ctx.input.cursor_motion.x / tick_width);
                            sect.first_tick += tick_offset;
                            sect.last_tick += tick_offset;
                        }
                    },

                    .sect_start => |sect_coords| {
                        const sect = &ctx.edit.track.channels[sect_coords.chan_i].sections[sect_coords.sect_i];
                        sect.first_tick = @min(sect.last_tick, @as(u64, @trunc((ctx.input.cursor_pos.x + self.scroll.x) / tick_width)));
                    },

                    .sect_end => |sect_coords| {
                        const sect = &ctx.edit.track.channels[sect_coords.chan_i].sections[sect_coords.sect_i];
                        sect.last_tick = @max(sect.first_tick, @as(u64, @trunc((ctx.input.cursor_pos.x + self.scroll.x) / tick_width)));
                    },

                    else => {},
                };
        },

        .scroll => {
            self.scroll.x = @max(self.scroll.x - event.amount.x, 0);
            self.scroll.y = @max(self.scroll.y - event.amount.y, 0);
        },
    }
}

pub fn draw(self: Timeline, ctx: Ctx, rect: math.Rect(f32), queue: *render.Queue) !void {
    try queue.clip(rect);

    const min_chan_i: u16 = @trunc(self.scroll.y / chan_height);
    const max_chan_i = @min(min_chan_i + @as(u16, @trunc(rect.h / chan_height)) + 1, ctx.edit.track.channels.len);

    for (ctx.edit.track.channels[min_chan_i..max_chan_i], min_chan_i..) |chan, chan_i| {
        for (chan.sections) |sect| {
            const pos = self.project(@intCast(chan_i), sect.first_tick, rect.pos());
            try queue.drawSprite9Patch(.sect_red, .{
                .x = pos.x,
                .y = pos.y,
                .w = @as(f32, @floatFromInt(sect.last_tick - sect.first_tick)) * tick_width,
                .h = chan_height,
            });
        }
    }

    switch (self.sel) {
        .none => {},

        .sect, .sect_start, .sect_end => |coords| {
            const sect = ctx.edit.track.channels[coords.chan_i].sections[coords.sect_i];
            const pos = self.project(coords.chan_i, sect.first_tick, rect.pos());
            try queue.drawSprite9Patch(.outline, .{
                .x = pos.x - 2,
                .y = pos.y - 2,
                .w = @as(f32, @floatFromInt(sect.last_tick - sect.first_tick)) * tick_width + 4,
                .h = chan_height + 4,
            });
        },
    }

    try queue.unclip();
}

pub fn totalSize(ctx: Ctx) math.Vec2(f32) {
    return .{
        .x = std.math.floatMax(f32),
        .y = @as(f32, @floatFromInt(ctx.edit.track.channels.len)) * chan_height,
    };
}

/// Returns the cursor target at the given position.
fn pick(self: Timeline, track: Track, pos: math.Vec2(f32), off: math.Vec2(f32)) Target {
    const tick: u64 = @intFromFloat((pos.x - off.x + self.scroll.x) / tick_width);
    const chan_i: u8 = @intFromFloat((pos.y - off.y + self.scroll.y) / chan_height);

    if (chan_i >= track.channels.len)
        return .none;

    const chan = track.channels[chan_i];

    for (chan.sections, 0..) |sect, sect_i|
        if (sect.first_tick <= tick and sect.last_tick >= tick)
            return if (tick - sect.first_tick < sect_edge_width)
                .{ .sect_start = .{ .chan_i = chan_i, .sect_i = @intCast(sect_i) } }
            else if (sect.last_tick - tick < sect_edge_width)
                .{ .sect_end = .{ .chan_i = chan_i, .sect_i = @intCast(sect_i) } }
            else
                .{ .sect = .{ .chan_i = chan_i, .sect_i = @intCast(sect_i) } };

    return .{ .chan = .{ .chan_i = chan_i, .tick = tick } };
}

/// Returns the position corresponding to the given channel index and tick.
fn project(self: Timeline, chan_i: u16, tick: u64, off: math.Vec2(f32)) math.Vec2(f32) {
    return .{
        .x = @as(f32, @floatFromInt(tick)) * tick_width + off.x - self.scroll.x,
        .y = @as(f32, @floatFromInt(chan_i)) * chan_height + off.y - self.scroll.y,
    };
}
