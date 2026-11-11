//! Application harness.
//!
//! Defines the callbacks called by `loop.run`.

const action = @import("action.zig");
const audio = @import("core/audio.zig");
const Ctx = @import("Ctx.zig");
const Edit = @import("Edit.zig");
const input = @import("core/input.zig");
const loop = @import("core/loop.zig");
const math = @import("core/math.zig");
const PianoRoll = @import("ui/PianoRoll.zig");
const render = @import("core/render.zig");
const std = @import("std");
const Timeline = @import("ui/Timeline.zig");
const Ui = @import("Ui.zig");

const App = @This();

/// Application state.
ctx: Ctx,

/// The UI system.
ui: Ui = .{},
/// A queue of rendering operations for the next frame.
render_queue: render.Queue,
/// An intermediary buffer used to synthesize audio.
synth_buf: []f32,

/// Piano roll state.
piano_roll: PianoRoll = .{},
/// Timeline state.
timeline: Timeline = .{},

/// Initializes the app.
pub fn init(gpa: std.mem.Allocator, io: std.Io) !App {
    var render_queue: render.Queue = try .init(gpa, io);
    errdefer render_queue.deinit();

    const synth_buf = try gpa.alloc(f32, 1024);
    errdefer gpa.free(synth_buf);

    const ctx: Ctx = try .init(gpa);
    errdefer ctx.deinit();

    return .{
        .ctx = ctx,
        .render_queue = render_queue,
        .synth_buf = synth_buf,
        .piano_roll = .{ .pat_i = 0 },
    };
}

/// Frees the app.
pub fn deinit(self: *App) void {
    self.ctx.gpa.free(self.synth_buf);
    self.ctx.deinit();
    self.ui.deinit();
    self.render_queue.deinit();
    self.* = undefined;
}

/// Updates the app's state over time.
pub fn iter(self: *App) !void {
    // Draws UI

    self.ui.clear(
        .{ .w = render.width(), .h = render.height() },
        &self.ctx.input,
        &self.render_queue,
    );

    try self.ui.split(.y, @divTrunc(self.ui.rect.h, 3) * 2);
    try self.ui.panel();
    try self.piano_roll.draw(self.ctx, &self.ui);
    self.ui.next();
    try self.ui.panel();
    try self.timeline.draw(self.ctx, &self.ui);

    self.ui.queue.flush();

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

/// Updates the app's state in response to input.
pub fn respond(self: *App, comptime event_type: input.event.Type, event: input.event.of(event_type)) !void {
    self.ctx.input.record(event_type, event);

    if (event_type == .button) {
        if (self.ctx.input.wasJustActivated(.toggle_synth)) {
            self.ctx.is_playing = !self.ctx.is_playing;
            self.ctx.synth.seek(0);
        } else if (self.ctx.input.wasJustActivated(.quit))
            loop.quit();
    }

    try self.ui.respond(&self.ctx);
}
