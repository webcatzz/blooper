//! Common UI elements.

const Ctx = @import("../Ctx.zig");
const input = @import("../core/input.zig");
const math = @import("../core/math.zig");
const render = @import("../core/render.zig");

pub const frame = struct {
    pub const ribbon_offset_y = 2;
    pub const ribbon_h = 8;
    pub const ribbon_padding_h = 5;

    pub const inner_padding: math.Sides(f32) = .{ .left = 3, .right = 3, .top = 12, .bottom = 3 };

    pub fn draw(rect: math.Rect(f32), queue: *render.Queue) !void {
        try queue.drawSprite9Patch(.frame, rect);
    }
};

pub const button = struct {
    pub const State = enum { normal, focused, active };

    /// Draws an icon button.
    pub fn draw(rect: math.Rect(f32), icon: render.Sprite, state: State, queue: *render.Queue) !void {
        switch (state) {
            .normal => {
                try queue.drawSprite9Patch(.button, rect);
                try queue.drawSprite(icon, rect.pos().add(.{ .x = 3, .y = 2 }));
            },
            .focused => {
                try queue.drawSprite9Patch(.button_focused, rect);
                try queue.drawSprite(icon, rect.pos().add(.{ .x = 3, .y = 2 }));
            },
            .active => {
                try queue.drawSprite9Patch(.button_active, rect);
                try queue.drawSprite(icon, rect.pos().add(.{ .x = 3, .y = 3 }));
            },
        }
    }
};

pub const v_split = struct {
    pub fn rects(rect: math.Rect(f32), fr: f32) [2]math.Rect(f32) {
        const off = rect.h * fr;
        return .{
            .{ .x = rect.x, .y = rect.y, .w = rect.w, .h = off },
            .{ .x = rect.x, .y = rect.y + off, .w = rect.w, .h = rect.h - off },
        };
    }
};
