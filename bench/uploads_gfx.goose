// The upload benchmark on Goose's gfx, against bench/uploads_ngfx.goose: K
// times a frame, it updates a 64 KB buffer and a 256 x 256 RGBA8 texture,
// then draws a quad from the buffer's first six vertices, sampling the
// texture. Each update is a copy pass that the next draw sees.
//
//   uploads_gfx --frames F --updates K
//
// bench/run_bench.py builds and times it; run alone, it prints what it drew.

import std;
import vec;
import math;
import os;
import gfx;

struct Vertex { pos: float2, uv: float2 }

let SIDE = 256;
let ENTRIES = 4096;     // 64 KB of Vertex

fn main() {
    var frames = 100;
    var updates = 1;
    let argv = args();
    var a = 1;
    while a + 1 < argv.len {
        let n, ok = parse_int(argv[a + 1]);
        guard ok && n > 0 else { abort("--frames and --updates take a positive count"); }
        if argv[a] == "--frames" { frames = n; }
        else if argv[a] == "--updates" { updates = n; }
        else { abort("usage: uploads_gfx --frames F --updates K"); }
        a += 2;
    }
    guard gfx::open("gfx uploads", 1280, 800, gfx::WINDOW_RESIZABLE) else {
        abort(str("gfx: ", gfx::error()));
    }

    // Update k's data: its quad's corners in a 4 x 4 grid, and a texture of
    // one color with a lighter border.
    var vertex_data: Vertex[>..] = [];
    var pixel_data: u8[>..] = [];
    let corners: float2[6] = [float2 { 0.0, 0.0 }, float2 { 1.0, 0.0 }, float2 { 1.0, 1.0 },
                              float2 { 0.0, 0.0 }, float2 { 1.0, 1.0 }, float2 { 0.0, 1.0 }];
    for k in updates {
        let at = float2 { (k % 4) * 0.5 - 1.0, ((k / 4) % 4) * 0.5 - 1.0 };
        for i in ENTRIES {
            let c = corners[i % 6];
            vertex_data.push(Vertex { pos: at + c * float2 { 0.45, 0.45 }, uv: c });
        }
        for y in SIDE {
            for x in SIDE {
                let edge = x < 8 || y < 8 || x >= SIDE - 8 || y >= SIDE - 8;
                let base: u8 = if edge { 200 } else { 60 };
                pixel_data.append([base + (k * 3) as u8, base, base + 40, 255]);
            }
        }
    }
    let buffer = gfx::buffer(gfx::BUFFER_VERTEX, ENTRIES * 16, []);
    let texture = gfx::texture2d(SIDE, SIDE);
    let sampler = gfx::sampler(gfx::NEAREST, gfx::CLAMP);
    let quad_vs = embed_shader("vert", """
        layout(location = 0) in vec2 a_pos;
        layout(location = 1) in vec2 a_uv;
        layout(location = 0) out vec2 v_uv;
        void main() {
            v_uv = a_uv;
            gl_Position = vec4(a_pos, 0.0, 1.0);
        }
        """);
    let quad_fs = embed_shader("frag", """
        layout(location = 0) in vec2 v_uv;
        layout(set = 2, binding = 0) uniform sampler2D image;
        layout(location = 0) out vec4 result;
        void main() { result = texture(image, v_uv); }
        """);
    let quad_pipeline = gfx::pipeline(quad_vs, quad_fs);
    let vertex_bytes = bytes_of(vertex_data);
    let update_bytes = ENTRIES * 16;
    let pixel_bytes = SIDE * SIDE * 4;
    // Each update's quad goes over what the frame drew so far.
    var load = gfx::PassDesc { clear_color: false, .. };
    load.color[0] = gfx::screen();

    var drawn = 0;
    while gfx::frame() {
        gfx::begin_screen(float4 { 0.05, 0.05, 20.0 / 255.0, 1.0 });
        gfx::end_pass();
        for k in updates {
            gfx::update_buffer(buffer, vertex_bytes[k * update_bytes..(k + 1) * update_bytes]);
            gfx::update_texture(texture, pixel_data[k * pixel_bytes..(k + 1) * pixel_bytes]);
            gfx::begin_pass(load);
            gfx::bind(quad_pipeline);
            gfx::bind_vertex_buffer(buffer);
            gfx::bind_texture(gfx::FRAGMENT, 0, texture, sampler);
            gfx::draw(6);
            gfx::end_pass();
        }
        drawn++;
        if drawn == frames { break; }
    }

    // Read back, which waits for the GPU, and count the pixels the quads
    // cover: the background's blue is 20.
    let px = gfx::read_pixels(gfx::screen());
    var covered = 0;
    for i in px.len / 4 { if px[i * 4 + 2] != 20 { covered++; } }
    print("drew ", drawn, " frames of ", updates, " updates, covering ", covered, " pixels");
    gfx::close();
}
