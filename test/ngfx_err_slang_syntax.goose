// A Slang module that does not compile aborts the program at the slang()
// call, reported at the offending line of the module.
import ngfx from "../";

fn main() {
    let shader = ngfx::slang("""
        #include <NoGraphicsAPI/shader.slang>
        [shader("compute")] [numthreads(1, 1, 1)]
        void fill(uint3 id : SV_DispatchThreadID) { uint x = oops; }
        """);
    print(shader.len);
}
