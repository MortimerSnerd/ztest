const std = @import("std");
const c = @import("cbindings.zig").c;
const ctrl = @import("controls.zig");
const mr = @import("mrrender.zig");
const RenderState = mr.RenderState;
const sg = @import("sokol").gfx;
const st = @import("sokol").time;
const tick = @import("ticks.zig");
const zlm = @import("zlm");
const Vec3 = zlm.Vec3;
const Mat4 = zlm.Mat4;

// Root logger def for std.log
pub fn log(comptime level: std.log.Level,
           comptime scope: @TypeOf(.EnumLiteral),
           comptime format: []const u8,
           args: anytype) void {
    const scope_prefix = @tagName(scope);
    const prefix = @tagName(level) ++ "/" ++ scope_prefix ++ ": ";
    const wr = std.io.getStdOut().writer();
    nosuspend wr.print(prefix ++ format ++ "\n", args) catch return;
}

const ztlog = std.log.scoped(.ztest);

pub fn main() !void {
    std.debug.print("Eat my ass\n", .{});
    const rc = c.SDL_Init(c.SDL_INIT_VIDEO);

    if (rc == -1) {
      ztlog.info("Bones! {}", .{c.SDL_GetError()});
      return;
    }
    defer c.SDL_Quit();

    _ = c.SDL_GL_SetAttribute(@intToEnum(c.SDL_GLattr, c.SDL_GL_CONTEXT_MAJOR_VERSION), 4);
    _ = c.SDL_GL_SetAttribute(@intToEnum(c.SDL_GLattr, c.SDL_GL_CONTEXT_MINOR_VERSION), 0);
    _ = c.SDL_GL_SetAttribute(@intToEnum(c.SDL_GLattr, c.SDL_GL_CONTEXT_PROFILE_MASK), c.SDL_GL_CONTEXT_PROFILE_CORE);

    const win = c.SDL_CreateWindow("Eat my ass", 0, 0, 400, 200, c.SDL_WINDOW_OPENGL);
    if (win == null) {
      ztlog.err("Could not create window {}", .{c.SDL_GetError()});
      return;
    }
    defer c.SDL_DestroyWindow(win);

    const ctx = c.SDL_GL_CreateContext(win);
    if (ctx == null) {
        ztlog.err("Could not create context: {}\n", .{c.SDL_GetError()});
    }
    defer c.SDL_GL_DeleteContext(ctx);

    var rend = RenderState{};
    try RenderState.init(&rend);

    st.setup();

    // create vertex buffer with triangle vertices
    const vertices = [_]f32 {
        // positions         colors
         0.0,  3,   3,     1.0, 0.0, 0.0, 1.0,
         3.0,  0,   3.0,     0.0, 1.0, 0.0, 1.0,
        -3.0,  0,   3.0,     0.0, 0.0, 1.0, 1.0
    };
    const tbuf = try rend.addBuffer(.{
        .buffer = sg.makeBuffer(.{
            .data = sg.asRange(vertices)
        }),
    });

    var drawables = [_]mr.Drawable{
        .{
            .buf = tbuf, 
            .pipeline = rend.pl_3d_color, 
            .base_element = 0, 
            .num_elements = 3
        },
    };

    const eyeheight = 2.0;
    var campos = Vec3.new(0, eyeheight, 0);
    var camrot: f32 = 0.0;
    var campitch: f32 = 0.0;
    var tickstate = tick.TickAccum.new();
    var tick_num: tick.T = 0;
    var frametime: u64 = 0;

    var ev: c.SDL_Event = undefined;
    var kmap = ctrl.ControlState.init(); 
    defer kmap.deinit();

    const mvspeed = 2.0;
    const rotspeed = 0.1;

    kmap.captureMouse();
    while (true) {
        const dTd = st.sec(st.laptime(&frametime));
        const dT = @floatCast(f32, dTd);
        var ticksReady = tickstate.numTicksReady(dTd);


        while (ticksReady > 0) {
            ticksReady -= 1;
            tick_num += 1;

            // Feed input to kmap
            kmap.beginFrame(tick_num);
            while (c.SDL_PollEvent(&ev) != 0) {
                if (ev.type == c.SDL_KEYDOWN or ev.type == c.SDL_KEYUP) {
                    switch (ev.key.keysym.sym) {
                        c.SDLK_ESCAPE => {
                            ztlog.info("ending tick={}, {}\n", .{tick_num, 
                                                                 tickstate});
                            return;
                        },

                        c.SDLK_a => {
                            kmap.press(.StrafeLeft, ev.type == c.SDL_KEYDOWN);
                        },

                        c.SDLK_d => {
                            kmap.press(.StrafeRight, ev.type == c.SDL_KEYDOWN);
                        },

                        c.SDLK_w => {
                            kmap.press(.Fwd, ev.type == c.SDL_KEYDOWN);
                        },

                        c.SDLK_s => {
                            kmap.press(.Back, ev.type == c.SDL_KEYDOWN);
                        },

                        else => break,
                    }
                }
            }

            // Act on input
            const mmove = kmap.getMouseMove();
            const pitch_range = std.math.pi * 0.5;

            camrot = camrot - mmove.x * rotspeed * tick.Length;
//          campitch = campitch - mmove.y * rotspeed * tick.Length;
//          campitch = std.math.max(-pitch_range,
//                                  std.math.min(pitch_range, campitch));
            var mv = Vec3.zero;

            if (kmap.isPressed(.StrafeLeft)) {
                mv.x -= 1;
            }
            if (kmap.isPressed(.StrafeRight)) {
                mv.x += 1;
            }
            if (kmap.isPressed(.Fwd)) {
                mv.z += 1;
            }
            if (kmap.isPressed(.Back)) {
                mv.z -= 1;
            }

            if (mv.length2() > 0) {
                const mrot = Mat4.createAngleAxis(Vec3.unitY, camrot);
                const mvdir = mv.transformDirection(mrot);
                campos = campos.add(mvdir.scale(mvspeed).scale(tick.Length));
            }
        }

        var w: c_int = 0;
        var h: c_int = 0;

        c.SDL_GetWindowSize(win, &w, &h);
        if (h > 0 and w > 0) {
            const aspect = @intToFloat(f32, w) / @intToFloat(f32, h);
            const camdir = getFwd(camrot, campitch);
            const look = Mat4.createLook(campos, camdir, Vec3.unitY);
            const pers = Mat4.createPerspective(zlm.toRadians(70.0), aspect, 0.1, 10.0);

            rend.ublock.mvp = look.mul(pers);
            rend.draw(w, h, drawables[0..]);
            c.SDL_GL_SwapWindow(win);
        }
    }
}

fn getFwd(camrot: f32, campitch: f32) Vec3 {
    const mpit = Mat4.createAngleAxis(Vec3.unitX, campitch);
    const mrot = Mat4.createAngleAxis(Vec3.unitY, camrot);
    return Vec3.unitZ.transformDirection(mpit).transformDirection(mrot);
}
