// Helpers for mapping and recognizing control input.
const c = @import("cbindings.zig").c;
const std = @import("std");
const tick = @import("ticks.zig");
const Vec2 = @import("zlm").Vec2;
const maxEnumVal = @import("utils.zig").maxEnumVal;

//TODO bindings

const ctlog = std.log.scoped(.ztest);

/// Logical input channels, which can be bound to keys.
pub const LogicalKeys = enum {
    Fwd, Back, StrafeLeft, StrafeRight, Quit
};


/// Keeps up with which keys/buttons are pressed, and for how long
/// they have been pressed.
pub const ControlState = struct {
    // Sentinel tick count for a key that is not pressed.
    const KeyUp = std.math.maxInt(tick.T);
    const Self = @This();

    key_times: [1+maxEnumVal(LogicalKeys)]tick.T = [_]tick.T{KeyUp} ** (1+maxEnumVal(LogicalKeys)),
    frame_tick: tick.T = 0,
    in_relmode: bool = false,

    /// Mask of buttons pressed since the last frame.
    mbutton_mask: u32 = 0,

    /// Relative x and y mouse position since last frame.
    myrel: c_int = 0,
    mxrel: c_int = 0,

    pub fn init() Self {
        return .{};
    }

    pub fn deinit(s: *Self) void {
        releaseMouse(s);
    }

    // Mouse needs to be captured if we want to get relattive
    // mouse move events.
    pub fn captureMouse(s: *Self) void {
        if (!s.in_relmode) {
            if (c.SDL_SetRelativeMouseMode(c.SDL_bool.SDL_TRUE) != -1) {
                s.in_relmode = true;
            } else {
                ctlog.err("Rel mouse mode not supported: {}", 
                          .{c.SDL_GetError()});
            }
        }
    }

    // Releases a previously captured mouse.
    pub fn releaseMouse(s: *Self) void {
        if (s.in_relmode) {
            if (c.SDL_SetRelativeMouseMode(c.SDL_bool.SDL_FALSE) != -1) {
                s.in_relmode = false;
            } else {
                ctlog.err("Could not leave mouse mode: {}", 
                          .{c.SDL_GetError()});
            }
        }
    }

    /// Should be called at the begining of a frame 
    /// before any press() or queries are called.
    pub fn beginFrame(self: *ControlState, now: tick.T) void {
        self.frame_tick = now;
        self.mbutton_mask = c.SDL_GetRelativeMouseState(&self.mxrel, 
                                                        &self.myrel);
    }

    pub fn getMouseMove(s: ControlState) Vec2 {
        return Vec2.new(@intToFloat(f32, s.mxrel), 
                        @intToFloat(f32, s.myrel));
    }

    pub fn press(self: *ControlState, key: LogicalKeys, down: bool) void {
        if (down) {
            self.key_times[@enumToInt(key)] = self.frame_tick;
        } else {
            self.key_times[@enumToInt(key)] = KeyUp;
        }
    }

    pub fn isPressed(self: ControlState, key: LogicalKeys) bool {
        return self.frame_tick >= self.key_times[@enumToInt(key)];
    }

    pub fn justPressed(self: ControlState, key: LogicalKeys) bool {
        return frame_tick == self.key_times[@enumToInt(key)];
    }

    /// Returns <0 if the key is not pressed. 
    pub fn ticksPressed(self: ControlState, key: LogicalKeys) f32 {
        const t = self.key_times[@enumToInt(key)];

        if (self.frame_time >= t) {
            return self.frame_tick - t;
        } else {
            return -1;
        }
    }
};

