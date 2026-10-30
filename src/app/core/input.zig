//! Data structures for representing user input.

const math = @import("math.zig");

const input = @This();

pub const event = struct {
    /// A button is pressed or released.
    pub const Button = struct { button: input.Button, is_pressed: bool };
    /// A cursor is moved to a new position.
    pub const Cursor = struct { pos: math.Vec2(f32) };
    /// A wheel or trackpad is scrolled by some amount.
    pub const Scroll = struct { amount: math.Vec2(f32) };

    /// The type of an input event.
    pub const Type = enum {
        button,
        cursor,
        scroll,
    };

    /// A union of events of any type.
    pub const Any = union(Type) {
        button: event.Button,
        cursor: event.Cursor,
        scroll: event.Scroll,
    };

    /// Returns an event of the given type.
    pub fn of(comptime t: Type) type {
        return switch (t) {
            .button => event.Button,
            .cursor => event.Cursor,
            .scroll => event.Scroll,
        };
    }
};

/// A button the user might press.
pub const Button = enum(u8) {
    key_a,
    key_b,
    key_c,
    key_d,
    key_e,
    key_f,
    key_g,
    key_h,
    key_i,
    key_j,
    key_k,
    key_l,
    key_m,
    key_n,
    key_o,
    key_p,
    key_q,
    key_r,
    key_s,
    key_t,
    key_u,
    key_v,
    key_w,
    key_x,
    key_y,
    key_z,
    key_0,
    key_1,
    key_2,
    key_3,
    key_4,
    key_5,
    key_6,
    key_7,
    key_8,
    key_9,
    key_left,
    key_right,
    key_up,
    key_down,

    mouse_left,
    mouse_right,
    mouse_middle,
};
