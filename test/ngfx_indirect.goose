// Indirect draws and dispatch, headless: a dispatch writes the arguments,
// and behind a barrier(COMPUTE_WRITE, STAGE_INDIRECT | ACCESS_INDIRECT_READ)
// draw_indirect draws the screen's left half, draw_indexed_indirect its right
// half, and dispatch_indirect runs as many groups as the dispatch said.
import std;
import vec;
import os;
import ngfx from "../";

let W = 16;

struct Args { draw: u64, indexed: u64, groups: u64 }
struct Quad { corners: u64, color: float4 }
struct Count { counter: u64 }

fn open_or_skip() -> bool {
    if ngfx::open_headless(W, W) { return true; }
    write_stderr(str("ngfx: ", ngfx::error(), "\n"));
    return false;
}

fn main() {
    guard open_or_skip() else { return; }
    let write_args = ngfx::slang("""
        #include <NoGraphicsAPI/shader.slang>
        struct Args { uint* draw; uint* indexed; uint* groups; };
        GPU_ROOT(Args, root);
        // The left quad's 6 corners; the right quad's 6 indices from 6;
        // 3 groups.
        [shader("compute")] [numthreads(1, 1, 1)]
        void writeArgs() {
            root.draw[0] = 6; root.draw[1] = 1; root.draw[2] = 0; root.draw[3] = 0;
            root.indexed[0] = 6; root.indexed[1] = 1; root.indexed[2] = 6; root.indexed[3] = 0;
            root.indexed[4] = 0;
            root.groups[0] = 3; root.groups[1] = 1; root.groups[2] = 1;
        }
        """);
    let count = ngfx::slang("""
        #include <NoGraphicsAPI/shader.slang>
        struct Count { uint* counter; };
        GPU_ROOT(Count, root);
        [shader("compute")] [numthreads(4, 1, 1)]
        void count() { InterlockedAdd(root.counter[0], 1u); }
        """);
    let quad = ngfx::slang("""
        #include <NoGraphicsAPI/shader.slang>
        struct Quad { float2* corners; float4 color; };
        GPU_ROOT(Quad, root);
        [shader("vertex")]
        float4 quadVertex(uint vertex_id : SV_VertexID) : SV_Position {
            return float4(root.corners[vertex_id], 0.0, 1.0);
        }
        [shader("fragment")]
        float4 quadFragment() : SV_Target0 { return root.color; }
        """);
    let left: float2[6] = [
        float2 { -1.0, -1.0 }, float2 { 0.0, -1.0 }, float2 { 0.0, 1.0 },
        float2 { -1.0, -1.0 }, float2 { 0.0, 1.0 }, float2 { -1.0, 1.0 },
    ];
    let corners: float2[8] = [
        float2 { -1.0, -1.0 }, float2 { 0.0, -1.0 }, float2 { 0.0, 1.0 }, float2 { -1.0, 1.0 },
        float2 { 0.0, -1.0 }, float2 { 1.0, -1.0 }, float2 { 1.0, 1.0 }, float2 { 0.0, 1.0 },
    ];
    let indices: u16[12] = [0, 1, 2, 0, 2, 3, 4, 5, 6, 4, 6, 7];
    let left_buffer = ngfx::buffer(bytes_of(left));
    let corner_buffer = ngfx::buffer(bytes_of(corners));
    let index_buffer = ngfx::buffer(bytes_of(indices));
    let draw_args = ngfx::buffer(16, "");
    let indexed_args = ngfx::buffer(20, "");
    let group_args = ngfx::buffer(12, "");
    let counter = ngfx::buffer(4, "");

    ngfx::bind(ngfx::compute_pipeline(write_args));
    ngfx::dispatch(ngfx::root(Args { draw: ngfx::address(draw_args),
                                     indexed: ngfx::address(indexed_args),
                                     groups: ngfx::address(group_args) }), 1, 1, 1);
    ngfx::barrier(ngfx::COMPUTE_WRITE, ngfx::STAGE_INDIRECT | ngfx::ACCESS_INDIRECT_READ);

    ngfx::begin_screen(float4 { 0.0, 0.0, 0.0, 1.0 });
    ngfx::bind(ngfx::pipeline(quad));
    ngfx::draw_indirect(ngfx::root(Quad { corners: ngfx::address(left_buffer),
                                          color: float4 { 1.0, 0.0, 0.0, 1.0 } }),
                        ngfx::address(draw_args));
    ngfx::draw_indexed_indirect(ngfx::root(Quad { corners: ngfx::address(corner_buffer),
                                                  color: float4 { 0.0, 1.0, 0.0, 1.0 } }),
                                index_buffer, 2, ngfx::address(indexed_args));
    ngfx::end_pass();

    ngfx::bind(ngfx::compute_pipeline(count));
    ngfx::dispatch_indirect(ngfx::root(Count { counter: ngfx::address(counter) }),
                            ngfx::address(group_args));

    let px = ngfx::read_pixels(ngfx::screen());
    var red = 0;
    var green = 0;
    for y in W {
        for x in W {
            let i = (y * W + x) * 4;
            if x < W / 2 && px[i] == 255 && px[i + 1] == 0 { red++; }
            if x >= W / 2 && px[i] == 0 && px[i + 1] == 255 { green++; }
        }
    }
    print("draw_indirect: ", red, " of ", W * W / 2, " left pixels red");
    print("draw_indexed_indirect: ", green, " of ", W * W / 2, " right pixels green");
    var counted: u32[>..] = [];
    ngfx::read_buffer(counter, counted, 1);
    print("dispatch_indirect: ", counted[0], " threads, of 3 groups of 4");
    ngfx::close();
}
