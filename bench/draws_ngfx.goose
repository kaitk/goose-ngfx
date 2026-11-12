// The draw-call benchmark on ngfx (task 001's subtask 03): N small quads a
// frame, each its own draw with its own root in frame memory, holding where
// the quad goes and its color. The shader fetches the quad's corners
// through the root's pointer. bench/draws_gfx.goose draws the same with gfx.
//
//   draws_ngfx --frames F --draws N [--indexed]
//
// bench/run_bench.py builds and times it; run alone, it prints what it drew.

import std;
import vec;
import math;
import os;
import ngfx from "../";
import gfx from "github.com/kaitk/goose_gfx@main";

// The draw's root, as the shader declares it: the corners, then the quad's
// offset and size in clip space, then its color.
struct Root { vertices: u64, pad0: u32, pad1: u32, place: float4, color: float4 }

fn main() {
    var frames = 100;
    var draws = 1000;
    var indexed = false;
    let argv = args();
    var a = 1;
    while a < argv.len {
        if argv[a] == "--indexed" { indexed = true; a++; continue; }
        guard a + 1 < argv.len else { abort("usage: draws_ngfx --frames F --draws N [--indexed]"); }
        let n, ok = parse_int(argv[a + 1]);
        guard ok && n > 0 else { abort("--frames and --draws take a positive count"); }
        if argv[a] == "--frames" { frames = n; }
        else if argv[a] == "--draws" { draws = n; }
        else { abort("usage: draws_ngfx --frames F --draws N [--indexed]"); }
        a += 2;
    }
    guard gfx::open("ngfx draws", 1280, 800, gfx::WINDOW_RESIZABLE | gfx::WINDOW_ONLY) else {
        abort(str("gfx: ", gfx::error()));
    }
    let window = gfx::screen_size();
    guard ngfx::open(gfx::native_window(), window.x, window.y, 0) else {
        abort(str("ngfx: ", ngfx::error()));
    }

    // A unit quad: four corners for the indexed draws, two triangles of
    // them for the others.
    let corners: float2[4] = [float2 { 0.0, 0.0 }, float2 { 1.0, 0.0 }, float2 { 1.0, 1.0 },
                              float2 { 0.0, 1.0 }];
    let order: u16[6] = [0, 1, 2, 0, 2, 3];
    var verts: float2[>..] = [];
    if indexed { for c in corners { verts.push(c); } }
    else { for i in order { verts.push(corners[i]); } }
    let vertex_buffer = ngfx::buffer(bytes_of(verts));
    let index_buffer = ngfx::buffer(bytes_of(order));
    let indices = ngfx::range(index_buffer);
    let quad_shader = ngfx::slang("""
        #include <NoGraphicsAPI/shader.slang>

        struct Root { float2* vertices; float4 place; float4 color; };
        GPU_ROOT(Root, root);

        struct Varyings {
            float4 position : SV_Position;
            float4 color : COLOR;
        };

        [shader("vertex")]
        Varyings vertexMain(uint vertex_id : SV_VertexID) {
            float2 p = root.place.xy + root.vertices[vertex_id] * root.place.zw;
            Varyings o;
            o.position = float4(p, 0.0, 1.0);
            o.color = root.color;
            return o;
        }

        [shader("fragment")]
        float4 fragmentMain(Varyings i) : SV_Target0 { return i.color; }
        """);
    let quad_pipeline = ngfx::pipeline(quad_shader);
    ngfx::prepare_screen(quad_pipeline);

    // The quads fill a grid over the screen, a cell each.
    var side = 1;
    while side * side < draws { side++; }
    let cell: f32 = 2.0 / side;
    let address = ngfx::address(vertex_buffer);
    var drawn = 0;
    while gfx::frame() {
        ngfx::resize(gfx::screen_size());
        let shift = (drawn % 60) / 60.0;
        ngfx::begin_screen(float4 { 0.05, 0.05, 20.0 / 255.0, 1.0 });
        ngfx::bind(quad_pipeline);
        for i in draws {
            let x = i % side;
            let y = i / side;
            let root = ngfx::root(Root {
                vertices: address,
                place: float4 { x * cell - 1.0, y * cell - 1.0, cell * 0.8, cell * 0.8 },
                color: float4 { x / side, y / side, shift, 1.0 }, .. });
            if indexed { ngfx::draw_indexed(root, indices, 2, 6); }
            else { ngfx::draw(root, 6); }
        }
        ngfx::end_pass();
        gfx::presented(ngfx::present());
        drawn++;
        if drawn == frames { break; }
    }

    // Headless, read back, which waits for the GPU, and count the pixels the
    // quads cover: the background's blue is 20. A window's screen is its
    // image, which can't be read.
    var covered = -1;
    if gfx::native_window() == 0 {
        let px = ngfx::read_pixels(ngfx::screen());
        covered = 0;
        for i in px.len / 4 { if px[i * 4 + 2] != 20 { covered++; } }
    }
    print("drew ", drawn, " frames of ", draws, if indexed { " indexed" } else { "" }, " draws",
          if covered >= 0 { str(", covering ", covered, " pixels") } else { "" });
    ngfx::close();
    gfx::close();
}
