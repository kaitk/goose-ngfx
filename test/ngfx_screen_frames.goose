// The screen across frames, headless: a frame that clears it draws into
// another texture behind the same handles than the frame before, and a frame
// that doesn't clear sees what the last frame drew, color and depth alike.
import std;
import vec;
import os;
import ngfx from "../";

let W = 16;

struct Fill { color: float4, depth: f32 }

fn open_or_skip() -> bool {
    if ngfx::open_headless(W, W) { return true; }
    write_stderr(str("ngfx: ", ngfx::error(), "\n"));
    return false;
}

fn middle() -> u8[>..] {
    let px = ngfx::read_pixels(ngfx::screen());
    let i = (W / 2 * W + W / 2) * 4;
    str(px[i], ",", px[i + 1], ",", px[i + 2])
}

fn main() {
    guard open_or_skip() else { return; }
    let screen = ngfx::screen();
    let depth = ngfx::screen_depth();
    let fill_shader = ngfx::slang("""
        #include <NoGraphicsAPI/shader.slang>
        struct Fill { float4 color; float depth; };
        GPU_ROOT(Fill, root);
        [shader("vertex")]
        float4 fillVertex(uint vertex_id : SV_VertexID) : SV_Position {
            float2 p = float2((vertex_id << 1) & 2, vertex_id & 2);
            return float4(p * 2.0 - 1.0, root.depth, 1.0);
        }
        [shader("fragment")]
        float4 fillFragment() : SV_Target0 { return root.color; }
        """);
    let fill = ngfx::pipeline(fill_shader, ngfx::PipelineDesc { depth_test: true, depth_write: true });

    ngfx::frame();
    var d = ngfx::PassDesc { depth: ngfx::screen_depth(), color_value: float4 { 1.0, 0.0, 0.0, 1.0 },
                             depth_value: 0.25 };
    d.color[0] = ngfx::screen();
    ngfx::begin_pass(d);
    ngfx::end_pass();
    print("cleared red: ", middle());

    ngfx::frame();
    print("a frame later, with no pass: ", middle());

    // Loaded, not cleared: the last frame's depth hides what is behind it,
    // and not what is in front.
    ngfx::frame();
    d.clear_color = false;
    d.clear_depth = false;
    ngfx::begin_pass(d);
    ngfx::bind(fill);
    ngfx::draw(ngfx::root(Fill { color: float4 { 0.0, 1.0, 0.0, 1.0 }, depth: 0.5 }), 3);
    ngfx::end_pass();
    print("loaded, drawn behind the last frame's depth: ", middle());
    ngfx::begin_pass(d);
    ngfx::bind(fill);
    ngfx::draw(ngfx::root(Fill { color: float4 { 0.0, 0.0, 1.0, 1.0 }, depth: 0.1 }), 3);
    ngfx::end_pass();
    print("and in front of it: ", middle());

    for i in 3 {
        ngfx::frame();
        // No channel lands halfway between two bytes, as 0.5 does (127.5), which
        // Metal rounds up and NVIDIA's Vulkan down.
        let c = float4 { 0.0, (i + 1) * 0.2, 0.0, 1.0 };
        ngfx::begin_screen(c);
        ngfx::end_pass();
        print("frame ", i, " cleared: ", middle());
    }
    ngfx::frame();
    print("same handles: ", ngfx::screen().id == screen.id && ngfx::screen_depth().id == depth.id);
    ngfx::close();
}
