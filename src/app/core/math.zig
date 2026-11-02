//! Common math types.

/// A 2D vector.
pub fn Vec2(comptime T: type) type {
    return struct {
        x: T,
        y: T,

        /// A vector with all components set to `0`.
        pub const zero: Vec2(T) = .{ .x = 0, .y = 0 };
        /// A vector with all components set to `1`.
        pub const one: Vec2(T) = .{ .x = 1, .y = 1 };

        /// A unit vector facing right.
        pub const right: Vec2(T) = .{ .x = 1, .y = 0 };
        /// A unit vector facing up.
        pub const up: Vec2(T) = .{ .x = 0, .y = -1 };
        /// A unit vector facing left.
        pub const left: Vec2(T) = .{ .x = -1, .y = 0 };
        /// A unit vector facing down.
        pub const down: Vec2(T) = .{ .x = 0, .y = 1 };

        /// Returns a vector with all components set to `v`.
        pub fn all(v: T) Vec2(T) {
            return .{ .x = v, .y = v };
        }

        // Arithmetic

        /// Adds the given vectors, component-wise.
        pub fn add(self: Vec2(T), other: Vec2(T)) Vec2(T) {
            return .{ .x = self.x + other.x, .y = self.y + other.y };
        }

        /// Subtracts `other` from `self`, component-wise.
        pub fn sub(self: Vec2(T), other: Vec2(T)) Vec2(T) {
            return .{ .x = self.x - other.x, .y = self.y - other.y };
        }

        /// Multiplies the given vectors, component-wise.
        pub fn mul(self: Vec2(T), other: Vec2(T)) Vec2(T) {
            return .{ .x = self.x * other.x, .y = self.y * other.y };
        }

        /// Divides `self` by `other`, component-wise.
        pub fn div(self: Vec2(T), other: Vec2(T)) Vec2(T) {
            return .{ .x = self.x / other.x, .y = self.y / other.y };
        }

        /// Adds the given vectors in place, component-wise.
        pub fn addAssign(self: *Vec2(T), other: Vec2(T)) void {
            self.x += other.x;
            self.y += other.y;
        }

        /// Subtracts `other` from `self` in place, component-wise.
        pub fn subAssign(self: *Vec2(T), other: Vec2(T)) void {
            self.x -= other.x;
            self.y -= other.y;
        }

        /// Multiplies the given vectors in place, component-wise.
        pub fn mulAssign(self: *Vec2(T), other: Vec2(T)) void {
            self.x *= other.x;
            self.y *= other.y;
        }

        /// Divides `self` by `other` in place, component-wise.
        pub fn divAssign(self: *Vec2(T), other: Vec2(T)) void {
            self.x /= other.x;
            self.y /= other.y;
        }

        // Casting

        /// Coerces the components of the vector to the given type.
        pub fn coerce(self: Vec2(T), comptime U: type) Vec2(U) {
            return .{ .x = self.x, .y = self.y };
        }

        /// Invokes `@trunc` on the components of the vector.
        pub fn trunc(self: Vec2(T), comptime U: type) Vec2(U) {
            return .{ .x = @trunc(self.x), .y = @trunc(self.y) };
        }
    };
}

/// A rectangle.
pub fn Rect(comptime T: type) type {
    return struct {
        x: T = 0,
        y: T = 0,
        w: T,
        h: T,

        /// Returns the position of the rectangle.
        pub fn pos(self: Rect(T)) Vec2(T) {
            return .{ .x = self.x, .y = self.y };
        }

        /// Returns the size of the rectangle.
        pub fn size(self: Rect(T)) Vec2(T) {
            return .{ .x = self.w, .y = self.h };
        }
    };
}

/// Stores an offset for each cardinal side.
pub fn Sides(comptime T: type) type {
    return struct {
        left: T,
        right: T,
        top: T,
        bottom: T,
    };
}

/// An RGBA color.
pub fn Color(comptime T: type) type {
    const max_v: f32 =
        if (@typeInfo(T) == .float)
            1
        else if (T == u8)
            255
        else
            @compileError("`Color` component type should be `u8` or a float type");

    return struct {
        r: T,
        g: T,
        b: T,
        a: T,

        /// A color with all components set to `0`.
        pub const zero: Color(T) = .{ .r = 0, .g = 0, .b = 0, .a = 0 };
        /// Absolute black.
        pub const black: Color(T) = .{ .r = 0, .g = 0, .b = 0, .a = max_v };
        /// Absolute white.
        pub const white: Color(T) = .{ .r = max_v, .g = max_v, .b = max_v, .a = max_v };
        /// Absolute red.
        pub const red: Color(T) = .{ .r = max_v, .g = 0, .b = 0, .a = max_v };
        /// Absolute green.
        pub const green: Color(T) = .{ .r = 0, .g = max_v, .b = 0, .a = max_v };
        /// Absolute blue.
        pub const blue: Color(T) = .{ .r = 0, .g = 0, .b = max_v, .a = max_v };
        /// Absolute cyan.
        pub const cyan: Color(T) = .{ .r = 0, .g = max_v, .b = max_v, .a = max_v };
        /// Absolute magenta.
        pub const magenta: Color(T) = .{ .r = max_v, .g = 0, .b = max_v, .a = max_v };
        /// Absolute yellow.
        pub const yellow: Color(T) = .{ .r = max_v, .g = max_v, .b = 0, .a = max_v };
    };
}

pub const Side = enum {
    left,
    right,
    top,
    bottom,

    /// Returns a unit vector oriented toward the given side.
    pub fn vector(self: Side, comptime T: type) Vec2(T) {
        return switch (self) {
            .left => .left,
            .right => .right,
            .top => .up,
            .bottom => .down,
        };
    }
};
