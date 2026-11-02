//! Audio.

const sokol = @import("sokol");
const std = @import("std");

/// Returns the sample rate.
pub fn sampleRate() u32 {
    return @intCast(sokol.audio.sampleRate());
}

/// Returns the number of channels.
pub fn channelCount() u32 {
    return @intCast(sokol.audio.channels());
}

/// Returns the number of frames needed to fill the packet queue.
pub fn framesNeeded() u32 {
    return @intCast(sokol.audio.expect());
}

/// Pushes the given audio data. Returns the number of frames pushed.
pub fn push(data: [*]f32, frame_count: u32) u32 {
    std.debug.assert(frame_count <= std.math.maxInt(i32));
    return @intCast(sokol.audio.push(@ptrCast(data), @intCast(frame_count)));
}
