//! Game state.

const action = @import("action.zig");
const input = @import("core/input.zig");
const render = @import("core/render.zig");
const std = @import("std");

const Game = @This();

tick: u16 = 0,

action_map: action.Map = .{},
render_queue: render.Queue,

const width = 200;
const height = 150;

pub fn init(_: std.mem.Allocator, _: std.Io) !Game {
    const render_queue: render.Queue = try .init();
    errdefer render_queue.deinit();

    return .{
        .render_queue = render_queue,
    };
}

pub fn deinit(self: *Game) void {
    self.render_queue.deinit();
    self.* = undefined;
}

pub fn iter(self: *Game) !void {
    self.tick +%= 1;
    try self.render_queue.drawSprite(switch ((self.tick / 32) % 5) {
        0 => .note_red,
        1 => .note_yellow,
        2 => .note_green,
        3 => .note_blue,
        4 => .note_purple,
        else => unreachable,
    }, .all(16));
    self.render_queue.commit(.{ .x = width, .y = height });
}

pub fn respond(self: *Game, comptime event_type: input.event.Type, event: input.event.of(event_type)) !void {
    self.action_map.record(event_type, event);
}
