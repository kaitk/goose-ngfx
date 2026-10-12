// The upload benchmark on ngfx (task 001's subtask 03): K times a frame, it
// updates a 64 KB buffer and a 256 x 256 RGBA8 texture, then draws a quad
// whose corners are the buffer's first six entries, sampling the texture.
// ngfx's update_buffer and update_texture take effect for the whole frame,
// so each update after the first overlaps the last and flushes a batch.
// bench/uploads_gfx.goose does the same with gfx.
//
//   uploads_ngfx --frames F --updates K
//
// bench/run_bench.py builds and times it; run alone, it prints what it drew.

import std;
import vec;
import math;
import os;
import ngfx from "../";

struct Vertex { pos: float2, uv: float2 }
struct Root { vertices: u64, texture: u32, sampler: u32 }

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
        else { abort("usage: uploads_ngfx --frames F --updates K"); }
        a += 2;
    }
    guard ngfx::open("ngfx uploads", 1280, 800, ngfx::WINDOW_RESIZABLE) else {
        abort(str("ngfx: ", ngfx::error()));
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
    let buffer = ngfx::buffer(ENTRIES * 16, []);
    let texture = ngfx::texture2d(SIDE, SIDE);
    let sampler = ngfx::sampler(ngfx::NEAREST, ngfx::CLAMP);
    let quad_shader = ngfx::slang("""
        #include <NoGraphicsAPI/shader.slang>

        struct Vertex { float2 pos; float2 uv; };
        struct Root { Vertex* vertices; uint texture; uint sampler; };
        GPU_ROOT(Root, root);

        struct Varyings {
            float4 position : SV_Position;
            float2 uv : TEXCOORD0;
        };

        [shader("vertex")]
        Varyings vertexMain(uint vertex_id : SV_VertexID) {
            Vertex v = root.vertices[vertex_id];
            Varyings o;
            o.position = float4(v.pos, 0.0, 1.0);
            o.uv = v.uv;
            return o;
        }

        [shader("fragment")]
        float4 fragmentMain(Varyings i) : SV_Target0 {
            Texture2D<float4> texture = gpu_texture<Texture2D<float4>>(root.texture);
            return texture.Sample(gpu_sampler(root.sampler), i.uv);
        }
        """);
    let quad_pipeline = ngfx::pipeline(quad_shader);
    ngfx::prepare_screen(quad_pipeline);
    let root = ngfx::root(Root { vertices: ngfx::address(buffer), texture: ngfx::index(texture),
                                 sampler: ngfx::index(sampler) });
    let vertex_bytes = bytes_of(vertex_data);
    let update_bytes = ENTRIES * 16;
    let pixel_bytes = SIDE * SIDE * 4;
    // Each update's quad goes over what the frame drew so far.
    var load = ngfx::PassDesc { clear_color: false, .. };
    load.color[0] = ngfx::screen();

    var drawn = 0;
    while ngfx::frame() {
        ngfx::begin_screen(float4 { 0.05, 0.05, 20.0 / 255.0, 1.0 });
        ngfx::end_pass();
        for k in updates {
            ngfx::update_buffer(buffer, vertex_bytes[k * update_bytes..(k + 1) * update_bytes]);
            ngfx::update_texture(texture, pixel_data[k * pixel_bytes..(k + 1) * pixel_bytes]);
            ngfx::begin_pass(load);
            ngfx::bind(quad_pipeline);
            ngfx::draw(root, 6);
            ngfx::end_pass();
        }
        drawn++;
        if drawn == frames { break; }
    }

    // Read back, which waits for the GPU, and count the pixels the quads
    // cover: the background's blue is 20.
    let px = ngfx::read_pixels(ngfx::screen());
    var covered = 0;
    for i in px.len / 4 { if px[i * 4 + 2] != 20 { covered++; } }
    print("drew ", drawn, " frames of ", updates, " updates, covering ", covered, " pixels");
    ngfx::close();
}
