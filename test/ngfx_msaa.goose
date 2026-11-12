// 4x multisampling, headless: a pass draws into TRANSIENT 4x color and depth
// targets and resolves the color into a texture of one sample. A quad whose
// right edge crosses pixel 2 at its middle covers two of that pixel's four
// sample positions (the standard ones, at x 0.125, 0.375, 0.625, 0.875), so
// it resolves to half the quad's color, and the pixels either side to all
// or none. The quad's 0.8 halves to 102 exactly, where 1.0 would land on
// 127.5, which GPUs round either way.
import std;
import vec;
import os;
import ngfx from "../";

let W = 8;
let H = 2;

fn open_or_skip() -> bool {
    if ngfx::open_headless(W, H) { return true; }
    write_stderr(str("ngfx: ", ngfx::error(), "\n"));
    return false;
}

fn main() {
    guard open_or_skip() else { return; }
    let shader = ngfx::slang("""
        #include <NoGraphicsAPI/shader.slang>
        // A quad over x in [-1, -0.375]: its right edge is 2.5 pixels in.
        [shader("vertex")]
        float4 quadVertex(uint vertex_id : SV_VertexID) : SV_Position {
            uint corner = vertex_id < 3 ? vertex_id : 6 - vertex_id;
            return float4((corner & 1) != 0 ? -0.375 : -1.0, (corner & 2) != 0 ? 1.0 : -1.0, 0.5, 1.0);
        }
        [shader("fragment")]
        float4 quadFragment() : SV_Target0 { return float4(0.8, 0.8, 0.8, 1.0); }
        """);
    let quad = ngfx::pipeline(shader, ngfx::PipelineDesc { depth_test: true, depth_write: true });
    let color = ngfx::texture(ngfx::TextureDesc { usage: ngfx::COLOR_TARGET | ngfx::TRANSIENT, width: W,
                                                  height: H, samples: 4 });
    let depth = ngfx::texture(ngfx::TextureDesc { format: ngfx::DEPTH, usage: ngfx::DEPTH_TARGET | ngfx::TRANSIENT,
                                                  width: W, height: H, samples: 4 });
    let image = ngfx::texture2d(W, H, ngfx::RGBA8, ngfx::COLOR_TARGET | ngfx::SAMPLED);

    var d = ngfx::PassDesc { depth: depth, color_value: float4 { 0.0, 0.0, 0.0, 1.0 } };
    d.color[0] = color;
    d.resolve[0] = image;
    ngfx::begin_pass(d);
    ngfx::bind(quad);
    ngfx::draw(0, 6);
    ngfx::end_pass();

    let px = ngfx::read_pixels(image);
    for y in H {
        var row: u8[>..] = [];
        for x in W { format(row, px[(y * W + x) * 4], " "); }
        print("row ", y, ": ", row);
    }
    print("info: samples ", ngfx::texture_info(color).samples, ", usage ", ngfx::texture_info(depth).usage);
    ngfx::close();
}
