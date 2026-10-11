// A module with no entry point is nothing a pipeline can be made from.
import ngfx from "../";

fn main() {
    let shader = ngfx::slang("""
        float twice(float x) { return x * 2.0; }
        """);
    print(shader.len);
}
