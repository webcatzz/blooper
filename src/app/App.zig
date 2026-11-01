//! Application state.

const action = @import("action.zig");
const Ctx = @import("Ctx.zig");
const Edit = @import("Edit.zig");
const input = @import("core/input.zig");
const render = @import("core/render.zig");
const std = @import("std");
const Timeline = @import("ui/Timeline.zig");

const App = @This();

ctx: Ctx,
render_queue: render.Queue,

timeline: Timeline = .{},

const width = 200;
const height = 150;

pub fn init(gpa: std.mem.Allocator, _: std.Io) !App {
    var render_queue: render.Queue = try .init();
    errdefer render_queue.deinit();

    const ctx: Ctx = try .init(gpa);
    errdefer ctx.deinit();

    return .{
        .ctx = ctx,
        .render_queue = render_queue,
    };
}

pub fn deinit(self: *App) void {
    self.ctx.deinit();
    self.render_queue.deinit();
    self.* = undefined;
}

pub fn iter(self: *App) !void {
    try self.timeline.draw(self.ctx, &self.render_queue);
    self.render_queue.flush(.{ .x = width, .y = height });
}

pub fn respond(self: *App, comptime event_type: input.event.Type, event: input.event.of(event_type)) !void {
    if (event_type == .cursor)
        self.ctx.input.record(event_type, .{ .pos = render.mapPos(event.pos, .{ .x = width, .y = height }) })
    else
        self.ctx.input.record(event_type, event);

    try self.timeline.respond(&self.ctx, event_type, event);
}
