// Frames with the ngfx module, headless: present() ends a frame and starts the
// next, showing nothing with no window, forced or not; resize() replaces the
// screen at the new size, keeping its handle, and leaves it alone at the same
// size; the screen draws in the frames after; and a frame's memory grows
// past its start within the frame.
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
    print("drawn, shown headless ", ngfx::present(), ", count ", ngfx::frame_count());
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
    // This frame's memory starts small and grows: 1 MB in parts in one frame.
    var part: u8[>..] = [];
    part.resize(300000, 7);
    var addresses: u64[>..] = [];
    for i in 4 { addresses.push(ngfx::frame_data(part)); }
    var distinct = true;
    for i in addresses.len { distinct = distinct && addresses[i] != 0; }
    for i in 1..addresses.len { distinct = distinct && addresses[i] != addresses[i - 1]; }
    print("frame memory grown within a frame: ", distinct);
    for i in 5 { ngfx::present(); }
    // A frame that records nothing after frames that did gives back the driver's
    // memory for recording, and the upload queue's once more than its staging went
    // through it: uploads, draws and read-back work after it as before.
    var data: u8[>..] = [];
    data.resize(6 << 20, 3);
    let big = ngfx::buffer(data);
    ngfx::present();
    ngfx::present();
    data[5 << 20] = 9;
    ngfx::update_buffer(big, data);
    ngfx::present();
    ngfx::present();
    var back: u8[>..] = [];
    back.resize(data.len, 0);
    ngfx::read_buffer(big, 0, back);
    ngfx::begin_screen(float4 { 0.0, 1.0, 0.0, 1.0 });
    ngfx::end_pass();
    let green = ngfx::read_pixels(ngfx::screen());
    print("after idle frames: uploaded ", back[0], ",", back[5 << 20], "; drawn ", green[0], ",", green[1], ",",
          green[2]);
    print("open count ", ngfx::open_count());
    ngfx::close();
}
