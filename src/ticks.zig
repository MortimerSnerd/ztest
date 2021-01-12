// The game logic is stepped once per tick.
pub const T = i32;

// Current tick rate is 60Hz.
pub const Rate = 60.0;
pub const Length = 1.0/Rate;

// Accumulates and divides frame times into ticks.
pub const TickAccum = struct {
    tick_accum: f64 = 0,

    pub fn new() TickAccum {
        return .{};
    }

    // Call at the beginning of the frame to get
    // the number of ticks that should be executed
    // this frame.
    pub fn numTicksReady(s: *TickAccum, dT: f64) T {
        var rv: T = 0;

        s.tick_accum += dT;
        while (s.tick_accum >= Length) {
            rv += 1;
            s.tick_accum -= Length;
        }

        return rv;
    }
};


