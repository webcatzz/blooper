const action = @import("action.zig");
const Edit = @import("Edit.zig");
const std = @import("std");

const Ctx = @This();

edit: Edit,
input: action.Map = .{},

pub fn init(gpa: std.mem.Allocator) !Ctx {
    var edit: Edit = try .init(gpa);

    _ = try edit.insertPattern();
    try edit.insertChannel(0, .{ .instrument = .{ .base = .{ .chip_pulse = 0.5 } } });
    try edit.insertChannel(1, .{ .instrument = .{ .base = .{ .chip_pulse = 0.5 } } });

    return .{
        .edit = edit,
    };
}

pub fn deinit(self: *Ctx) void {
    self.edit.deinit();
}
