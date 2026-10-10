// An error in Slang a global holds is reported at its line in the module
// the parts make.
import ngfx;

let helpers = """
    float twice(float x) { return x * oops; }
    """;

fn main() {
    let shader = ngfx::slang("#include <NoGraphicsAPI/shader.slang>", helpers, """
        [shader("compute")] [numthreads(1, 1, 1)]
        void fill(uint3 id : SV_DispatchThreadID) { float y = twice(1.0); }
        """);
    print(shader.len);
}
