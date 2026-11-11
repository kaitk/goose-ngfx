// Block-compressed textures, headless: each format the device supports made
// from blocks of one color each, a region of whole blocks replaced, and
// sampled at its blocks' centers. A 6 x 6 texture's edge blocks are cut by
// the texture's edge, as a 2048 texture's are.
import std;
import vec;
import os;
import ngfx from "../";

struct Sample { texture: u32, sampler: u32, at: f32 }

let colors: u8[4][4] = [[255, 0, 0, 255], [0, 255, 0, 255], [0, 0, 255, 255], [255, 255, 255, 255]];

// One 16-byte block of a single color: ASTC's void-extent block, or BC3's
// two endpoints alike with every index 0.
fn one_color(format: i32, c: u8[4]) -> u8[16] {
    var b: u8[16] = [0; 16];
    if format == ngfx::BC3 {
        b[0] = c[3];
        b[1] = c[3];
        let rgb = ((c[0] as i64 >> 3) << 11) | ((c[1] as i64 >> 2) << 5) | (c[2] as i64 >> 3);
        b[8] = (rgb & 255) as u8;
        b[9] = (rgb >> 8) as u8;
        b[10] = b[8];
        b[11] = b[9];
        return b;
    }
    b[0] = 0xFC;
    b[1] = 0xFD;
    for i in 2..8 { b[i] = 0xFF; }
    for i in 4 {
        b[8 + i * 2] = c[i];
        b[9 + i * 2] = c[i];
    }
    return b;
}

fn main() {
    if !ngfx::open_headless(64, 64) {
        write_stderr(str("ngfx: ", ngfx::error(), "\n"));
        return;
    }
    let shader = ngfx::slang("""
        #include <NoGraphicsAPI/shader.slang>
        struct Sample { uint texture; uint sampler; float at; };
        GPU_ROOT(Sample, root);
        struct Varyings { float4 position : SV_Position; float2 uv : TEXCOORD0; };
        [shader("vertex")]
        Varyings fullVertex(uint vertex_id : SV_VertexID) {
            float2 p = float2(float((vertex_id << 1) & 2), float(vertex_id & 2));
            Varyings o;
            o.uv = p;
            o.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
            return o;
        }
        [shader("fragment")]
        float4 sample2d(Varyings i) : SV_Target0 {
            Texture2D<float4> tex = gpu_texture<Texture2D<float4>>(root.texture);
            return tex.SampleLevel(gpu_sampler(root.sampler), i.uv, 0.0);
        }
        """);
    let copy = ngfx::pipeline(shader);
    let nearest = ngfx::sampler(ngfx::NEAREST, ngfx::CLAMP);
    let target = ngfx::render_target(2, 2, ngfx::RGBA8);
    let formats: i32[3] = [ngfx::BC3, ngfx::ASTC_4x4, ngfx::ASTC_6x6];
    let blocks: i32[3] = [4, 4, 6];
    var any = false;
    var all = true;
    for f in 3 {
        let format = formats[f];
        guard ngfx::format_supported(format, ngfx::SAMPLED) else { continue; }
        any = true;
        all = all && !ngfx::format_supported(format, ngfx::SAMPLED | ngfx::COLOR_TARGET);
        // 2 x 2 blocks; 6 x 6 ones in 10 x 10 texels.
        let size: i32 = if blocks[f] == 6 { 10 } else { 8 };
        var data: u8[>..] = [];
        for i in 4 { data.append(one_color(format, colors[i])); }
        let tex = ngfx::texture(ngfx::TextureDesc { format: format, width: size, height: size });
        ngfx::update_texture(tex, data);
        // The bottom right block, cut by the edge, black.
        let edge = blocks[f];
        let black = one_color(format, [0, 0, 0, 255]);
        ngfx::update_texture(tex, ngfx::Region { x: edge, y: edge, w: size - edge, h: size - edge }, black);
        ngfx::begin_pass(target, ngfx::Texture { 0 }, float4 { 0.0, 0.0, 0.0, 0.0 });
        ngfx::bind(copy);
        ngfx::draw(ngfx::root(Sample { texture: ngfx::index(tex), sampler: ngfx::index(nearest), at: 0.0 }), 3);
        ngfx::end_pass();
        let px = ngfx::read_pixels(target);
        for i in 4 {
            let want = if i == 3 { [0 as u8, 0, 0, 255] } else { colors[i] };
            for k in 4 { all = all && px[i * 4 + k] == want[k]; }
        }
        ngfx::release(tex);
    }
    print("compressed: some format supported ", any);
    print("compressed: every supported format sampled as written ", all);
    ngfx::close();
}
