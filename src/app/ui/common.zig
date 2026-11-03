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

pub const scroll_bar = struct {
    const min_thumb_len = 6;

    pub fn draw(comptime axis: math.Axis, scroll: f32, max_scroll: f32, rect: math.Rect(f32), queue: *render.Queue) !void {
        const thumb_len = @max(min_thumb_len, switch (axis) {
            .x => rect.w,
            .y => rect.h,
        } / max_scroll);

        try queue.drawSprite9Patch(.scroll_track, rect);
        try queue.drawSprite9Patch(.scroll_thumb, switch (axis) {
            .x => .{
                .x = rect.x + (rect.w - thumb_len) * (scroll / max_scroll) - 1,
                .y = rect.y - 1,
                .w = thumb_len + 2,
                .h = rect.h + 2,
            },
            .y => .{
                .x = rect.x - 1,
                .y = rect.y + (rect.h - thumb_len) * (scroll / max_scroll) - 1,
                .w = rect.w + 2,
                .h = thumb_len + 2,
            },
        });
    }
};

pub fn ScrollBox(comptime T: type) type {
    return struct {
        inner: T,

        const scrollbar_width = 4;

        pub fn respond(self: *ScrollBox(T), ctx: *Ctx, rect: math.Rect(f32), comptime event_type: input.event.Type, event: input.event.of(event_type)) !void {
            try self.inner.respond(ctx, .{
                .x = rect.x + 1,
                .y = rect.y + 1,
                .w = rect.w - scrollbar_width - 1,
                .h = rect.h - scrollbar_width - 1,
            }, event_type, event);
        }

        pub fn draw(self: ScrollBox(T), ctx: Ctx, rect: math.Rect(f32), queue: *render.Queue) !void {
            const inner_w = rect.w - scrollbar_width;
            const inner_h = rect.h - scrollbar_width;

            try queue.drawSprite9Patch(.frame, rect);

            const total_size: math.Vec2(f32) = T.totalSize(ctx);

            try scroll_bar.draw(.x, self.inner.scroll.x, total_size.x, .{
                .x = rect.x,
                .y = rect.y + inner_h,
                .w = inner_w,
                .h = scrollbar_width,
            }, queue);
            try scroll_bar.draw(.y, self.inner.scroll.y, total_size.y, .{
                .x = rect.x + inner_w,
                .y = rect.y,
                .w = scrollbar_width,
                .h = inner_h,
            }, queue);

            try self.inner.draw(ctx, .{
                .x = rect.x + 1,
                .y = rect.y + 1,
                .w = inner_w - 1,
                .h = inner_h - 1,
            }, queue);
        }
    };
}
