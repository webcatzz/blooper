//! Application state.

const action = @import("action.zig");
const audio = @import("core/audio.zig");
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
synth_buf: []f32,

timeline: ui.ScrollBox(Timeline) = .{ .inner = .{} },
piano_roll: ui.ScrollBox(PianoRoll) = .{ .inner = .{} },

/// The scale at which the application renders.
const scale = 4;

pub fn init(gpa: std.mem.Allocator, _: std.Io) !App {
    var render_queue: render.Queue = try .init();
    errdefer render_queue.deinit();

    const synth_buf = try gpa.alloc(f32, 1024);
    errdefer gpa.free(synth_buf);

    const ctx: Ctx = try .init(gpa);
    errdefer ctx.deinit();

    return .{
        .ctx = ctx,
        .render_queue = render_queue,
        .synth_buf = synth_buf,
        .piano_roll = .{ .inner = .{ .pat_i = 0 } },
    };
}

pub fn deinit(self: *App) void {
    self.ctx.gpa.free(self.synth_buf);
    self.ctx.deinit();
    self.render_queue.deinit();
    self.* = undefined;
}

pub fn iter(self: *App) !void {
    // Renders

    try ui.v_split.draw(
        self.piano_roll,
        self.timeline,
        self.ctx,
        .{ .w = render.widthf() / scale, .h = render.heightf() / scale },
        0.67,
        &self.render_queue,
    );

    self.render_queue.flush(scale);

    // Streams audio

    if (self.ctx.is_playing) {
        std.debug.assert(audio.channelCount() == 1);
        const buf = self.synth_buf[0..@min(audio.framesNeeded(), self.synth_buf.len)];
        if (buf.len == 0) return;

        @memset(buf, 0);
        try self.ctx.synth.run(self.ctx.gpa, self.ctx.edit.track, audio.sampleRate(), buf);
        _ = audio.push(buf.ptr, @intCast(buf.len));
    }
}

pub fn respond(self: *App, comptime event_type: input.event.Type, event: input.event.of(event_type)) !void {
    if (event_type == .cursor)
        self.ctx.input.record(event_type, .{ .pos = event.pos.div(.all(scale)) })
    else
        self.ctx.input.record(event_type, event);

    if (event_type == .button) {
        if (self.ctx.input.wasJustActivated(.toggle_synth)) {
            self.ctx.is_playing = !self.ctx.is_playing;
            self.ctx.synth.seek(0);
        } else if (self.ctx.input.wasJustActivated(.quit))
            loop.quit();
    }

    if (self.ctx.is_playing) return;

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
