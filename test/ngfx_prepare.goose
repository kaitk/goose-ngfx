// Pipelines prepared before their first draw, headless: one prepared for
// the screen and an offscreen target, one made lazily at its first draw,
// drawing the same.
import std;
import vec;
import os;
import ngfx from "../";

let W = 16;

struct Fill { color: float4 }

fn open_or_skip() -> bool {
    if ngfx::open_headless(W, W) { return true; }
    write_stderr(str("ngfx: ", ngfx::error(), "\n"));
    return false;
}

fn middle(t: ngfx::Texture) -> u8[>..] {
    let px = ngfx::read_pixels(t);
    let i = (W / 2 * W + W / 2) * 4;
    str(px[i], ",", px[i + 1], ",", px[i + 2])
}

fn fill(p: ngfx::Pipeline, target: ngfx::Texture, depth: ngfx::Texture, color: float4) -> u8[>..] {
    ngfx::begin_pass(target, depth, float4 { 0.0, 0.0, 0.0, 1.0 });
    ngfx::bind(p);
    ngfx::draw(ngfx::root(Fill { color: color }), 3);
    ngfx::end_pass();
    middle(target)
}

fn main() {
    guard open_or_skip() else { return; }
    let fill_shader = ngfx::slang("""
        #include <NoGraphicsAPI/shader.slang>
        struct Fill { float4 color; };
        GPU_ROOT(Fill, root);
        [shader("vertex")]
        float4 fillVertex(uint vertex_id : SV_VertexID) : SV_Position {
            float2 p = float2((vertex_id << 1) & 2, vertex_id & 2);
            return float4(p * 2.0 - 1.0, 0.5, 1.0);
        }
        [shader("fragment")]
        float4 fillFragment() : SV_Target0 { return root.color; }
        """);
    let desc = ngfx::PipelineDesc { depth_test: true, depth_write: true };
    let prepared = ngfx::pipeline(fill_shader, desc);
    let lazy = ngfx::pipeline(fill_shader, desc);
    let target = ngfx::texture2d(W, W, ngfx::RGBA8, ngfx::SAMPLED | ngfx::COLOR_TARGET);
    print("prepared for the screen: ", ngfx::prepare_screen(prepared));
    print("prepared for a target without depth: ",
          ngfx::prepare(prepared, target, ngfx::Texture { 0 }));
    print("prepared again: ", ngfx::prepare_screen(prepared));

    let screen = ngfx::screen();
    let depth = ngfx::screen_depth();
    print("screen, prepared: ", fill(prepared, screen, depth, float4 { 1.0, 0.0, 0.0, 1.0 }));
    print("screen, lazy: ", fill(lazy, screen, depth, float4 { 0.0, 1.0, 0.0, 1.0 }));
    print("target, prepared: ", fill(prepared, target, ngfx::Texture { 0 },
                                     float4 { 0.0, 0.0, 1.0, 1.0 }));
    print("target, lazy: ", fill(lazy, target, ngfx::Texture { 0 }, float4 { 1.0, 1.0, 0.0, 1.0 }));
    ngfx::close();
}
