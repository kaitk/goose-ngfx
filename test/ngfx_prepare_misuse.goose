// prepare() for a pass with no targets: a misuse, reported as it happens,
// which aborts the program at the next frame().
import std;
import vec;
import os;
import ngfx from "../";

fn main() {
    guard ngfx::open_headless(16, 16) else {
        write_stderr(str("ngfx: ", ngfx::error(), "\n"));
        return;
    }
    let p = ngfx::pipeline(ngfx::slang("""
        #include <NoGraphicsAPI/shader.slang>
        [shader("vertex")]
        float4 v(uint vertex_id : SV_VertexID) : SV_Position { return float4(0.0, 0.0, 0.0, 1.0); }
        [shader("fragment")]
        float4 f() : SV_Target0 { return float4(1.0, 1.0, 1.0, 1.0); }
        """));
    print("preparing for no targets: ", ngfx::prepare(p, ngfx::PassDesc {}));
    ngfx::frame();
    print("not reached");
}
