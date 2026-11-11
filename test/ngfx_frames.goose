// Frames with the ngfx module, headless: present() ends a frame and starts the
// next, showing nothing with no window, forced or not; resize() replaces the
// screen at the new size, keeping its handle, and leaves it alone at the same
// size; and the screen draws in the frames after.
import std;
import vec;
import os;
import ngfx from "../";

fn open_or_skip() -> bool {
    if ngfx::open_headless(32, 24) { return true; }
    write_stderr(str("ngfx: ", ngfx::error(), "\n"));
    return false;
}

fn main() {
    guard open_or_skip() else { return; }
    let size = ngfx::screen_size();
    print("screen ", size.x, " x ", size.y, ", driver named ", ngfx::driver().len > 0);
    let screen = ngfx::screen();
    ngfx::begin_screen(float4 { 1.0, 0.0, 0.0, 1.0 });
    ngfx::end_pass();
    print("drawn, shown headless ", ngfx::present(), ", forced ", ngfx::present(true), ", count ",
          ngfx::frame_count());
    ngfx::resize(32, 24);
    print("same size, same screen ", ngfx::screen().id == screen.id);
    ngfx::resize(int2 { 48, 16 });
    let after = ngfx::screen_size();
    print("resized to ", after.x, " x ", after.y, ", same handle ", ngfx::screen().id == screen.id);
    ngfx::begin_screen(float4 { 0.0, 0.0, 1.0, 1.0 });
    ngfx::end_pass();
    ngfx::present();
    let px = ngfx::read_pixels(ngfx::screen());
    print("drawn after the resize: ", px.len / 4, " pixels, first ", px[0], ",", px[1], ",", px[2]);
    for i in 5 { ngfx::present(); }
    print("open count ", ngfx::open_count());
    ngfx::close();
}
