// The draw-call benchmark on Goose's gfx, against bench/draws_ngfx.goose: N
// small quads a frame, each its own draw after a uniform push of where the
// quad goes and its color. The corners come from a bound vertex buffer.
//
//   draws_gfx --frames F --draws N [--indexed]
//
// bench/run_bench.py builds and times it; run alone, it prints what it drew.

import std;
import vec;
import math;
import os;
import gfx;

// The vertex shader's uniform block: the quad's offset and size in clip
// space, then its color. std140 lays two vec4s out with no padding.
struct Quad { place: float4, color: float4 }

fn main() {
    var frames = 100;
    var draws = 1000;
    var indexed = false;
    let argv = args();
    var a = 1;
    while a < argv.len {
        if argv[a] == "--indexed" { indexed = true; a++; continue; }
        guard a + 1 < argv.len else { abort("usage: draws_gfx --frames F --draws N [--indexed]"); }
        let n, ok = parse_int(argv[a + 1]);
        guard ok && n > 0 else { abort("--frames and --draws take a positive count"); }
        if argv[a] == "--frames" { frames = n; }
        else if argv[a] == "--draws" { draws = n; }
        else { abort("usage: draws_gfx --frames F --draws N [--indexed]"); }
        a += 2;
    }
    guard gfx::open("gfx draws", 1280, 800, gfx::WINDOW_RESIZABLE) else {
        abort(str("gfx: ", gfx::error()));
    }

    // A unit quad: four corners for the indexed draws, two triangles of
    // them for the others.
    let corners: float2[4] = [float2 { 0.0, 0.0 }, float2 { 1.0, 0.0 }, float2 { 1.0, 1.0 },
                              float2 { 0.0, 1.0 }];
    let order: u16[6] = [0, 1, 2, 0, 2, 3];
    var verts: float2[>..] = [];
    if indexed { for c in corners { verts.push(c); } }
    else { for i in order { verts.push(corners[i]); } }
    let vertex_buffer = gfx::vertex_buffer(bytes_of(verts));
    let index_buffer = gfx::index_buffer(bytes_of(order));
    let quad_vs = embed_shader("vert", """
        layout(location = 0) in vec2 a_pos;
        layout(set = 1, binding = 0) uniform Quad {
            vec4 place;
            vec4 color;
        };
        layout(location = 0) out vec4 v_color;
        void main() {
            v_color = color;
            gl_Position = vec4(place.xy + a_pos * place.zw, 0.0, 1.0);
        }
        """);
    let quad_fs = embed_shader("frag", """
        layout(location = 0) in vec4 v_color;
        layout(location = 0) out vec4 result;
        void main() { result = v_color; }
        """);
    let quad_pipeline = gfx::pipeline(quad_vs, quad_fs);

    // The quads fill a grid over the screen, a cell each.
    var side = 1;
    while side * side < draws { side++; }
    let cell: f32 = 2.0 / side;
    var drawn = 0;
    while gfx::frame() {
        let shift = (drawn % 60) / 60.0;
        gfx::begin_screen(float4 { 0.05, 0.05, 20.0 / 255.0, 1.0 });
        gfx::bind(quad_pipeline);
        gfx::bind_vertex_buffer(vertex_buffer);
        if indexed { gfx::bind_index_buffer(index_buffer, 2); }
        for i in draws {
            let x = i % side;
            let y = i / side;
            gfx::uniforms(gfx::VERTEX, 0, Quad {
                place: float4 { x * cell - 1.0, y * cell - 1.0, cell * 0.8, cell * 0.8 },
                color: float4 { x / side, y / side, shift, 1.0 } });
            if indexed { gfx::draw_indexed(6); }
            else { gfx::draw(6); }
        }
        gfx::end_pass();
        drawn++;
        if drawn == frames { break; }
    }

    // Read back, which waits for the GPU, and count the pixels the quads
    // cover: the background's blue is 20.
    let px = gfx::read_pixels(gfx::screen());
    var covered = 0;
    for i in px.len / 4 { if px[i * 4 + 2] != 20 { covered++; } }
    print("drew ", drawn, " frames of ", draws, if indexed { " indexed" } else { "" },
          " draws, covering ", covered, " pixels");
    gfx::close();
}
