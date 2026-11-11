// Texture memory growing a chunk at a time, headless: more textures than a
// chunk holds, each keeping its own texels; one larger than half a chunk in a
// heap of its own, given back and made again; and released ones' room used
// again by new ones.
import std;
import vec;
import os;
import ngfx from "../";

let SIDE = 512;         // 1 MB each in RGBA8: 40 of them fill several 8 MB chunks
let COUNT = 40;

// A texture of one color: its index in red and green.
fn filled(i: i64) -> ngfx::Texture {
    let t = ngfx::texture2d(SIDE, SIDE);
    var px: u8[>..] = [];
    px.resize(SIDE * SIDE * 4, 0);
    var k = 0;
    while k < px.len {
        px[k] = i as u8;
        px[k + 1] = (255 - i) as u8;
        px[k + 3] = 255;
        k += 4;
    }
    ngfx::update_texture(t, px);
    return t;
}

// Whether the texture still holds index i's color, at its first and last texel.
fn holds(t: ngfx::Texture, i: i64) -> bool {
    let px = ngfx::read_pixels(t);
    let last = px.len - 4;
    return px[0] == i as u8 && px[1] == (255 - i) as u8 && px[last] == i as u8 && px[last + 1] == (255 - i) as u8;
}

fn main() {
    if !ngfx::open_headless(64, 64) {
        write_stderr(str("ngfx: ", ngfx::error(), "\n"));
        return;
    }
    var ts: ngfx::Texture[>..] = [];
    for i in COUNT { ts.push(filled(i)); }
    var ok = true;
    for i in COUNT { if !holds(ts[i], i) { ok = false; } }
    print(COUNT, " textures of 1 MB: ", if ok { "each holds its own" } else { "mixed up" });

    // 1500 x 1100 RGBA8, 6.6 MB: a heap of its own of a size no allocation unit divides.
    let odd = ngfx::texture2d(1500, 1100);
    if odd.id != 0 { print("one of 6.6 MB: made"); } else { print("one of 6.6 MB: ", ngfx::error()); }
    ngfx::release(odd);

    // 8192 x 4096 RGBA8, 128 MB: a heap of its own.
    let big = ngfx::texture2d(8192, 4096);
    if big.id != 0 { print("one of 128 MB: made"); } else { print("one of 128 MB: ", ngfx::error()); }
    ngfx::release(big);
    ngfx::flush();
    let again = ngfx::texture2d(8192, 4096);
    if again.id != 0 { print("given back and made again: made"); } else { print("again: ", ngfx::error()); }
    ngfx::release(again);

    // Half released, then as many new ones in their room.
    var i = 0;
    while i < COUNT {
        ngfx::release(ts[i]);
        i += 2;
    }
    ngfx::flush();
    i = 0;
    while i < COUNT {
        ts[i] = filled(i);
        i += 2;
    }
    ok = true;
    for k in COUNT { if !holds(ts[k], k) { ok = false; } }
    print("half released and made again: ", if ok { "each holds its own" } else { "mixed up" });
    ngfx::close();
}
