//! The main loop.

const input = @import("input.zig");
const render = @import("render.zig");
const sokol = @import("sokol");
const std = @import("std");

pub var gpa: std.mem.Allocator = undefined;
pub var io: std.Io = undefined;

/// Runs the application defined by the given type.
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

            state = T.init(gpa, io) catch {
                if (@errorReturnTrace()) |trace|
                    std.debug.dumpErrorReturnTrace(trace);
                sokol.app.quit();
                return;
            };
        }

        fn sokolCleanup() callconv(.c) void {
            state.deinit();
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
    });
}

/// Returns the button ID corresponding to the given Sokol keycode, or `null`.
fn buttonFromSokolKeycode(keycode: sokol.app.Keycode) ?input.Button {
    return switch (keycode) {
        .A, .B, .C, .D, .E, .F, .G, .H, .I, .J, .K, .L, .M, .N, .O, .P, .Q, .R, .S, .T, .U, .V, .W, .X, .Y, .Z => @fromBackingInt(@as(u8, @intCast(@backingInt(keycode) - @backingInt(sokol.app.Keycode.A))) + @backingInt(input.Button.key_a)),
        ._0, ._1, ._2, ._3, ._4, ._5, ._6, ._7, ._8, ._9 => @fromBackingInt(@as(u8, @intCast(@backingInt(keycode) - @backingInt(sokol.app.Keycode._0))) + @backingInt(input.Button.key_0)),
        .LEFT => .key_left,
        .RIGHT => .key_right,
        .UP => .key_up,
        .DOWN => .key_down,
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
