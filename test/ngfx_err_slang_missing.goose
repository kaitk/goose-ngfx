// A Slang file is resolved relative to the working directory.
import ngfx from "../";

fn main() {
    let shader = ngfx::slang_file("no_such_module.slang");
    print(shader.len);
}
