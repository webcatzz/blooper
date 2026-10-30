const App = @import("app/App.zig");
const loop = @import("app/core/loop.zig");
const std = @import("std");

pub fn main(init: std.process.Init) void {
    loop.run(App, init);
}
