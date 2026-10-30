//! User action.

const input = @import("core/input.zig");
const math = @import("core/math.zig");
const std = @import("std");

/// An action the user might perform.
pub const Action = enum {
    left,
    right,
    up,
    down,
    accept,
    cancel,
};

/// Records input events and keeps track of input state.
pub const Map = struct {
    /// A set of all buttons currently recorded as pressed.
    pressed_buttons: std.EnumSet(input.Button) = .empty,
    /// The most recently recorded cursor position.
    cursor_pos: math.Vec2(f32) = .zero,
    /// Button bindings for each action.
    bindings: std.EnumArray(Action, [2]Binding) = default_bindings,
    /// The most recently recorded input event.
    last_event: input.event.Any = .{ .cursor = .{ .pos = .zero } },

    const Binding = ?input.Button;

    /// Default button bindings.
    pub const default_bindings: @FieldType(Map, "bindings") = .initDefault(.{ null, null }, .{
        .left = .{ .key_left, null },
        .right = .{ .key_right, null },
        .up = .{ .key_up, null },
        .down = .{ .key_down, null },
        .accept = .{ .key_z, null },
        .cancel = .{ .key_x, null },
    });

    /// Records the given input event.
    pub fn record(self: *Map, comptime event_type: input.event.Type, event: input.event.of(event_type)) void {
        switch (event_type) {
            .button => {
                self.pressed_buttons.setPresent(event.button, event.is_pressed);
                self.last_event = .{ .button = event };
            },
            .cursor => {
                self.cursor_pos = event.pos;
                self.last_event = .{ .cursor = event };
            },
            .scroll => self.last_event = .{ .scroll = event },
        }
    }

    /// Returns `true` if the given action is active.
    pub fn isActive(self: Map, action: Action) bool {
        for (self.bindings.get(action)) |binding|
            if (binding) |button|
                if (self.pressed_buttons.contains(button))
                    return true;
        return false;
    }

    /// Returns `true` if the given action was just activated.
    pub fn wasJustActivated(self: Map, action: Action) bool {
        switch (self.last_event) {
            .button => |button_event| if (button_event.is_pressed)
                for (self.bindings.get(action)) |binding|
                    if (binding) |button|
                        if (button_event.button == button)
                            return true,
            else => {},
        }
        return false;
    }

    /// Returns `true` if the given action was just deactivated.
    pub fn wasJustDeactivated(self: Map, action: Action) bool {
        switch (self.last_event) {
            .button => |button_event| if (!button_event.is_pressed)
                for (self.bindings.get(action)) |binding|
                    if (binding) |button|
                        if (button_event.button == button)
                            return true,
            else => {},
        }
        return false;
    }

    /// Returns a unit vector based on the state of each of the given actions.
    pub fn vector(self: Map, neg_x: Action, pos_x: Action, neg_y: Action, pos_y: Action) math.Vec2(f32) {
        return .{
            .x = @as(f32, @floatFromInt(@intFromBool(self.isActive(pos_x)))) -
                @as(f32, @floatFromInt(@intFromBool(self.isActive(neg_x)))),
            .y = @as(f32, @floatFromInt(@intFromBool(self.isActive(pos_y)))) -
                @as(f32, @floatFromInt(@intFromBool(self.isActive(neg_y)))),
        };
    }
};
