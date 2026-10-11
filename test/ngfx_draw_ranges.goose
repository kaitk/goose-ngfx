// Indexed draws whose indices are a Range, headless: from this frame's
// memory (frame_range), from part of it (first_index), and from a buffer's
// range, the same as from the buffer.
import std;
import vec;
import os;
import ngfx from "../";

let W = 16;

struct Quads { corners: u64, color: float4 }

fn open_or_skip() -> bool {
    if ngfx::open_headless(W, W) { return true; }
    write_stderr(str("ngfx: ", ngfx::error(), "\n"));
    return false;
}

// How many pixels of the screen are white, and whether the top left and
// bottom right corners are.
fn white() -> u8[>..] {
    let px = ngfx::read_pixels(ngfx::screen());
    var n = 0;
    for i in W * W { if px[i * 4] == 255 && px[i * 4 + 1] == 255 { n++; } }
    let last = (W * W - 1) * 4;
    str(n, " white, top left ", px[0] == 255, ", bottom right ", px[last] == 255)
}

fn main() {
    guard open_or_skip() else { return; }
    // Two quads' corners: the left half of the screen, then the right half.
    let corners: float2[8] = [
        float2 { -1.0, -1.0 }, float2 { 0.0, -1.0 }, float2 { 0.0, 1.0 }, float2 { -1.0, 1.0 },
        float2 { 0.0, -1.0 }, float2 { 1.0, -1.0 }, float2 { 1.0, 1.0 }, float2 { 0.0, 1.0 },
    ];
    let indices: u32[12] = [0, 1, 2, 0, 2, 3, 4, 5, 6, 4, 6, 7];
    let corner_buffer = ngfx::buffer(bytes_of(corners));
    let index_buffer = ngfx::buffer(bytes_of(indices));
    let quad_shader = ngfx::slang("""
        #include <NoGraphicsAPI/shader.slang>
        struct Quads { float2* corners; float4 color; };
        GPU_ROOT(Quads, root);
        [shader("vertex")]
        float4 quadVertex(uint vertex_id : SV_VertexID) : SV_Position {
            return float4(root.corners[vertex_id], 0.0, 1.0);
        }
        [shader("fragment")]
        float4 quadFragment() : SV_Target0 { return root.color; }
        """);
    let quads = ngfx::pipeline(quad_shader);
    let root = ngfx::root(Quads { corners: ngfx::address(corner_buffer),
                                  color: float4 { 1.0, 1.0, 1.0, 1.0 } });

    let in_frame = ngfx::frame_range(bytes_of(indices));
    print("frame_range: ", in_frame.size, " bytes, aligned ", in_frame.address % 16 == 0);
    ngfx::begin_screen(float4 { 0.0, 0.0, 0.0, 1.0 });
    ngfx::bind(quads);
    ngfx::draw_indexed(root, in_frame, 4, 12);
    ngfx::end_pass();
    print("both quads from frame memory: ", white());

    ngfx::frame();
    let root2 = ngfx::root(Quads { corners: ngfx::address(corner_buffer),
                                   color: float4 { 1.0, 1.0, 1.0, 1.0 } });
    ngfx::begin_screen(float4 { 0.0, 0.0, 0.0, 1.0 });
    ngfx::bind(quads);
    ngfx::draw_indexed(root2, ngfx::frame_range(bytes_of(indices)), 4, 6, 1, 6, 0, 0);
    ngfx::end_pass();
    print("the second quad, from index 6: ", white());

    let range = ngfx::range(index_buffer);
    print("a buffer's range: ", range.size, " bytes at its address ",
          range.address == ngfx::address(index_buffer));
    ngfx::begin_screen(float4 { 0.0, 0.0, 0.0, 1.0 });
    ngfx::bind(quads);
    ngfx::draw_indexed(root2, range, 4, 6);
    ngfx::end_pass();
    let from_range = white();
    ngfx::begin_screen(float4 { 0.0, 0.0, 0.0, 1.0 });
    ngfx::bind(quads);
    ngfx::draw_indexed(root2, index_buffer, 4, 6);
    ngfx::end_pass();
    print("the first quad, from the range: ", from_range, "; the same from the buffer: ",
          white() == from_range);
    ngfx::close();
}
