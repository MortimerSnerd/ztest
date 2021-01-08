const std = @import("std");
const c = @cImport(@cInclude("SDL2/SDL.h"));

pub fn main() void {
  std.debug.print("Eat my ass\n", .{});
  const rc = c.SDL_Init(c.SDL_INIT_VIDEO);

  if (rc == -1) {
    std.debug.print("Bones!", .{});
    return;
  }
  defer c.SDL_Quit();

  _ = c.SDL_GL_SetAttribute(@intToEnum(c.SDL_GLattr, c.SDL_GL_CONTEXT_MAJOR_VERSION), 3);
  _ = c.SDL_GL_SetAttribute(@intToEnum(c.SDL_GLattr, c.SDL_GL_CONTEXT_MINOR_VERSION), 0);
  _ = c.SDL_GL_SetAttribute(@intToEnum(c.SDL_GLattr, c.SDL_GL_CONTEXT_PROFILE_MASK), c.SDL_GL_CONTEXT_PROFILE_CORE);

  const win = c.SDL_CreateWindow("Eat my ass", 0, 0, 320, 200, c.SDL_WINDOW_OPENGL);
  if (win == null) {
    std.debug.print("Could not create window {}", .{c.SDL_GetError()});
    return;
  }
  defer c.SDL_DestroyWindow(win);
}
