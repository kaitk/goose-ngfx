// `ngfx` (docs/api.md), graphics on NoGraphicsAPI
// (third_party/NoGraphicsAPI): Goose gfx's screen, textures and read-back,
// with NoGraphicsAPI's way of drawing, into a native window the program gives
// it. The window, input, events and time are the program's, usually Goose
// gfx's opened WINDOW_ONLY:
//
//   gfx::open("title", w, h, gfx::WINDOW_ONLY);   // a window, no GPU device
//   let size = gfx::screen_size();
//   ngfx::open(gfx::native_window(), size.x, size.y, 0);
//   while gfx::frame() {                          // events; waits when idle
//       ngfx::resize(gfx::screen_size());
//       if changed || gfx::needs_present() { ...draw into screen()... }
//       gfx::presented(ngfx::present());
//   } The
// functions are C, the layer in native/, declared here as extern fns against
// the list in native/ngfx_api.h; scripts/api_check.py checks the two agree.
// docs/design.md says why it is shaped as it is.
//
// Drawing passes data to shaders as memory, not bindings. A draw takes the
// GPU address of a root: a struct the program fills, declared again in the
// shader, which reads it with GPU_ROOT. The root holds what the shader
// needs: GPU addresses of buffers (address(b)), which it reads as pointers,
// fetching its own vertices; indices of textures and samplers (index(t),
// index(s)); and constants. root(value) copies a root into this frame's
// memory and gives its address; frame_data(bytes) does the same for any
// other data that lives one frame.
//
//   struct Root { vertices: u64, transform: ngfx::float4x4 }
//   let root = ngfx::root(Root { vertices: ngfx::address(vertex_buffer), transform: m });
//   ngfx::draw(root, vertex_count);
//
// A Goose struct is packed and a Slang one has C's layout, so pad the Goose
// struct where C would: a u64 (a pointer) on an 8-byte boundary.
//
// Shaders are Slang modules, compiled by slang() while the program runs,
// for the backend it runs on: SPIR-V for Vulkan, and a metallib for Metal
// as well on a Mac. One module holds every entry point, each marked
// [shader("vertex")], [shader("fragment")] or [shader("compute")]; it is
// written in the program, `ngfx::slang("""...""")`, or read from a file,
// `ngfx::slang_file("file.slang")`, and starts with
// `#include <NoGraphicsAPI/shader.slang>`.
//
// Clip space is NoGraphicsAPI's on both backends: y down, depth from 0 to 1,
// and texture coordinates with (0, 0) at the top left. perspective(),
// ortho() and look_at() below produce matrices for it, as row-major
// float4x4s, which Slang reads as its float4x4: mul(root.transform, v).
//
// Synchronization is split by who can see both sides of a hazard. The
// layer orders the work it records itself: uploads (NoGraphicsAPI's
// UploadQueue, which reaches the GPU before the frame's work, so
// update_buffer takes effect for the whole frame it is called in), texture
// creation, read-back, each frame's first pass after the last frame (none
// when it draws into the window's image alone, which no earlier frame used),
// and a pass drawing into a target an earlier pass drew into. What shaders
// read and write through roots, the layer cannot see, so the program states
// it, between passes and dispatches:
//
//   ngfx::dispatch(...);                                       // writes a buffer
//   ngfx::barrier(ngfx::COMPUTE_WRITE, ngfx::VERTEX_READ);     // which the pass reads
//   ngfx::begin_screen(...);
//
// and nothing else is recorded: dispatches writing separate memory, and
// passes drawing into separate targets, wait for nothing. A missing barrier
// is a race, as in NoGraphicsAPI; GOOSE_NGFX_SYNC=full in the environment
// puts a full barrier around every pass and dispatch, so a program whose
// output changes under it is missing one.
//
// Errors: a call that can fail for reasons outside the program returns
// false or a zero handle, and error() says why. A call the program should
// not have made is reported as it happens and aborts the program at the
// next present(), check() or read back.

namespace ngfx;

import std;
import vec;
import math;

// --- constants: NGFX_CONSTANTS in native/ngfx_api.h -----------------------

// open() and open_headless() flags.
let NO_VSYNC: i32 = 16;

// Texture kinds.
let TEXTURE_2D: i32 = 0;
let TEXTURE_2D_ARRAY: i32 = 1;
let TEXTURE_3D: i32 = 2;
let TEXTURE_CUBE: i32 = 3;

// Texture usage, combined with |. Every texture can also be updated and
// read back.
let SAMPLED: i32 = 1;
let COLOR_TARGET: i32 = 2;
let DEPTH_TARGET: i32 = 4;
let STORAGE: i32 = 8;                 // read and written by shaders, through storage_index

// Texture formats. DEPTH is DEPTH32F.
let RGBA8: i32 = 1;
let BGRA8: i32 = 2;
let RGBA8_SRGB: i32 = 3;
let R8: i32 = 4;
let RG8: i32 = 5;
let RGBA16F: i32 = 6;
let RGBA32F: i32 = 7;
let R16F: i32 = 8;
let RG16F: i32 = 9;
let R32F: i32 = 10;
let RG32F: i32 = 11;
let R32UI: i32 = 12;
let RGBA8UI: i32 = 13;
let RGB10A2: i32 = 14;
let RG11B10F: i32 = 15;
let DEPTH16: i32 = 16;
let DEPTH32F: i32 = 18;
let DEPTH24_STENCIL8: i32 = 19;
let DEPTH: i32 = 20;
// Block-compressed, SAMPLED only and uploaded in whole blocks: BC on desktop
// GPUs, ASTC on Apple silicon and phones. format_supported says which.
let BC3: i32 = 22;
let BC7: i32 = 23;
let ASTC_4x4: i32 = 24;
let ASTC_6x6: i32 = 26;

// Samplers.
let NEAREST: i32 = 0;
let LINEAR: i32 = 1;
let REPEAT: i32 = 0;
let MIRROR: i32 = 1;
let CLAMP: i32 = 2;
let COMPARE_NEVER: i32 = 1;
let COMPARE_LESS: i32 = 2;
let COMPARE_EQUAL: i32 = 3;
let COMPARE_LESS_EQUAL: i32 = 4;
let COMPARE_GREATER: i32 = 5;
let COMPARE_NOT_EQUAL: i32 = 6;
let COMPARE_GREATER_EQUAL: i32 = 7;
let COMPARE_ALWAYS: i32 = 8;

// Pipelines. NoGraphicsAPI draws triangle lists only.
let CULL_NONE: i32 = 0;
let CULL_FRONT: i32 = 1;
let CULL_BACK: i32 = 2;
let BLEND_NONE: i32 = 0;
let BLEND_ALPHA: i32 = 1;
let BLEND_ADD: i32 = 2;
let BLEND_PREMULTIPLIED: i32 = 3;
let BLEND_MULTIPLY: i32 = 4;

// load_texture() flags.
let LOAD_SRGB: i32 = 2;

// Barrier points, for barrier(): a STAGE_* | ACCESS_* combination, each with
// NoGraphicsAPI's Stage and Access meaning, combined with |. A stage stands
// for itself and, on the before side, the stages logically before it, on
// the after side those after it (NoGraphicsAPI.hpp's Stage).
let STAGE_INDIRECT: i32 = 1;
let STAGE_INDEX_INPUT: i32 = 2;
let STAGE_VERTEX: i32 = 4;
let STAGE_TASK: i32 = 8;
let STAGE_MESH: i32 = 16;
let STAGE_DEPTH: i32 = 32;            // depth and stencil tests
let STAGE_FRAGMENT: i32 = 64;
let STAGE_COLOR_OUTPUT: i32 = 128;
let STAGE_COMPUTE: i32 = 256;
let STAGE_TRANSFER: i32 = 512;
let STAGE_ALL: i32 = 2048;
let ACCESS_TRANSFER_READ: i32 = 65536;
let ACCESS_TRANSFER_WRITE: i32 = 131072;
let ACCESS_SHADER_READ: i32 = 262144;
let ACCESS_SHADER_WRITE: i32 = 524288;
let ACCESS_COLOR_READ: i32 = 1048576;
let ACCESS_COLOR_WRITE: i32 = 2097152;
let ACCESS_DEPTH_READ: i32 = 4194304;
let ACCESS_DEPTH_WRITE: i32 = 8388608;
let ACCESS_INDIRECT_READ: i32 = 16777216;
let ACCESS_INDEX_READ: i32 = 33554432;
let ACCESS_DESCRIPTOR_READ: i32 = 134217728;
// The usual ones, named.
let COMPUTE_WRITE: i32 = 524544;      // STAGE_COMPUTE | ACCESS_SHADER_WRITE
let COMPUTE_READ: i32 = 262400;       // STAGE_COMPUTE | ACCESS_SHADER_READ
let VERTEX_READ: i32 = 262148;        // STAGE_VERTEX | ACCESS_SHADER_READ
let FRAGMENT_READ: i32 = 262208;      // STAGE_FRAGMENT | ACCESS_SHADER_READ
let TARGET_WRITE: i32 = 10485920;     // a pass's color and depth writes
let INDEX_READ: i32 = 33554434;       // STAGE_INDEX_INPUT | ACCESS_INDEX_READ

// --- handles and descriptions: the structs of native/ngfx_api.h -------------

// A GPU object, by handle. A released handle is an error to use, not a
// crash; a zero handle is none.
struct Buffer { id: u32 }
struct Texture { id: u32 }
struct Sampler { id: u32 }
struct Pipeline { id: u32 }
struct ComputePipeline { id: u32 }

// GPU memory: an address and the bytes from it. A buffer's is range(b), and
// frame_range() makes one in this frame's memory.
struct Range { address: u64, size: i64 }

// Field defaults cannot name the constants above (a default may run before
// any global is initialized), so they spell the values, and say which.
struct TextureDesc {
    kind: i32 = 0,          // TEXTURE_2D
    format: i32 = 1,        // RGBA8
    usage: i32 = 1,         // SAMPLED
    width: i32,
    height: i32,
    depth: i32 = 1,         // a 3D texture's depth, or an array's layers
    mips: i32 = 1,          // 0: the full chain
}

// Part of one mip of one layer of a texture; w == 0 is the whole mip.
struct Region {
    mip: i32 = 0,
    layer: i32 = 0,         // array layer, or cube face (+x, -x, +y, -y, +z, -z)
    x: i32 = 0,
    y: i32 = 0,
    z: i32 = 0,
    w: i32 = 0,
    h: i32 = 0,
    d: i32 = 0,
}

struct SamplerDesc {
    min_filter: i32 = 1,    // LINEAR
    mag_filter: i32 = 1,
    mip_filter: i32 = 1,
    wrap_u: i32 = 0,        // REPEAT
    wrap_v: i32 = 0,
    wrap_w: i32 = 0,
    max_anisotropy: f32 = 1.0,      // more than 1: NoGraphicsAPI's fixed 4x
    compare: i32 = 0,       // a COMPARE_*, for a shadow sampler
}

// What a pipeline adds to its shaders. It is not tied to the formats it
// draws into: it is made for the targets of each pass it is bound in, the
// first time, unless prepare() made it for them before.
struct PipelineDesc {
    cull: i32 = 0,          // CULL_NONE
    clockwise: bool = false,        // front faces wind clockwise on the screen
    depth_test: bool = false,
    depth_write: bool = false,
    depth_compare: i32 = 2, // COMPARE_LESS
    blend: i32 = 0,         // BLEND_NONE
    depth_bias: f32 = 0.0,
    depth_bias_slope: f32 = 0.0,
}

struct PassDesc {
    color: Texture[4] = [Texture { 0 }; 4],     // targets, up to the first zero handle
    depth: Texture = Texture { 0 },
    layer: i32 = 0,                             // of the targets: a face, a slice
    mip: i32 = 0,
    clear_color: bool = true,
    clear_depth: bool = true,
    color_value: float4 = float4 { 0.0, 0.0, 0.0, 1.0 },
    depth_value: f32 = 1.0,
}

// --- device and frames ------------------------------------------------------

// Whether the ngfx layer is linked in: true wherever a program using it
// links, which is only as an executable built from the generated C.
extern fn available() -> bool = "ngfx_available";

// The GPU device, drawing into `window`, a native window's handle as a u64
// (a CAMetalLayer on Apple's systems, an HWND on Windows; gfx's
// native_window()), with a screen of width x height pixels, the window's size
// in pixels; or headless for a window of 0. False with error() set. Flags:
// NO_VSYNC presents without waiting for the display, for benchmarks.
extern fn open(window: u64, width: i64, height: i64, flags: i64) -> bool = "ngfx_open";
// The device alone, drawing into a screen of width x height that no window
// shows: for tests, and for tools that only compute or render to files.
extern fn open_headless(width: i64, height: i64, flags: i64) -> bool = "ngfx_open_headless";
fn open_headless(width: i64, height: i64) -> bool { open_headless(width, height, 0) }
extern fn close_raw() = "ngfx_close";
fn close() {
    check();
    close_raw();
}

extern fn error_into(out: u8[>..]&) = "ngfx_error";
extern fn misuse_count() -> i64 = "ngfx_misuse_count";
// Why the last call that failed did, as text.
fn error() -> u8[>..] {
    var text: u8[>..] = [];
    error_into(text);
    return text;
}
// Aborts, saying why, if the program has used ngfx wrongly.
fn check() {
    if misuse_count() > 0 { abort(str("ngfx: ", error())); }
}

extern fn driver_into(out: u8[>..]&) = "ngfx_driver";
// NoGraphicsAPI's backend: "metal" or "vulkan".
fn driver() -> u8[>..] {
    var name: u8[>..] = [];
    driver_into(name);
    return name;
}

// Ends the frame drawn since open() or the last present(): submits it, and
// shows the screen in the window if the frame drew into it. Then starts the
// next frame. Whether it showed one: a program on gfx hands that to
// gfx::presented, so that a frame that showed nothing makes the next
// gfx::frame() wait for an event. A window that wants showing again (gfx's
// needs_present(): exposed, shown or resized) needs a frame drawn: ngfx
// keeps no copy of the last one. Headless, it shows nothing.
extern fn present_raw() -> bool = "ngfx_present";
fn present() -> bool {
    let shown = present_raw();
    check();
    shown
}
// The window's size in pixels, which the screen follows: call it each frame
// with gfx::screen_size(), before drawing. Nothing happens when it is the
// screen's size already.
extern fn resize(width: i64, height: i64) = "ngfx_resize";
fn resize(size: int2) { resize(size.x, size.y); }
// Submits everything drawn so far and waits until the GPU has done it.
extern fn flush_raw() = "ngfx_flush";
fn flush() {
    flush_raw();
    check();
}

// The screen: what a frame draws into, of the window's size in pixels, with
// a depth texture to go with it. Both keep their handles when the window
// resizes. In a window the screen is the window's image, BGRA8, which a
// frame's first pass into it acquires and present() shows: only a pass can
// draw into it, and it holds nothing of the last frame, so that pass clears
// it. Headless it is an RGBA8 texture, which keeps what the last frame drew
// and can be sampled, read back and saved.
extern fn screen() -> Texture = "ngfx_screen";
extern fn screen_depth() -> Texture = "ngfx_screen_depth";
extern fn screen_size_into(out: int2&) = "ngfx_screen_size";
fn screen_size() -> int2 {
    var size = int2_0;
    screen_size_into(size);
    size
}

// How many frames have been shown in the window since open.
extern fn frame_count() -> i64 = "ngfx_frame_count";
// How many times ngfx has been opened in this process: handles made before it
// last changed were released by close().
extern fn open_count() -> i64 = "ngfx_open_count";

// --- buffers and this frame's data ---------------------------------------------

// A buffer of `size` bytes of GPU memory, holding `data` and zeros after it.
// Shaders reach it through its address. Data comes from bytes_of:
// ngfx::buffer(bytes_of(vertices)).
extern fn buffer(size: i64, data: const u8[:]) -> Buffer = "ngfx_create_buffer";
fn buffer(data: const u8[:]) -> Buffer { buffer(data.len, data) }
// New contents from `offset`, for every draw of the frame being recorded and
// the frames after it.
extern fn update_buffer(b: Buffer, offset: i64, data: const u8[:]) -> bool = "ngfx_update_buffer";
fn update_buffer(b: Buffer, data: const u8[:]) -> bool { update_buffer(b, 0, data) }
extern fn read_buffer_into(b: Buffer, offset: i64, out: u8[:]) -> bool = "ngfx_read_buffer";
extern fn buffer_size(b: Buffer) -> i64 = "ngfx_buffer_size";
// The buffer's GPU address, for a root: a pointer in the shader.
extern fn address(b: Buffer) -> u64 = "ngfx_buffer_address";
extern fn range_into(b: Buffer, out: Range&) = "ngfx_buffer_range";
// The buffer's address and size.
fn range(b: Buffer) -> Range {
    var r = Range { address: 0, size: 0 };
    range_into(b, r);
    r
}
extern fn release(b: Buffer) = "ngfx_release_buffer";

// Reads back `out.len` bytes from `offset`, once the GPU has done
// everything recorded before. Not inside a pass.
fn read_buffer(b: Buffer, offset: i64, out: u8[:]) -> bool {
    let ok = read_buffer_into(b, offset, out);
    check();
    ok
}

// Appends the buffer's first `count` elements to `out`, as the elements of
// out's type: ngfx::read_buffer(results, floats, 256) into an f32[>..].
fn read_buffer<T>(b: Buffer, out: T[>..]&, count: i64) -> bool {
    var raw: u8[>..] = [];
    raw.resize(count * elem_size(out), 0);
    let ok = read_buffer(b, 0, raw);
    append_as(raw, out);
    ok
}

// `data` copied into this frame's memory, and its GPU address, 16-byte
// aligned. It lives until the GPU has finished the frame.
extern fn frame_data(data: const u8[:]) -> u64 = "ngfx_frame_data";
// The same, with its size: indices that live one frame, for draw_indexed.
fn frame_range(data: const u8[:]) -> Range { Range { address: frame_data(data), size: data.len } }

// A root: any flat struct copied into this frame's memory, and the address
// a draw or dispatch takes.
fn root<T>(value: T) -> u64 {
    let one: T[1] = [value];
    frame_data(bytes_of(one))
}

// --- textures and samplers -----------------------------------------------------

// The extern fns taking a description by reference are wrapped by ones
// taking it by value, which a struct literal can be passed to.
extern fn create_texture(desc: const TextureDesc&) -> Texture = "ngfx_create_texture";
fn texture(desc: TextureDesc) -> Texture { create_texture(desc) }
fn texture2d(width: i64, height: i64, format: i32, usage: i32) -> Texture {
    texture(TextureDesc { format: format, usage: usage, width: width as i32,
                          height: height as i32 })
}
fn texture2d(width: i64, height: i64) -> Texture { texture2d(width, height, RGBA8, SAMPLED) }
// A texture to draw into and then sample.
fn render_target(width: i64, height: i64, format: i32) -> Texture {
    texture2d(width, height, format, COLOR_TARGET | SAMPLED)
}
// A depth buffer that can also be sampled, as a shadow map is.
fn depth_target(width: i64, height: i64) -> Texture {
    texture2d(width, height, DEPTH, DEPTH_TARGET | SAMPLED)
}
fn texture3d(width: i64, height: i64, depth: i64, format: i32, usage: i32) -> Texture {
    texture(TextureDesc { kind: TEXTURE_3D, format: format, usage: usage, width: width as i32,
                          height: height as i32, depth: depth as i32 })
}
fn texture_cube(size: i64, format: i32, usage: i32) -> Texture {
    texture(TextureDesc { kind: TEXTURE_CUBE, format: format, usage: usage, width: size as i32,
                          height: size as i32 })
}
fn texture_array(width: i64, height: i64, layers: i64, format: i32, usage: i32) -> Texture {
    texture(TextureDesc { kind: TEXTURE_2D_ARRAY, format: format, usage: usage,
                          width: width as i32, height: height as i32, depth: layers as i32 })
}

// A PNG (or .bmp) as an RGBA8 texture, RGBA8_SRGB with LOAD_SRGB.
extern fn load_texture(path: const u8[:], flags: i64) -> Texture = "ngfx_load_texture";
fn load_texture(path: const u8[:]) -> Texture { load_texture(path, 0) }

extern fn update_texture_region(t: Texture, region: const Region&,
                                data: const u8[:]) -> bool = "ngfx_update_texture";
fn update_texture(t: Texture, region: Region, data: const u8[:]) -> bool {
    update_texture_region(t, region, data)
}
// The whole of mip 0 of layer 0: a 2D texture, or all of a 3D one.
fn update_texture(t: Texture, data: const u8[:]) -> bool { update_texture(t, Region {}, data) }

extern fn read_texture_into(t: Texture, region: const Region&,
                            out: u8[:]) -> bool = "ngfx_read_texture";
fn read_texture(t: Texture, region: Region, out: u8[:]) -> bool {
    let ok = read_texture_into(t, region, out);
    check();
    ok
}
// Appends the whole of mip 0 of layer 0 to `out`, as the elements of out's
// type: u8 for the bytes of an RGBA8 texture, float4 for RGBA32F texels.
fn read_texture<T>(t: Texture, out: T[>..]&) -> bool {
    let info = texture_info(t);
    var raw: u8[>..] = [];
    raw.resize(texel_size(info.format) * info.width * info.height *
               (if info.kind == TEXTURE_3D { info.depth } else { 1 }), 0);
    let ok = read_texture(t, Region {}, raw);
    append_as(raw, out);
    ok
}
// The bytes of mip 0 of layer 0, fresh: an RGBA8 texture's pixels, four
// bytes each, from the top left.
fn read_pixels(t: Texture) -> u8[>..] {
    var px: u8[>..] = [];
    read_texture(t, px);
    return px;
}

// An RGBA8 or BGRA8 texture's mip 0 as a PNG file; the headless screen as
// it is shown, opaque.
extern fn save_png_raw(t: Texture, path: const u8[:]) -> bool = "ngfx_save_png";
fn save_png(t: Texture, path: const u8[:]) -> bool {
    let ok = save_png_raw(t, path);
    check();
    ok
}
// The headless screen; in a window the screen is the window's image, which
// can't be read.
fn screenshot(path: const u8[:]) -> bool { save_png(screen(), path) }

extern fn texture_info_into(t: Texture, out: TextureDesc&) -> bool = "ngfx_texture_info";
fn texture_info(t: Texture) -> TextureDesc {
    var d = TextureDesc { width: 0, height: 0 };
    texture_info_into(t, d);
    d
}
// The texture's slot in the sampled-texture heap, for a root: the shader's
// gpu_texture<Texture2D<float4>>(index). A SAMPLED texture has one.
extern fn index(t: Texture) -> u32 = "ngfx_texture_index";
// Its slot as a storage texture, gpu_texture<RWTexture2D<float4>>(index),
// for a STORAGE texture; or one mip level's, which is how a shader writes a
// level other than the first.
extern fn storage_index(t: Texture) -> u32 = "ngfx_storage_index";
extern fn storage_index(t: Texture, mip: i64) -> u32 = "ngfx_storage_mip_index";
extern fn release(t: Texture) = "ngfx_release_texture";
// Whether this device makes a 2D texture of `format` with `usage`: what a
// compressed format needs asking before use, and a fallback is chosen by.
extern fn format_supported(format: i32, usage: i32) -> bool = "ngfx_format_supported";

// The bytes one texel of `format` takes.
fn texel_size(format: i32) -> i64 {
    if format == R8 { return 1; }
    if format == RG8 || format == R16F || format == DEPTH16 { return 2; }
    if format == RGBA16F || format == RG32F { return 8; }
    if format == RGBA32F { return 16; }
    return 4;
}

extern fn create_sampler(desc: const SamplerDesc&) -> Sampler = "ngfx_create_sampler";
fn sampler(desc: SamplerDesc) -> Sampler { create_sampler(desc) }
fn sampler(filter: i32, wrap: i32) -> Sampler {
    sampler(SamplerDesc { min_filter: filter, mag_filter: filter, mip_filter: filter,
                          wrap_u: wrap, wrap_v: wrap, wrap_w: wrap })
}
// For a SamplerComparisonState: a hardware depth comparison, filtered.
fn shadow_sampler() -> Sampler {
    sampler(SamplerDesc { wrap_u: CLAMP, wrap_v: CLAMP, wrap_w: CLAMP,
                          compare: COMPARE_LESS_EQUAL })
}
// The sampler's slot in the sampler heap, for a root: gpu_sampler(index).
extern fn index(s: Sampler) -> u32 = "ngfx_sampler_index";
extern fn release(s: Sampler) = "ngfx_release_sampler";

// --- shaders -----------------------------------------------------------------

// The Slang module `source`, compiled into what pipeline() and
// compute_pipeline() take, or the program aborts with slangc's error, at
// "<slang source>:line". Its #include also looks in the working directory.
// Compiling needs slangc (docs/development.md) but no device, and takes a
// fraction of a second, so compile each module once, before the frame loop.
extern fn compile_slang(source: const u8[:], out: u8[>..]&) -> bool = "ngfx_compile_slang";
extern fn compile_slang_file(path: const u8[:], out: u8[>..]&) -> bool = "ngfx_compile_slang_file";
fn slang(source: const u8[:]) -> u8[>..] {
    var blob: u8[>..] = [];
    if !compile_slang(source, blob) { abort(str("ngfx::slang: ", error())); }
    return blob;
}
// A module written in parts, such as code shared by several modules: the
// parts are its lines in order.
fn slang(a: const u8[:], b: const u8[:]) -> u8[>..] { slang(str(a, "\n", b)) }
fn slang(a: const u8[:], b: const u8[:], c: const u8[:]) -> u8[>..] {
    slang(str(a, "\n", b, "\n", c))
}
// The module in the file at `path`, relative to the working directory; its
// #include also looks in the file's own directory.
fn slang_file(path: const u8[:]) -> u8[>..] {
    var blob: u8[>..] = [];
    if !compile_slang_file(path, blob) { abort(str("ngfx::slang: ", error())); }
    return blob;
}

// --- pipelines ---------------------------------------------------------------

// `shader` is a slang() result. The vertex and fragment entry points
// are its only ones of their stage, or the ones named.
extern fn create_pipeline(shader: const u8[:], vertex: const u8[:],
                          fragment: const u8[:],
                          desc: const PipelineDesc&) -> Pipeline = "ngfx_create_pipeline";
fn pipeline(shader: const u8[:], vertex: const u8[:], fragment: const u8[:],
            desc: PipelineDesc) -> Pipeline {
    create_pipeline(shader, vertex, fragment, desc)
}
fn pipeline(shader: const u8[:], desc: PipelineDesc) -> Pipeline {
    create_pipeline(shader, "", "", desc)
}
fn pipeline(shader: const u8[:]) -> Pipeline { pipeline(shader, PipelineDesc {}) }
extern fn release(p: Pipeline) = "ngfx_release_pipeline";
// Makes the pipeline for the formats of `pass`'s targets now, as its first
// draw into them would, so the driver compiles its shaders before the frame
// loop rather than in a frame. A pipeline can be prepared for several sets
// of targets. False, with error() set, if it can't draw into them.
extern fn prepare_desc(p: Pipeline, pass: const PassDesc&) -> bool = "ngfx_prepare_pipeline";
fn prepare(p: Pipeline, pass: PassDesc) -> bool { prepare_desc(p, pass) }
// For passes into `target` and `depth`, or Texture { 0 } for none.
fn prepare(p: Pipeline, target: Texture, depth: Texture) -> bool {
    var d = PassDesc { depth: depth };
    d.color[0] = target;
    prepare_desc(p, d)
}
// For begin_screen's passes.
fn prepare_screen(p: Pipeline) -> bool { prepare(p, screen(), screen_depth()) }

// The compute entry point `entry` of `shader`, or its only one; the thread
// group size is the one its numthreads declares.
extern fn compute_pipeline(shader: const u8[:],
                           entry: const u8[:]) -> ComputePipeline = "ngfx_create_compute_pipeline";
fn compute_pipeline(shader: const u8[:]) -> ComputePipeline { compute_pipeline(shader, "") }
extern fn release(p: ComputePipeline) = "ngfx_release_compute_pipeline";

// --- passes and drawing ----------------------------------------------------------

// Draws go between begin_pass and end_pass, into the targets the pass
// names; the bound pipeline lasts until the pass ends.
extern fn begin_pass_desc(desc: const PassDesc&) -> bool = "ngfx_begin_pass";
fn begin_pass(desc: PassDesc) -> bool { begin_pass_desc(desc) }
extern fn end_pass() = "ngfx_end_pass";
// Into one target, with a depth target or Texture { 0 }, cleared.
fn begin_pass(target: Texture, depth: Texture, clear: float4) -> bool {
    var d = PassDesc { depth: depth, color_value: clear };
    d.color[0] = target;
    begin_pass_desc(d)
}
// Into the screen and its depth, cleared to `clear`.
fn begin_screen(clear: float4) -> bool { begin_pass(screen(), screen_depth(), clear) }

extern fn bind(p: Pipeline) = "ngfx_bind_pipeline";
extern fn viewport(x: f32, y: f32, w: f32, h: f32) = "ngfx_viewport";
// w == 0: the whole target.
extern fn scissor(x: i64, y: i64, w: i64, h: i64) = "ngfx_scissor";

// `root` is a root's address (root(), frame_data()), or 0 for a shader
// without one. SV_VertexID counts from first_vertex on Metal and from 0 on
// Vulkan, as Slang compiles it, so a shader that fetches its own vertices
// takes where they start from its root, or draws indexed.
extern fn draw(root: u64, vertices: i64, instances: i64, first_vertex: i64,
               first_instance: i64) = "ngfx_draw";
fn draw(root: u64, vertices: i64) { draw(root, vertices, 1, 0, 0) }
fn draw_instanced(root: u64, vertices: i64, instances: i64) { draw(root, vertices, instances, 0, 0) }
// Indices of index_size bytes, 2 for u16 or 4 for u32, from `indices`: a
// buffer, or a Range such as frame_range() makes. SV_VertexID is the index,
// plus vertex_offset on Metal only, as for draw's first_vertex.
extern fn draw_indexed_raw(root: u64, indices: u64, indices_size: i64,
                           index_size: i64, count: i64, instances: i64,
                           first_index: i64, vertex_offset: i64,
                           first_instance: i64) = "ngfx_draw_indexed";
fn draw_indexed(root: u64, indices: Range, index_size: i64, count: i64, instances: i64,
                first_index: i64, vertex_offset: i64, first_instance: i64) {
    draw_indexed_raw(root, indices.address, indices.size, index_size, count, instances, first_index,
                     vertex_offset, first_instance)
}
fn draw_indexed(root: u64, indices: Range, index_size: i64, count: i64) {
    draw_indexed(root, indices, index_size, count, 1, 0, 0, 0)
}
fn draw_indexed_instanced(root: u64, indices: Range, index_size: i64, count: i64, instances: i64) {
    draw_indexed(root, indices, index_size, count, instances, 0, 0, 0)
}
fn draw_indexed(root: u64, indices: Buffer, index_size: i64, count: i64, instances: i64,
                first_index: i64, vertex_offset: i64, first_instance: i64) {
    draw_indexed(root, range(indices), index_size, count, instances, first_index, vertex_offset,
                 first_instance)
}
fn draw_indexed(root: u64, indices: Buffer, index_size: i64, count: i64) {
    draw_indexed(root, range(indices), index_size, count, 1, 0, 0, 0)
}
fn draw_indexed_instanced(root: u64, indices: Buffer, index_size: i64, count: i64,
                          instances: i64) {
    draw_indexed(root, range(indices), index_size, count, instances, 0, 0, 0)
}

// Draws whose arguments the GPU reads from memory at `arguments`, such as a
// dispatch wrote, behind a barrier(COMPUTE_WRITE, STAGE_INDIRECT |
// ACCESS_INDIRECT_READ): `count` commands, each a DrawArguments or
// DrawIndexedArguments, `stride` bytes apart (0: packed).
struct DrawArguments { vertices: u32, instances: u32, first_vertex: u32, first_instance: u32 }
struct DrawIndexedArguments { count: u32, instances: u32, first_index: u32, vertex_offset: i32,
                              first_instance: u32 }
extern fn draw_indirect(root: u64, arguments: u64, count: i64, stride: i64) = "ngfx_draw_indirect";
fn draw_indirect(root: u64, arguments: u64) { draw_indirect(root, arguments, 1, 0) }
extern fn draw_indexed_indirect_raw(root: u64, indices: u64,
                                    indices_size: i64,
                                    index_size: i64, arguments: u64,
                                    count: i64, stride: i64) = "ngfx_draw_indexed_indirect";
fn draw_indexed_indirect(root: u64, indices: Range, index_size: i64, arguments: u64, count: i64,
                         stride: i64) {
    draw_indexed_indirect_raw(root, indices.address, indices.size, index_size, arguments, count,
                              stride)
}
fn draw_indexed_indirect(root: u64, indices: Range, index_size: i64, arguments: u64) {
    draw_indexed_indirect(root, indices, index_size, arguments, 1, 0)
}
fn draw_indexed_indirect(root: u64, indices: Buffer, index_size: i64, arguments: u64, count: i64,
                         stride: i64) {
    draw_indexed_indirect(root, range(indices), index_size, arguments, count, stride)
}
fn draw_indexed_indirect(root: u64, indices: Buffer, index_size: i64, arguments: u64) {
    draw_indexed_indirect(root, range(indices), index_size, arguments, 1, 0)
}

// --- compute -------------------------------------------------------------------

// Dispatches go between passes. What a dispatch writes reaches a later pass
// or dispatch only after a barrier (see synchronization below).
extern fn bind(p: ComputePipeline) = "ngfx_bind_compute_pipeline";
// Runs x * y * z thread groups of the shader's numthreads.
extern fn dispatch(root: u64, x: i64, y: i64, z: i64) = "ngfx_dispatch";
// The same, with the thread group counts a DispatchArguments at `arguments`
// holds, which the GPU reads (see draw_indirect).
struct DispatchArguments { x: u32, y: u32, z: u32 }
extern fn dispatch_indirect(root: u64, arguments: u64) = "ngfx_dispatch_indirect";

// --- synchronization -------------------------------------------------------------

// What `before` did, before `after` does it: barrier(COMPUTE_WRITE,
// FRAGMENT_READ) when a pass samples what a dispatch wrote. Between passes
// and dispatches, never inside a pass. Each side is barrier points
// combined with |.
extern fn barrier(before: i32, after: i32) = "ngfx_barrier";

// --- mips ------------------------------------------------------------------------

// The root of the layer's downsampling shader (native/ngfx_mips.slang).
// A root's size is a multiple of 16 bytes (NoGraphicsAPI's docs/slang.md).
struct MipRoot { source: u32, target: u32, level: u32, width: u32, height: u32, source_width: u32,
                 source_height: u32, unused: u32 }

// generate_mips' pipeline: the layer's downsampling shader
// (native/ngfx_mips.slang), which takes a MipRoot and makes each texel of
// a level the average of the 2 x 2 above it. It is built with the layer, not
// embedded here, where every program importing ngfx would compile it.
extern fn mip_pipeline() -> ComputePipeline = "ngfx_mip_pipeline";

// Fills mips 1 and up of a 2D texture from mip 0, a compute dispatch per
// level with a barrier between them. The texture needs SAMPLED | STORAGE
// usage, so a format storage can write: not an sRGB one. Not inside a pass.
// What wrote mip 0 is ordered before this by the program (an upload is
// ngfx's), and so is what reads the levels after it:
//   ngfx::generate_mips(t);
//   ngfx::barrier(ngfx::COMPUTE_WRITE, ngfx::FRAGMENT_READ);
fn generate_mips(t: Texture) {
    let info = texture_info(t);
    if info.kind != TEXTURE_2D || (info.usage & (SAMPLED | STORAGE)) != SAMPLED | STORAGE {
        abort("ngfx: generate_mips takes a 2D texture with SAMPLED | STORAGE usage");
    }
    bind(mip_pipeline());
    var width = info.width as i64;
    var height = info.height as i64;
    for level in 1..info.mips as i64 {
        let w = max(width / 2, 1);
        let h = max(height / 2, 1);
        if level > 1 { barrier(COMPUTE_WRITE, COMPUTE_READ); }
        dispatch(root(MipRoot { source: index(t), target: storage_index(t, level), level: (level - 1) as u32,
                                width: w as u32, height: h as u32, source_width: width as u32,
                                source_height: height as u32, unused: 0 }),
                 (w + 7) / 8, (h + 7) / 8, 1);
        width = w;
        height = h;
    }
}

// --- matrices ------------------------------------------------------------------

// A row-major 4x4 matrix, as NoGraphicsAPIUtility's float4x4 and Slang's
// (built with -matrix-layout-row-major) are laid out: m * v is
// mul(root.m, v) in a shader.
struct float4x4 { rows: float4[4] }

let float4x4_identity = float4x4 { rows: [float4 { 1.0, 0.0, 0.0, 0.0 }, float4 { 0.0, 1.0, 0.0, 0.0 },
                                          float4 { 0.0, 0.0, 1.0, 0.0 }, float4 { 0.0, 0.0, 0.0, 1.0 }] };

fn column(m: float4x4, i: i64) -> float4 {
    match i {
        0 => float4 { m.rows[0].x, m.rows[1].x, m.rows[2].x, m.rows[3].x },
        1 => float4 { m.rows[0].y, m.rows[1].y, m.rows[2].y, m.rows[3].y },
        2 => float4 { m.rows[0].z, m.rows[1].z, m.rows[2].z, m.rows[3].z },
        _ => float4 { m.rows[0].w, m.rows[1].w, m.rows[2].w, m.rows[3].w },
    }
}

fn transpose(m: float4x4) -> float4x4 {
    float4x4 { rows: [column(m, 0), column(m, 1), column(m, 2), column(m, 3)] }
}

fn mul(m: float4x4, v: float4) -> float4 {
    float4 { dot(m.rows[0], v), dot(m.rows[1], v), dot(m.rows[2], v), dot(m.rows[3], v) }
}

fn mul(a: float4x4, b: float4x4) -> float4x4 {
    let t = transpose(b);
    var m = float4x4_identity;
    for i in 4 { m.rows[i] = mul(t, a.rows[i]); }
    m
}

fn translate(t: float3) -> float4x4 {
    float4x4 { rows: [float4 { 1.0, 0.0, 0.0, t.x }, float4 { 0.0, 1.0, 0.0, t.y },
                      float4 { 0.0, 0.0, 1.0, t.z }, float4 { 0.0, 0.0, 0.0, 1.0 }] }
}

fn scale(s: float3) -> float4x4 {
    float4x4 { rows: [float4 { s.x, 0.0, 0.0, 0.0 }, float4 { 0.0, s.y, 0.0, 0.0 },
                      float4 { 0.0, 0.0, s.z, 0.0 }, float4 { 0.0, 0.0, 0.0, 1.0 }] }
}

// A rotation of `angle` radians about `axis`, counterclockwise looking down
// the axis.
fn rotate(axis: float3, angle: f32) -> float4x4 {
    let a = normalize(axis);
    let c = cos(angle);
    let s = sin(angle);
    let k = 1.0 - c;
    float4x4 { rows: [float4 { c + a.x * a.x * k, a.x * a.y * k - a.z * s, a.x * a.z * k + a.y * s, 0.0 },
                      float4 { a.y * a.x * k + a.z * s, c + a.y * a.y * k, a.y * a.z * k - a.x * s, 0.0 },
                      float4 { a.z * a.x * k - a.y * s, a.z * a.y * k + a.x * s, c + a.z * a.z * k, 0.0 },
                      float4 { 0.0, 0.0, 0.0, 1.0 }] }
}

// Right-handed, looking down -z, to NoGraphicsAPI's clip space: y down, depth
// 0 at `near` and 1 at `far`. gfx's perspective with y negated, as
// NoGraphicsAPI's examples negate perspective_rh_zo's.
fn perspective(fovy: f32, aspect: f32, near: f32, far: f32) -> float4x4 {
    let f = 1.0 / tan(fovy * 0.5);
    float4x4 { rows: [float4 { f / aspect, 0.0, 0.0, 0.0 }, float4 { 0.0, -f, 0.0, 0.0 },
                      float4 { 0.0, 0.0, far / (near - far), near * far / (near - far) },
                      float4 { 0.0, 0.0, -1.0, 0.0 }] }
}

// `bottom` and `top` are where y is at the screen's bottom and top edges:
// ortho(0, w, h, 0, ...) is pixels with y down, as it is in gfx.
fn ortho(left: f32, right: f32, bottom: f32, top: f32, near: f32, far: f32) -> float4x4 {
    float4x4 { rows: [float4 { 2.0 / (right - left), 0.0, 0.0, (left + right) / (left - right) },
                      float4 { 0.0, 2.0 / (bottom - top), 0.0, (top + bottom) / (top - bottom) },
                      float4 { 0.0, 0.0, 1.0 / (near - far), near / (near - far) },
                      float4 { 0.0, 0.0, 0.0, 1.0 }] }
}

fn look_at(eye: float3, target: float3, up: float3) -> float4x4 {
    let f = normalize(target - eye);
    let s = normalize(cross(f, up));
    let u = cross(s, f);
    float4x4 { rows: [float4 { s.x, s.y, s.z, -dot(s, eye) }, float4 { u.x, u.y, u.z, -dot(u, eye) },
                      float4 { -f.x, -f.y, -f.z, dot(f, eye) }, float4 { 0.0, 0.0, 0.0, 1.0 }] }
}

// --- helpers -------------------------------------------------------------------

// The bytes an element of `xs` takes: what bytes_of gives for one.
fn elem_size<T>(xs: T[>..]&) -> i64 {
    let one: T[1] = [default<T>()];
    bytes_of(one).len
}

// Appends bytes read back from the GPU to `out` as elements of its flat T,
// through from_bytes' image format: a LEB128 byte count, then the elements.
fn append_as<T>(raw: const u8[:], out: T[>..]&) {
    var image: u8[>..] = [];
    var n = raw.len as u64;
    loop {
        let low = (n & 127) as u8;
        n >>= 7;
        if n == 0 {
            image.push(low);
            break;
        }
        image.push(low | 128);
    }
    image.append(raw);
    var elems, ok = from_bytes<T[>..]>(image);
    assert(ok);
    out.append(elems);
}
