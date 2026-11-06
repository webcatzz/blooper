//! Application state.

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
const ui = @import("ui/common.zig");

const App = @This();

ctx: Ctx,
render_queue: render.Queue,
synth_buf: []f32,

timeline: Timeline = .{},
piano_roll: PianoRoll = .{},

/// The scale at which the application renders.
const scale = 3;

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
        .piano_roll = .{ .pat_i = 0 },
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

    const rect: math.Rect(f32) = .{ .w = render.widthf() / scale, .h = render.heightf() / scale };

    const rects = ui.v_split.rects(rect, 0.67);

    try ui.frame.draw(rects[0], &self.render_queue);
    try self.piano_roll.draw(self.ctx, rects[0].shrink(ui.frame.inner_padding), &self.render_queue);
    _ = try self.render_queue.drawText("roll", rects[0].pos().add(.{ .x = ui.frame.ribbon_padding_h, .y = ui.frame.ribbon_offset_y + 1 }));

    try ui.frame.draw(rects[1], &self.render_queue);
    try self.timeline.draw(self.ctx, rects[1].shrink(ui.frame.inner_padding), &self.render_queue);
    _ = try self.render_queue.drawText("timeline", rects[1].pos().add(.{ .x = ui.frame.ribbon_padding_h, .y = ui.frame.ribbon_offset_y + 1 }));

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

    const rect: math.Rect(f32) = .{ .w = render.widthf() / scale, .h = render.heightf() / scale };

    const rects = ui.v_split.rects(rect, 0.67);
    if (self.ctx.input.cursor_pos.y < rects[1].y)
        try self.piano_roll.respond(&self.ctx, rects[0].pos().add(.{ .x = ui.frame.inner_padding.left, .y = ui.frame.inner_padding.top }), event_type, event)
    else
        try self.timeline.respond(&self.ctx, rects[1].pos().add(.{ .x = ui.frame.inner_padding.left, .y = ui.frame.inner_padding.top }), event_type, event);
}
