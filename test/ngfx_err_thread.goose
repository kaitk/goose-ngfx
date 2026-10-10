// The ngfx layer is main-thread only, as windowing is, and says so.
import ngfx;

thread_fn render() {
    ngfx::frame();
}

fn main() {
    thread_wait(thread_spawn(render));
}
