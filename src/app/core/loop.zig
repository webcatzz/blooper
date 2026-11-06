//! The main loop.

const input = @import("input.zig");
const render = @import("render.zig");
const sokol = @import("sokol");
const std = @import("std");

pub var gpa: std.mem.Allocator = undefined;
pub var io: std.Io = undefined;

/// Runs the application defined by `T`.
///
/// `T` should fulfill the following interface:
///
/// ```
/// fn init(std.mem.Allocator, std.Io) !T
/// fn deinit(*T) void
/// fn iter(*T) !void
/// fn respond(*T, comptime event_type: input.event.Type, input.event.of(event_type)) !void
/// ```
///
/// This function should not be called while another instance is still running.
pub fn run(comptime T: type, init: std.process.Init) void {
    const impl = struct {
        var state: T = undefined;

        fn sokolInit() callconv(.c) void {
            sokol.gfx.setup(.{
                .environment = sokol.glue.environment(),
                .logger = .{ .func = sokol.log.func },
            });

            sokol.audio.setup(.{
                .logger = .{ .func = sokol.log.func },
            });

            if (!sokol.gfx.isvalid())
                std.log.scoped(.sokol).err("Failed to initialize Sokol graphics backend", .{});
            if (!sokol.audio.isvalid())
                std.log.scoped(.sokol).err("Failed to initialize Sokol audio backend", .{});

            state = T.init(gpa, io) catch {
                if (@errorReturnTrace()) |trace|
                    std.debug.dumpErrorReturnTrace(trace);
                sokol.app.quit();
                return;
            };
        }

        fn sokolCleanup() callconv(.c) void {
            state.deinit();
            sokol.audio.shutdown();
            sokol.gfx.shutdown();
        }

        fn sokolFrame() callconv(.c) void {
            state.iter() catch {
                if (@errorReturnTrace()) |trace|
                    std.debug.dumpErrorReturnTrace(trace);
                sokol.app.quit();
                return;
            };
        }

        fn sokolEvent(event: [*c]const sokol.app.Event) callconv(.c) void {
            (switch (event.*.type) {
                .KEY_DOWN => state.respond(.button, .{
                    .button = buttonFromSokolKeycode(event.*.key_code) orelse return,
                    .is_pressed = true,
                }),

                .KEY_UP => state.respond(.button, .{
                    .button = buttonFromSokolKeycode(event.*.key_code) orelse return,
                    .is_pressed = false,
                }),

                .MOUSE_DOWN => state.respond(.button, .{
                    .button = buttonFromSokolMouseButton(event.*.mouse_button) orelse return,
                    .is_pressed = true,
                }),

                .MOUSE_UP => state.respond(.button, .{
                    .button = buttonFromSokolMouseButton(event.*.mouse_button) orelse return,
                    .is_pressed = false,
                }),

                .MOUSE_MOVE => state.respond(.cursor, .{
                    .pos = .{ .x = event.*.mouse_x, .y = event.*.mouse_y },
                }),

                .MOUSE_SCROLL => state.respond(.scroll, .{
                    .amount = .{ .x = event.*.scroll_x, .y = event.*.scroll_y },
                }),

                .CHAR => state.respond(.char, .{
                    .char = event.*.char_code,
                }),

                else => return,
            }) catch {
                if (@errorReturnTrace()) |trace|
                    std.debug.dumpErrorReturnTrace(trace);
                sokol.app.quit();
                return;
            };
        }
    };

    gpa = init.gpa;
    io = init.io;

    sokol.app.run(.{
        .window_title = "blooper",
        .width = 800,
        .height = 600,
        .init_cb = impl.sokolInit,
        .cleanup_cb = impl.sokolCleanup,
        .frame_cb = impl.sokolFrame,
        .event_cb = impl.sokolEvent,
        .logger = .{ .func = sokol.log.func },
    });
}

/// Exits the currently running main loop.
pub fn quit() void {
    sokol.app.quit();
}

/// Returns the button ID corresponding to the given Sokol keycode, or `null`.
fn buttonFromSokolKeycode(keycode: sokol.app.Keycode) ?input.Button {
    return switch (keycode) {
        .SPACE => .key_space,
        .A => .key_a,
        .B => .key_b,
        .C => .key_c,
        .D => .key_d,
        .E => .key_e,
        .F => .key_f,
        .G => .key_g,
        .H => .key_h,
        .I => .key_i,
        .J => .key_j,
        .K => .key_k,
        .L => .key_l,
        .M => .key_m,
        .N => .key_n,
        .O => .key_o,
        .P => .key_p,
        .Q => .key_q,
        .R => .key_r,
        .S => .key_s,
        .T => .key_t,
        .U => .key_u,
        .V => .key_v,
        .W => .key_w,
        .X => .key_x,
        .Y => .key_y,
        .Z => .key_z,
        ._0 => .key_0,
        ._1 => .key_1,
        ._2 => .key_2,
        ._3 => .key_3,
        ._4 => .key_4,
        ._5 => .key_5,
        ._6 => .key_6,
        ._7 => .key_7,
        ._8 => .key_8,
        ._9 => .key_9,
        .ESCAPE => .key_escape,
        .ENTER => .key_enter,
        .TAB => .key_tab,
        .BACKSPACE => .key_backspace,
        .RIGHT => .key_right,
        .LEFT => .key_left,
        .DOWN => .key_down,
        .UP => .key_up,
        .LEFT_SHIFT => .key_lshift,
        .LEFT_CONTROL => .key_lctrl,
        .LEFT_ALT => .key_lalt,
        .LEFT_SUPER => .key_lsuper,
        .RIGHT_SHIFT => .key_rshift,
        .RIGHT_CONTROL => .key_rctrl,
        .RIGHT_ALT => .key_ralt,
        .RIGHT_SUPER => .key_rsuper,
        else => null,
    };
}

/// Returns the button ID corresponding to the given Sokol mouse button, or
/// `null`.
fn buttonFromSokolMouseButton(mouse_button: sokol.app.Mousebutton) ?input.Button {
    return switch (mouse_button) {
        .LEFT, .RIGHT, .MIDDLE => @fromBackingInt(@as(u8, @intCast(@backingInt(mouse_button))) + @backingInt(input.Button.mouse_left)),
        else => null,
    };
}
