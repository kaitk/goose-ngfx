// The ngfx package is main-thread only, as windowing is: its sidecar says so,
// and the compiler rejects a thread_fn that reaches it.
import ngfx from "../";

thread_fn render() {
    ngfx::frame();
}

fn main() {
    thread_wait(thread_spawn(render));
}
