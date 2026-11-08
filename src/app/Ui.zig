//! An immediate-mode UI system.

const action = @import("action.zig");
const builtin = @import("builtin");
const Ctx = @import("Ctx.zig");
const loop = @import("core/loop.zig");
const math = @import("core/math.zig");
const render = @import("core/render.zig");
const std = @import("std");
const Timeline = @import("ui/Timeline.zig");

const Ui = @This();

/// The current working rectangle.
rect: math.Rect(i32) = .zero,
/// The next working rectangle.
next_rect: math.Rect(i32) = .zero,
/// A stack of clipping rectangles.
clip_stack: std.ArrayList(math.Rect(i32)) = .empty,

/// Regions listening for input.
regions: std.MultiArrayList(Region) = .empty,

/// The current input state.
input: *action.Map = undefined,
/// A queue of instructions for rendering the UI.
queue: *render.Queue = undefined,

/// The width of an icon button.
pub const icon_button_w = 9;
/// The height of an icon button.
pub const icon_button_h = 9;

/// A rectangular region of the UI with an associated input callback.
const Region = struct {
    rect: math.Rect(i32),
    callback: Callback,
};

/// A function pointer with additional context.
///
/// Used for input callbacks.
const Callback = struct {
    /// A type-erased pointer to an externally-defined context.
    ctx: *anyopaque,
    /// A pointer to the callback implementation. `ctx` is passed as its first
    /// argument.
    f: *const fn (*anyopaque, *Ctx, math.Rect(i32)) error{ IndexOverflow, OutOfMemory }!void,

    /// A no-op callback.
    pub const noop: Callback = .{
        .ctx = undefined,
        .f = struct {
            fn impl(_: *anyopaque, _: *Ctx, _: math.Rect(i32)) !void {}
        }.impl,
    };

    /// Wraps the given function in a callback, without any context.
    pub fn wrap(f: fn (*void, *Ctx, math.Rect(i32)) error{ IndexOverflow, OutOfMemory }!void) Callback {
        const inner = struct {
            fn wrapper(a: *anyopaque, b: *Ctx, c: math.Rect(i32)) !void {
                return f(@ptrCast(@alignCast(a)), b, c);
            }
        };
        return .{
            .ctx = &.{},
            .f = inner.wrapper,
        };
    }

    /// Wraps the given context and function in a callback.
    pub fn wrapCtx(ctx: anytype, f: fn (@TypeOf(ctx), *Ctx, math.Rect(i32)) error{ IndexOverflow, OutOfMemory }!void) Callback {
        const inner = struct {
            fn wrapper(a: *anyopaque, b: *Ctx, c: math.Rect(i32)) !void {
                return f(@ptrCast(@alignCast(a)), b, c);
            }
        };
        return .{
            .ctx = ctx,
            .f = inner.wrapper,
        };
    }

    /// Calls the callback.
    pub fn call(self: Callback, app_ctx: *Ctx, rect: math.Rect(i32)) !void {
        return self.f(self.ctx, app_ctx, rect);
    }
};

/// Clears the UI, resizing it to the given rectangle.
///
/// Uses the given input state and rendering queue for the next batch of draw
/// calls.
pub fn clear(
    self: *Ui,
    rect: math.Rect(i32),
    input: *action.Map,
    queue: *render.Queue,
) void {
    self.rect = rect;
    self.clip_stack.clearRetainingCapacity();
    self.regions.clearRetainingCapacity();
    self.input = input;
    self.queue = queue;
}

/// Splits the working rectangle at the given position along the given axis.
///
/// Call `next` to move to the next half of the split.
pub fn split(self: *Ui, comptime axis: math.Axis, pos: i32) void {
    // TODO nested splits behave unexpectedly
    switch (axis) {
        .x => {
            self.next_rect = self.rect;
            self.rect.w = pos;
            self.next_rect.x += pos;
            self.next_rect.w -= pos;
        },
        .y => {
            self.next_rect = self.rect;
            self.rect.h = pos;
            self.next_rect.y += pos;
            self.next_rect.h -= pos;
        },
    }
}

/// Moves to the next working rectangle.
pub fn next(self: *Ui) void {
    self.rect = self.next_rect;
}

/// Adds a panel to the working rectangle, shrinking it as a result.
pub fn panel(self: *Ui) !void {
    try self.queue.drawSprite9Patch(.panel, self.rect);
    self.rect = self.rect.shrink(.all(2));
}

/// Adds an inset to the working rectangle, shrinking it as a result.
pub fn inset(self: *Ui) !void {
    try self.queue.drawSprite9Patch(.panel_inset, self.rect);
    self.rect = self.rect.shrink(.all(1));
}

/// Places an icon button with the given icon in the top-left corner of the
/// working rectangle.
///
/// Calls the given callback when the button receives input. See `flag` for
/// usage notes.
pub fn addIconButton(self: *Ui, icon: render.Sprite, callback: Callback) !void {
    const rect: math.Rect(i32) = .{
        .x = self.rect.x,
        .y = self.rect.y,
        .w = 9,
        .h = 9,
    };

    const spr: render.Sprite = if (!rect.contains(self.input.cur_pos))
        .button
    else if (self.input.wasJustActivated(.accept))
        .button_active
    else
        .button_hovered;

    try self.queue.drawSprite9Patch(spr, rect);
    try self.queue.drawSprite(icon, .{ .x = rect.x + 3, .y = rect.y + 2 + @intFromBool(spr == .button_active) });
    try self.flag(rect, callback);
}

/// Adds a scrollbar to the working rectangle, shrinking it as a result.
///
/// Calls the given callback when the scrollbar receives input. See `flag` for
/// usage notes.
pub fn addScrollbar(self: *Ui, comptime axis: math.Axis, scroll: i32, full_size: i32, callback: Callback) !void {
    switch (axis) {
        .x => {
            self.rect.h -= 4;

            const thumb_len = @min(@max(0, self.rect.w), @max(16, @divTrunc(self.rect.w * self.rect.w, full_size)));
            const thumb_off = @divTrunc((self.rect.w - thumb_len) * scroll, full_size);
            const track_rect: math.Rect(i32) = .{
                .x = self.rect.x,
                .y = self.rect.y + self.rect.h,
                .w = self.rect.w,
                .h = 4,
            };
            const scroll_thumb_border = render.Sprite.info.get(.scroll_thumb).border;

            try self.flag(track_rect, callback);

            try self.queue.drawSpriteStretch(.scroll_track, track_rect.shrink(.all(1)));
            try self.queue.drawSprite9Patch(.scroll_thumb, .{
                .x = track_rect.x + thumb_off,
                .y = track_rect.y - 1,
                .w = thumb_len,
                .h = track_rect.h + 2,
            });
            try self.queue.drawSprite(.scroll_ticks_h, .{
                .x = track_rect.x + thumb_off + @divTrunc(thumb_len - scroll_thumb_border.left - scroll_thumb_border.right, 2),
                .y = track_rect.y - 1 + scroll_thumb_border.top,
            });
        },
        .y => {
            self.rect.w -= 4;

            const thumb_len = @min(@max(0, self.rect.h), @max(16, @divTrunc(self.rect.h * self.rect.h, full_size)));
            const thumb_off = @divTrunc((self.rect.h - thumb_len) * scroll, full_size);
            const track_rect: math.Rect(i32) = .{
                .x = self.rect.x + self.rect.w,
                .y = self.rect.y,
                .w = 4,
                .h = self.rect.h,
            };
            const scroll_thumb_border = render.Sprite.info.get(.scroll_thumb).border;

            try self.flag(track_rect, callback);

            try self.queue.drawSpriteStretch(.scroll_track, track_rect.shrink(.all(1)));
            try self.queue.drawSprite9Patch(.scroll_thumb, .{
                .x = track_rect.x - 1,
                .y = track_rect.y + thumb_off,
                .w = track_rect.w + 2,
                .h = thumb_len,
            });
            try self.queue.drawSprite(.scroll_ticks_v, .{
                .x = track_rect.x - 1 + scroll_thumb_border.left,
                .y = track_rect.y + thumb_off + (thumb_len - scroll_thumb_border.top - scroll_thumb_border.bottom) / 2,
            });
        },
    }
}

/// Clips subsequent drawing operations to the given rectangle.
pub fn clip(self: *Ui, rect: math.Rect(i32)) !void {
    var intersection = rect;
    if (self.clip_stack.last()) |last_rect|
        intersection = intersection.intersect(last_rect);

    try self.clip_stack.append(loop.gpa, intersection);
    try self.queue.clip(intersection);
}

/// Pops the last clipping rectangle.
pub fn unclip(self: *Ui) !void {
    _ = self.clip_stack.pop();
    if (self.clip_stack.last()) |rect|
        try self.queue.clip(rect)
    else
        try self.queue.unclip();
}

/// Associates the given rectangle with the given callback. The callback will be
/// called whenever any input is received within the rectangle, until the next
/// time `clear` is called.
///
/// The callback should remain valid until the next time `clear` is called. In
/// particular, the callback context should not be moved or modified in any way
/// that would invalidate the callback's pointer to its context.
pub fn flag(self: *Ui, rect: math.Rect(i32), callback: Callback) !void {
    try self.regions.append(loop.gpa, .{ .rect = rect, .callback = callback });
}

/// Responds to the most recently recorded input event in `ctx`.
pub fn respond(self: Ui, ctx: *Ctx) !void {
    for (self.regions.items(.rect), 0..) |rect, i|
        if (rect.contains(ctx.input.cur_pos))
            try self.regions.items(.callback)[i].call(ctx, rect);
}
