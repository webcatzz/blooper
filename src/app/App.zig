//! Application state.

const action = @import("action.zig");
const Ctx = @import("Ctx.zig");
const Edit = @import("Edit.zig");
const input = @import("core/input.zig");
const loop = @import("core/loop.zig");
const PianoRoll = @import("ui/PianoRoll.zig");
const render = @import("core/render.zig");
const std = @import("std");
const Timeline = @import("ui/Timeline.zig");
const ui = @import("ui/common.zig");

const App = @This();

ctx: Ctx,
render_queue: render.Queue,

timeline: Timeline = .{},
piano_roll: PianoRoll = .{},

/// The scale at which the application renders.
const scale = 4;

pub fn init(gpa: std.mem.Allocator, _: std.Io) !App {
    var render_queue: render.Queue = try .init();
    errdefer render_queue.deinit();

    const ctx: Ctx = try .init(gpa);
    errdefer ctx.deinit();

    return .{
        .ctx = ctx,
        .render_queue = render_queue,
        .piano_roll = .{ .pat_i = 0 },
    };
}

pub fn deinit(self: *App) void {
    self.ctx.deinit();
    self.render_queue.deinit();
    self.* = undefined;
}

pub fn iter(self: *App) !void {
    try ui.v_split.draw(
        self.piano_roll,
        self.timeline,
        self.ctx,
        .{ .w = render.widthf() / scale, .h = render.heightf() / scale },
        0.67,
        &self.render_queue,
    );

    self.render_queue.flush(scale);
}

pub fn respond(self: *App, comptime event_type: input.event.Type, event: input.event.of(event_type)) !void {
    if (event_type == .cursor)
        self.ctx.input.record(event_type, .{ .pos = event.pos.div(.all(scale)) })
    else
        self.ctx.input.record(event_type, event);

    if (event_type == .button and self.ctx.input.wasJustActivated(.quit))
        loop.quit();

    try ui.v_split.respond(
        &self.piano_roll,
        &self.timeline,
        &self.ctx,
        .{ .w = render.widthf() / scale, .h = render.heightf() / scale },
        0.67,
        event_type,
        event,
    );
}
