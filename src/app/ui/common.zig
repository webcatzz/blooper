//! Common UI elements.

const Ctx = @import("../Ctx.zig");
const input = @import("../core/input.zig");
const math = @import("../core/math.zig");
const render = @import("../core/render.zig");

pub const v_split = struct {
    pub fn respond(first: anytype, last: anytype, ctx: *Ctx, rect: math.Rect(f32), fr: f32, comptime event_type: input.event.Type, event: input.event.of(event_type)) !void {
        const off = rect.h * fr;

        try if (ctx.input.cursor_pos.y < rect.y + off)
            first.respond(ctx, .{ .x = rect.x, .y = rect.y, .w = rect.w, .h = off }, event_type, event)
        else
            last.respond(ctx, .{ .x = rect.x, .y = rect.y + off, .w = rect.w, .h = rect.h - off }, event_type, event);
    }

    pub fn draw(first: anytype, last: anytype, ctx: Ctx, rect: math.Rect(f32), fr: f32, queue: *render.Queue) !void {
        const off = rect.h * fr;

        try first.draw(ctx, .{ .x = rect.x, .y = rect.y, .w = rect.w, .h = off }, queue);
        try last.draw(ctx, .{ .x = rect.x, .y = rect.y + off, .w = rect.w, .h = rect.h - off }, queue);
    }
};

pub const scrollbox = struct {
    const scrollbar_width = 4;

    pub fn respond(comptime T: type, inner: *T, ctx: *Ctx, rect: math.Rect(f32), comptime event_type: input.event.Type, event: input.event.of(event_type)) !void {
        if (@hasField(T, "scroll") and event_type == .scroll) {
            inner.scroll.x = @min(inner.scroll.x + event.amount.x, 0);
            inner.scroll.y = @min(inner.scroll.y + event.amount.y, 0);
        }

        try inner.respond(ctx, .{
            .x = rect.x,
            .y = rect.y,
            .w = rect.w - scrollbar_width,
            .h = rect.h - scrollbar_width,
        }, event_type, event);
    }

    pub fn draw(comptime T: type, inner: T, ctx: Ctx, rect: math.Rect(f32), queue: *render.Queue) !void {
        const inner_w = rect.w - scrollbar_width;
        const inner_h = rect.h - scrollbar_width;

        try queue.drawSprite9Patch(.scroll_track, .{
            .x = rect.x + inner_w,
            .y = rect.y,
            .w = scrollbar_width,
            .h = inner_h,
        }, queue);
        try queue.drawSprite9Patch(.scroll_track, .{
            .x = rect.x,
            .y = rect.y + inner_h,
            .w = inner_w,
            .h = scrollbar_width,
        }, queue);

        try queue.clip(.{
            .x = rect.x,
            .y = rect.y,
            .w = inner_w,
            .h = inner_h,
        });
        try inner.draw(ctx, .{
            .x = rect.x,
            .y = rect.y,
            .w = inner_w,
            .h = inner_h,
        }, queue);
        try queue.unclip();
    }
};
