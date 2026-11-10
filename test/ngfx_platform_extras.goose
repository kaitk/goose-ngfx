// Fullscreen, scale, cursor shapes and gamepads without a window: scales are
// 1, a headless screen is never fullscreen, cursor shapes are validated, and
// an empty gamepad slot reads as nothing.
import std;
import os;
import ngfx from "../";

fn main() {
    print("before open: ", ngfx::pixel_density(), " ", ngfx::display_scale());
    guard ngfx::open_headless(32, 24) else {
        write_stderr(str("ngfx: ", ngfx::error(), "\n"));
        return;
    }
    ngfx::frame();
    print("headless: ", ngfx::pixel_density(), " ", ngfx::display_scale());
    print("fullscreen ", ngfx::fullscreen(), ", set ", ngfx::set_fullscreen(true), ", now ",
          ngfx::fullscreen());
    ngfx::maximize();
    print("size ", ngfx::screen_size().x, " ", ngfx::screen_size().y);

    print("cursor default ", ngfx::set_cursor(ngfx::CURSOR_DEFAULT));
    print("cursor last ", ngfx::set_cursor(ngfx::CURSOR_W_RESIZE));
    print("cursor invalid ", ngfx::set_cursor(-1), " ", ngfx::set_cursor(ngfx::CURSOR_W_RESIZE + 1));

    // Slot 3 stays empty even if a pad is plugged in to a developer's machine.
    print("pad connected ", ngfx::gamepad_connected(3), ", type ", ngfx::gamepad_type(3));
    print("pad axis ", ngfx::gamepad_axis(3, ngfx::AXIS_LEFT_X));
    print("pad buttons ", ngfx::gamepad_down(3, ngfx::GAMEPAD_SOUTH), " ",
          ngfx::gamepad_pressed(3, ngfx::GAMEPAD_SOUTH), " ",
          ngfx::gamepad_released(3, ngfx::GAMEPAD_SOUTH));
    print("pad rumble ", ngfx::gamepad_rumble(3, 1.0, 1.0, 10));
    ngfx::frame();
    print("pad still ", ngfx::gamepad_connected(3));
    ngfx::close();
    print("after close: ", ngfx::pixel_density(), " ", ngfx::display_scale(), " ",
          ngfx::fullscreen());
}
