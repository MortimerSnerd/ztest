// All of the rendering code that's dealing directly with sokol.
const std = @import("std");
const sg = @import("sokol").gfx;
const zlm = @import("zlm");
const Mat4 = zlm.Mat4;
const Simd = std.meta.Vector;
const StaticArray = @import("utils.zig").StaticArray;

//TODO does it make sense to have math functions that act on a slice + index
//     so we can perform operations on our arrays of floats that are packed so 
//     you can't just use Vec3, etc...?

//TODO renderer structure - have numeric ids for textures and bindings, 
//     and have a struct Drawable that bundles up these ids so the 
//     renderer can collect and deal with them, so all the rest of
//     the code for the view etc just needs to feed the renderer.

const rlog = std.log.scoped(.render);

pub const RenderErr = error {
    SokolNotInitialized,
    BadBackend,
};

pub const BufIx = u16;
pub const PipeIx = u16;

pub const Drawable = struct {
    /// Index for the pipeline.
    pipeline: PipeIx,

    /// Index of buffer information to use.  A subset of 
    /// what's in Bindings with only the pieces we need.
    buf: BufIx,

    //TODO need something to optionally mod uniforms?

    /// Essentially the parameters to sg.Draw()
    base_element: i32,
    num_elements: i32, 
    num_instances: i32 = 1,
};

// Minimal binding info used to fill out sg.Bindings
// when rendering.
pub const SimpleBinding = struct {
    buffer: sg.Buffer = .{},
    idx_buffer: sg.Buffer = .{},
    tx0: sg.Image = .{},

    // Assumes `bnd` has only had fields filled out from SimpleBinding.
    pub fn updateBinding(s: SimpleBinding, bnd: *sg.Bindings) void {
        bnd.vertex_buffers[0] = s.buffer;
        bnd.index_buffer = s.idx_buffer;
        bnd.fs_images[0] = s.tx0;
    }
};

pub const UniformBlock = packed struct {
    mvp: Mat4,
};

// Arbitrary, no deep thought here.
const MaxPipelines = 64;
const MaxBuffers   = 128;
const MaxDrawables = 1024;

pub const RenderState = struct {
    const PipelineArray = StaticArray(sg.Pipeline, MaxPipelines);
    const BufferArray = StaticArray(SimpleBinding, MaxBuffers);

    pipelines: PipelineArray = PipelineArray.init(),
    buffers: BufferArray = BufferArray.init(),

    // Index for common pipeline for rendering solid colors in 3d.
    pl_3d_color: PipeIx = undefined,

    // Pipeline for 3d textured geometry with normals.
    pl_v_tx_n: PipeIx = undefined,

    // Solid color shader.
    colorShader: sg.Shader = undefined,

    ublock: UniformBlock = .{
        .mvp = Mat4.identity,
    },

    /// Initializes a default RenderState struct in place. 
    /// Because we're using StaticArray, we need to be sure to 
    /// construct the struct in place and not copy it, so the 
    /// StaticArray slices won't be invalidated. 
    pub fn init(rv: *RenderState) !void {
        const gfxdesc = sg.Desc{
            .context = .{
                .color_format = @enumToInt(sg.PixelFormat.RGBA8),
                .depth_format = @enumToInt(sg.PixelFormat.DEPTH),
                .sample_count = 1,
            },
        };

        sg.setup(gfxdesc);
        if (!sg.isvalid()) {
            rlog.err("Failed to init sokol device?", .{});
            return RenderErr.SokolNotInitialized;
        }

        const desc = try colorShaderDesc();
        rv.colorShader = sg.makeShader(desc);

        var p1desc = sg.PipelineDesc{
            .shader = rv.colorShader, 
            .depth_stencil = .{
                .depth_compare_func = .LESS_EQUAL,
                .depth_write_enabled = true,
            },
            .rasterizer = .{
                .cull_mode = .BACK,
            },
        };
        p1desc.layout.attrs[0].format = .FLOAT3;
        p1desc.layout.attrs[1].format = .FLOAT4;
        rv.pl_3d_color = try rv.addPipeline(p1desc);
        rv.pl_v_tx_n = try rv.addVTxNPipeline();
    }

    pub fn addVTxNPipeline(s: *RenderState) !PipeIx {
        const vs = 
            \\ #version 330
            \\ uniform mat4 mvp;
            \\ layout(location = 0) in vec3 position;
            \\ layout(location = 1) in vec3 normal;
            \\ layout(location = 2) in vec2 tc;
            \\ out vec2 uv;
            \\ out vec4 ncolor;
            \\
            \\ void main() {
            \\   gl_Position = mvp * vec4(position, 1);
            \\   uv = tc;
            \\   ncolor = vec4(1, 1, 1, 1) * max(0.3, dot(normal, vec3(0, 0.707, 0.707)));
            \\ }
            ;
        const fs = 
            \\ #version 330
            \\ uniform sampler2D tex;
            \\ in vec2 uv;
            \\ in vec4 ncolor;
            \\ out vec4 frag_color;
            \\ void main() {
            \\   frag_color = texture2D(tex, uv) * ncolor;
            \\ }
            ;

        var desc = try mkShaderDesc(vs, fs);

        desc.fs.images[0].type = ._2D;
        desc.fs.images[0].name = "tex";
        setStdUniforms(&desc);
        const shd = sg.makeShader(desc);

        var d = sg.PipelineDesc{
            .shader = shd, 
            .index_type = .UINT16,
            .depth_stencil = .{
                .depth_compare_func = .LESS_EQUAL,
                .depth_write_enabled = true,
            },
            .rasterizer = .{
                .cull_mode = .BACK,
            },
        };
        d.layout.attrs[0].format = .FLOAT3;
        d.layout.attrs[1].format = .FLOAT3;
        d.layout.attrs[2].format = .FLOAT2;

        return s.addPipeline(d);
    }

    pub fn addPipeline(s: *RenderState, pd: sg.PipelineDesc) !PipeIx {
        const rv = s.pipelines.items.len;
        const pip = sg.makePipeline(pd);
        try s.pipelines.push(pip);
        return @truncate(PipeIx, rv);
    }

    pub fn addBuffer(s: *RenderState, b: SimpleBinding) !BufIx {
        const rv = s.buffers.items.len;
        try s.buffers.push(b);
        return @truncate(BufIx, rv);
    }

    // lessThan function for std.sort that groups drawables in a way
    // that's appropriate for doing the least state changes for sokol.
    // Higher level groupings, like for transparencies need to be handled
    // at a higher level.
    fn drawableGrouping(comptime context: comptime_int, lhs: Drawable, rhs: Drawable) bool {
        return lhs.pipeline < rhs.pipeline or lhs.buf < rhs.buf;
    }

    pub fn draw(s: RenderState, w: i32, h: i32, items: []Drawable) void {
        if (items.len > 0) {
            var lastpipe: ?PipeIx = null;
            var lastbuf: ?BufIx = null;
            var bindings = sg.Bindings{};
            var updunis = false;

            std.sort.sort(Drawable, items, 0, drawableGrouping);
            sg.beginDefaultPass(.{}, w, h);
            for (items) |d| {
                if (lastpipe == null or lastpipe.? != d.pipeline) {
                    sg.applyPipeline(s.pipelines.items[d.pipeline]);
                    lastpipe = d.pipeline;
                    updunis = true;
                }

                if (lastbuf == null or lastbuf.? != d.buf) {
                    s.buffers.items[d.buf].updateBinding(&bindings);
                    sg.applyBindings(bindings);
                    lastbuf = d.buf;
                }
                if (updunis) {
                    sg.applyUniforms(.VS, 0, sg.asRange(s.ublock));
                }

                sg.draw(d.base_element, d.num_elements, d.num_instances);
            }
            sg.endPass();
            sg.commit();
        }
    }
};

fn colorShaderDesc() !sg.ShaderDesc {
    const vs = 
        \\ #version 330
        \\ uniform mat4 mvp;
        \\ in vec4 position;
        \\ in vec4 color0;
        \\ out vec4 color;
        \\ void main() {
        \\   gl_Position = mvp * position;
        \\   color = color0;
        \\ }
        ;
    const fs = 
        \\ #version 330
        \\ in vec4 color;
        \\ out vec4 frag_color;
        \\ void main() {
        \\   frag_color = color;
        \\ }
        ;

    var desc = try mkShaderDesc(vs, fs);

    desc.attrs[0].name = "position";
    desc.attrs[1].name = "color0";
    setStdUniforms(&desc);
    return desc;
}

fn setStdUniforms(desc: *sg.ShaderDesc) void {
    desc.vs.uniform_blocks[0].size = @sizeOf(UniformBlock);
    desc.vs.uniform_blocks[0].uniforms[0] = .{ .name = "mvp", 
                                               .type = .MAT4 };
}

// build a backend-specific ShaderDesc struct
fn mkShaderDesc(vs: [*c]const u8, fs: [*c]const u8) !sg.ShaderDesc {
    var desc: sg.ShaderDesc = .{};
    const be = sg.queryBackend();

    switch (be) {
        .GLCORE33 => {
            desc.vs.source = vs;
            desc.fs.source = fs;
        },
        else => {
            rlog.err("Unexpected backend: {}", .{be});
            return RenderErr.BadBackend;
        },
    }
    return desc;
}

