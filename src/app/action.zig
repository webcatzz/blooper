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
    next,
    prev,

    accept,
    cancel,
    remove,
    toggle_synth,

    quit,
};

/// A physical button binding for an action.
const Binding = struct {
    button: input.Button,
    modifiers: Modifiers = .{},
};

/// A set of modifier buttons.
const Modifiers = packed struct {
    shift: bool = false,
    ctrl: bool = false,
    alt: bool = false,
    super: bool = false,
};

/// Records input events, keeps track of input state, and allows querying
/// actions' state.
pub const Map = struct {
    /// A set of all buttons currently recorded as pressed.
    pressed_buttons: std.EnumSet(input.Button) = .empty,
    /// The most recently recorded cursor position.
    cur_pos: math.Vec2(i32) = .zero,
    /// The motion of the cursor, relative to the second-most recently recorded
    /// cursor position.
    cur_motion: math.Vec2(i32) = .zero,
    /// Button bindings for each action.
    bindings: std.EnumArray(Action, [2]?Binding) = default_bindings,
    /// The most recently recorded input event.
    last_event: input.event.Any = .{ .cursor = .{ .pos = .zero } },

    /// Default button bindings.
    pub const default_bindings: @FieldType(Map, "bindings") = .init(.{
        .left = .{ .{ .button = .key_left }, null },
        .right = .{ .{ .button = .key_right }, null },
        .up = .{ .{ .button = .key_up }, null },
        .down = .{ .{ .button = .key_down }, null },
        .next = .{ .{ .button = .key_tab }, null },
        .prev = .{ .{ .button = .key_tab, .modifiers = .{ .shift = true } }, null },

        .accept = .{ .{ .button = .mouse_left }, null },
        .cancel = .{ .{ .button = .key_escape }, null },
        .remove = .{ .{ .button = .key_backspace }, null },
        .toggle_synth = .{ .{ .button = .key_space }, null },

        .quit = .{ .{ .button = .key_w, .modifiers = .{ .super = true } }, null },
    });

    /// Records the given input event.
    pub fn record(self: *Map, comptime event_type: input.event.Type, event: input.event.of(event_type)) void {
        switch (event_type) {
            .button => {
                self.pressed_buttons.setPresent(event.button, event.is_pressed);
                self.last_event = .{ .button = event };
            },
            .cursor => {
                self.cur_motion = event.pos.sub(self.cur_pos);
                self.cur_pos = event.pos;
                self.last_event = .{ .cursor = event };
            },
            .scroll => self.last_event = .{ .scroll = event },
            else => {},
        }
    }

    /// Returns `true` if the given action is active.
    pub fn isActive(self: Map, action: Action) bool {
        for (self.bindings.get(action)) |maybe_binding|
            if (maybe_binding) |binding|
                if (self.pressed_buttons.contains(binding.button) and
                    self.areModifiersPressed(binding.modifiers))
                    return true;
        return false;
    }

    /// Returns `true` if the given action was just activated.
    pub fn wasJustActivated(self: Map, action: Action) bool {
        switch (self.last_event) {
            .button => |button_event| if (button_event.is_pressed)
                for (self.bindings.get(action)) |maybe_binding|
                    if (maybe_binding) |binding|
                        if (binding.button == button_event.button and
                            self.areModifiersPressed(binding.modifiers))
                            return true,
            else => {},
        }
        return false;
    }

    /// Returns `true` if the given action was just deactivated.
    pub fn wasJustDeactivated(self: Map, action: Action) bool {
        switch (self.last_event) {
            .button => |button_event| if (!button_event.is_pressed)
                for (self.bindings.get(action)) |maybe_binding|
                    if (maybe_binding) |binding|
                        if (binding.button == button_event.button and
                            self.areModifiersPressed(maybe_binding.modifiers))
                            return true,
            else => {},
        }
        return false;
    }

    /// Returns `true` if the given modifiers are all pressed.
    fn areModifiersPressed(self: Map, modifiers: Modifiers) bool {
        return (!modifiers.shift or self.pressed_buttons.contains(.key_lshift) or self.pressed_buttons.contains(.key_rshift)) and
            (!modifiers.ctrl or self.pressed_buttons.contains(.key_lctrl) or self.pressed_buttons.contains(.key_rctrl)) and
            (!modifiers.alt or self.pressed_buttons.contains(.key_lalt) or self.pressed_buttons.contains(.key_ralt)) and
            (!modifiers.super or self.pressed_buttons.contains(.key_lsuper) or self.pressed_buttons.contains(.key_rsuper));
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
