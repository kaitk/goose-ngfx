/* The ngfx layer's C API: every function lib/ngfx.goose reaches through an
   `extern "ngfx_..." fn`, listed once in NGFX_API. That list expands
   into the prototypes below, and scripts/api_check.py checks
   lib/ngfx.goose against it.

   ngfx is gfx's platform half (window, input, time, the screen, textures and
   read-back) over NoGraphicsAPI, with NoGraphicsAPI's way of drawing: a draw
   takes the GPU address of a root struct the program fills, buffers are
   plain GPU memory with addresses, and textures and samplers are indices
   into heaps the layer owns (docs/design.md).

   The conventions are gfx's (src/gfx/gfx_api.h): what crosses is what
   `extern fn` can pass; structs are packed and declared again in
   lib/ngfx.goose with the same fields; handles are one u32 with a
   generation, 0 never valid; failures outside the program return false or a
   zero handle with the reason in ngfx_error, and misuse is counted for
   the Goose side to abort on. */

#ifndef NGFX_API_H
#define NGFX_API_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#pragma pack(push, 1)

typedef struct { uint8_t *data; int64_t len; } ngfx_bytes;   /* u8[:] */

typedef struct { uint32_t id; } ngfx_buffer;
typedef struct { uint32_t id; } ngfx_texture;
typedef struct { uint32_t id; } ngfx_sampler;
typedef struct { uint32_t id; } ngfx_pipeline;
typedef struct { uint32_t id; } ngfx_compute_pipeline;

/* One input event of a frame, as gfx's. */
typedef struct {
    int32_t kind;
    int32_t scancode;
    int32_t keycode;
    int32_t mods;
    uint8_t down;
    uint8_t repeat;
    int32_t button;
    int32_t clicks;
    uint32_t codepoint;
    float x, y;
} ngfx_event;

typedef struct { ngfx_event *data; int64_t len; } ngfx_event_slice;

typedef struct { int32_t x, y; } ngfx_int2;
typedef struct { float x, y; } ngfx_float2;
typedef struct { float x, y, z, w; } ngfx_float4;

typedef struct {
    int32_t kind, format, usage;
    int32_t width, height;
    int32_t depth;              /* a 3D texture's depth, or an array's layers */
    int32_t mips;               /* 0: the full chain */
} ngfx_texture_desc;

/* Part of one mip of one layer. w == 0 means the whole mip. */
typedef struct {
    int32_t mip, layer;
    int32_t x, y, z;
    int32_t w, h, d;
} ngfx_region;

typedef struct {
    int32_t min_filter, mag_filter, mip_filter;
    int32_t wrap_u, wrap_v, wrap_w;
    float max_anisotropy;       /* more than 1: NoGraphicsAPI's fixed 4x */
    int32_t compare;            /* a COMPARE_*, for a shadow sampler; 0: none */
} ngfx_sampler_desc;

/* What a pipeline adds to its shaders. The formats it draws into come from
   the pass it is bound in: one NoGraphicsAPI PSO per set of them. */
typedef struct {
    int32_t cull;
    uint8_t clockwise;          /* front faces wind clockwise */
    uint8_t depth_test, depth_write;
    int32_t depth_compare, blend;
    float depth_bias, depth_bias_slope;
} ngfx_pipeline_desc;

typedef struct {
    ngfx_texture color[4];   /* the targets, up to the first 0 */
    ngfx_texture depth;      /* 0: none */
    int32_t layer, mip;         /* of the targets */
    uint8_t clear_color, clear_depth;
    ngfx_float4 color_value;
    float depth_value;
} ngfx_pass_desc;

#pragma pack(pop)

#define NGFX_API(X) \
    /* Device, window and frames. */ \
    X(uint8_t, ngfx_available, (void)) \
    X(uint8_t, ngfx_open, (ngfx_bytes title, int64_t width, int64_t height, int64_t flags)) \
    X(uint8_t, ngfx_open_headless, (int64_t width, int64_t height, int64_t flags)) \
    X(void, ngfx_close, (void)) \
    X(int64_t, ngfx_error, (ngfx_bytes out)) \
    X(int64_t, ngfx_misuse_count, (void)) \
    X(int64_t, ngfx_driver, (ngfx_bytes out)) \
    X(uint8_t, ngfx_frame, (void)) \
    X(void, ngfx_quit, (void)) \
    X(void, ngfx_flush, (void)) \
    X(void, ngfx_set_title, (ngfx_bytes title)) \
    X(void, ngfx_screen_size, (ngfx_int2 *out)) \
    X(ngfx_texture, ngfx_screen, (void)) \
    X(ngfx_texture, ngfx_screen_depth, (void)) \
    X(double, ngfx_time, (void)) \
    X(double, ngfx_delta_time, (void)) \
    X(int64_t, ngfx_frame_count, (void)) \
    X(int64_t, ngfx_open_count, (void)) \
    /* Input. */ \
    X(uint8_t, ngfx_key_down, (ngfx_bytes name)) \
    X(uint8_t, ngfx_key_pressed, (ngfx_bytes name)) \
    X(uint8_t, ngfx_key_released, (ngfx_bytes name)) \
    X(uint8_t, ngfx_mouse_down, (int64_t button)) \
    X(uint8_t, ngfx_mouse_pressed, (int64_t button)) \
    X(uint8_t, ngfx_mouse_released, (int64_t button)) \
    X(void, ngfx_mouse_pos, (ngfx_float2 *out)) \
    X(void, ngfx_mouse_delta, (ngfx_float2 *out)) \
    X(float, ngfx_mouse_wheel, (void)) \
    X(uint8_t, ngfx_mouse_in_window, (void)) \
    X(uint8_t, ngfx_focused, (void)) \
    X(uint8_t, ngfx_set_mouse_relative, (uint8_t on)) \
    X(uint8_t, ngfx_mouse_relative, (void)) \
    X(uint8_t, ngfx_set_cursor_visible, (uint8_t visible)) \
    X(uint8_t, ngfx_cursor_visible, (void)) \
    X(uint8_t, ngfx_inject_focus, (uint8_t focused)) \
    X(uint8_t, ngfx_inject_key, (ngfx_bytes name, uint8_t down)) \
    X(void, ngfx_inject_mouse, (float x, float y, int64_t button, uint8_t down)) \
    X(int64_t, ngfx_events, (ngfx_event_slice out)) \
    X(void, ngfx_text_input, (uint8_t on)) \
    X(uint8_t, ngfx_inject_text, (ngfx_bytes text)) \
    X(int64_t, ngfx_scancode, (ngfx_bytes name)) \
    X(int64_t, ngfx_key_name, (int64_t scancode, ngfx_bytes out)) \
    X(int64_t, ngfx_clipboard, (ngfx_bytes out)) \
    X(uint8_t, ngfx_set_clipboard, (ngfx_bytes text)) \
    /* Buffers: GPU memory with an address, and this frame's data. */ \
    X(ngfx_buffer, ngfx_create_buffer, (int64_t size, ngfx_bytes data)) \
    X(uint8_t, ngfx_update_buffer, (ngfx_buffer b, int64_t offset, ngfx_bytes data)) \
    X(uint8_t, ngfx_read_buffer, (ngfx_buffer b, int64_t offset, ngfx_bytes out)) \
    X(int64_t, ngfx_buffer_size, (ngfx_buffer b)) \
    X(uint64_t, ngfx_buffer_address, (ngfx_buffer b)) \
    X(void, ngfx_release_buffer, (ngfx_buffer b)) \
    X(uint64_t, ngfx_frame_data, (ngfx_bytes data)) \
    /* Textures and samplers. */ \
    X(ngfx_texture, ngfx_create_texture, (const ngfx_texture_desc *desc)) \
    X(ngfx_texture, ngfx_load_texture, (ngfx_bytes path, int64_t flags)) \
    X(uint8_t, ngfx_update_texture, (ngfx_texture t, const ngfx_region *region, ngfx_bytes data)) \
    X(uint8_t, ngfx_read_texture, (ngfx_texture t, const ngfx_region *region, ngfx_bytes out)) \
    X(uint8_t, ngfx_save_png, (ngfx_texture t, ngfx_bytes path)) \
    X(uint8_t, ngfx_texture_info, (ngfx_texture t, ngfx_texture_desc *out)) \
    X(uint32_t, ngfx_texture_index, (ngfx_texture t)) \
    X(uint32_t, ngfx_storage_index, (ngfx_texture t)) \
    X(uint32_t, ngfx_storage_mip_index, (ngfx_texture t, int64_t mip)) \
    X(void, ngfx_release_texture, (ngfx_texture t)) \
    X(ngfx_sampler, ngfx_create_sampler, (const ngfx_sampler_desc *desc)) \
    X(uint32_t, ngfx_sampler_index, (ngfx_sampler s)) \
    X(void, ngfx_release_sampler, (ngfx_sampler s)) \
    /* Slang modules compiled into blobs (ngfx_slang.cpp, ngfx_blob.h). */ \
    X(int64_t, ngfx_compile_slang, (ngfx_bytes source)) \
    X(int64_t, ngfx_compile_slang_file, (ngfx_bytes path)) \
    X(int64_t, ngfx_slang_result, (ngfx_bytes out)) \
    /* Pipelines, from those blobs. */ \
    X(ngfx_pipeline, ngfx_create_pipeline, (ngfx_bytes shader, ngfx_bytes vertex, ngfx_bytes fragment, const ngfx_pipeline_desc *desc)) \
    X(void, ngfx_release_pipeline, (ngfx_pipeline p)) \
    X(ngfx_compute_pipeline, ngfx_create_compute_pipeline, (ngfx_bytes shader, ngfx_bytes entry)) \
    X(void, ngfx_release_compute_pipeline, (ngfx_compute_pipeline p)) \
    X(ngfx_compute_pipeline, ngfx_mip_pipeline, (void)) \
    /* Passes, drawing and compute. */ \
    X(uint8_t, ngfx_begin_pass, (const ngfx_pass_desc *desc)) \
    X(void, ngfx_end_pass, (void)) \
    X(void, ngfx_bind_pipeline, (ngfx_pipeline p)) \
    X(void, ngfx_bind_compute_pipeline, (ngfx_compute_pipeline p)) \
    X(void, ngfx_viewport, (float x, float y, float w, float h)) \
    X(void, ngfx_scissor, (int64_t x, int64_t y, int64_t w, int64_t h)) \
    X(void, ngfx_draw, (uint64_t root, int64_t vertices, int64_t instances, int64_t first_vertex, int64_t first_instance)) \
    X(void, ngfx_draw_indexed, (uint64_t root, ngfx_buffer indices, int64_t index_size, int64_t count, int64_t instances, int64_t first_index, int64_t vertex_offset, int64_t first_instance)) \
    X(void, ngfx_dispatch, (uint64_t root, int64_t x, int64_t y, int64_t z)) \
    /* Synchronization the program states: what `before` did, before `after` does it. */ \
    X(void, ngfx_barrier, (int32_t before, int32_t after))

#define NGFX_PROTO(ret, name, params) ret name params;
NGFX_API(NGFX_PROTO)
#undef NGFX_PROTO

/* The constants lib/ngfx.goose declares, with their Goose types; here they
   are NGFX_<name>. The ones gfx also has keep gfx's values. */
#define NGFX_CONSTANTS(X) \
    /* open() and open_headless() flags. */ \
    X(i32, WINDOW_RESIZABLE, 1) \
    X(i32, WINDOW_HIDDEN, 2) \
    X(i32, WINDOW_FULLSCREEN, 4) \
    /* Texture kinds. */ \
    X(i32, TEXTURE_2D, 0) \
    X(i32, TEXTURE_2D_ARRAY, 1) \
    X(i32, TEXTURE_3D, 2) \
    X(i32, TEXTURE_CUBE, 3) \
    /* Texture usage, combined with |. */ \
    X(i32, SAMPLED, 1) \
    X(i32, COLOR_TARGET, 2) \
    X(i32, DEPTH_TARGET, 4) \
    X(i32, STORAGE, 8) \
    /* Texture formats. DEPTH is DEPTH32F. */ \
    X(i32, RGBA8, 1) \
    X(i32, BGRA8, 2) \
    X(i32, RGBA8_SRGB, 3) \
    X(i32, R8, 4) \
    X(i32, RG8, 5) \
    X(i32, RGBA16F, 6) \
    X(i32, RGBA32F, 7) \
    X(i32, R16F, 8) \
    X(i32, RG16F, 9) \
    X(i32, R32F, 10) \
    X(i32, RG32F, 11) \
    X(i32, R32UI, 12) \
    X(i32, RGBA8UI, 13) \
    X(i32, RGB10A2, 14) \
    X(i32, RG11B10F, 15) \
    X(i32, DEPTH16, 16) \
    X(i32, DEPTH32F, 18) \
    X(i32, DEPTH24_STENCIL8, 19) \
    X(i32, DEPTH, 20) \
    /* Samplers. */ \
    X(i32, NEAREST, 0) \
    X(i32, LINEAR, 1) \
    X(i32, REPEAT, 0) \
    X(i32, MIRROR, 1) \
    X(i32, CLAMP, 2) \
    X(i32, COMPARE_NEVER, 1) \
    X(i32, COMPARE_LESS, 2) \
    X(i32, COMPARE_EQUAL, 3) \
    X(i32, COMPARE_LESS_EQUAL, 4) \
    X(i32, COMPARE_GREATER, 5) \
    X(i32, COMPARE_NOT_EQUAL, 6) \
    X(i32, COMPARE_GREATER_EQUAL, 7) \
    X(i32, COMPARE_ALWAYS, 8) \
    /* Pipelines. */ \
    X(i32, CULL_NONE, 0) \
    X(i32, CULL_FRONT, 1) \
    X(i32, CULL_BACK, 2) \
    X(i32, BLEND_NONE, 0) \
    X(i32, BLEND_ALPHA, 1) \
    X(i32, BLEND_ADD, 2) \
    X(i32, BLEND_PREMULTIPLIED, 3) \
    X(i32, BLEND_MULTIPLY, 4) \
    /* load_texture() flags. */ \
    X(i32, LOAD_SRGB, 2) \
    /* Barrier points: a NoGraphicsAPI Stage mask in bits 0-11 and an Access mask in bits 16-27, each with
       NoGraphicsAPI's own bit values, so points combine with | as its masks do. */ \
    X(i32, STAGE_INDIRECT, 1) \
    X(i32, STAGE_INDEX_INPUT, 2) \
    X(i32, STAGE_VERTEX, 4) \
    X(i32, STAGE_TASK, 8) \
    X(i32, STAGE_MESH, 16) \
    X(i32, STAGE_DEPTH, 32) \
    X(i32, STAGE_FRAGMENT, 64) \
    X(i32, STAGE_COLOR_OUTPUT, 128) \
    X(i32, STAGE_COMPUTE, 256) \
    X(i32, STAGE_TRANSFER, 512) \
    X(i32, STAGE_ALL, 2048) \
    X(i32, ACCESS_TRANSFER_READ, 65536) \
    X(i32, ACCESS_TRANSFER_WRITE, 131072) \
    X(i32, ACCESS_SHADER_READ, 262144) \
    X(i32, ACCESS_SHADER_WRITE, 524288) \
    X(i32, ACCESS_COLOR_READ, 1048576) \
    X(i32, ACCESS_COLOR_WRITE, 2097152) \
    X(i32, ACCESS_DEPTH_READ, 4194304) \
    X(i32, ACCESS_DEPTH_WRITE, 8388608) \
    X(i32, ACCESS_INDIRECT_READ, 16777216) \
    X(i32, ACCESS_INDEX_READ, 33554432) \
    X(i32, ACCESS_DESCRIPTOR_READ, 134217728) \
    /* Named points: STAGE_ | ACCESS_ combinations. */ \
    X(i32, COMPUTE_WRITE, 524544) \
    X(i32, COMPUTE_READ, 262400) \
    X(i32, VERTEX_READ, 262148) \
    X(i32, FRAGMENT_READ, 262208) \
    X(i32, TARGET_WRITE, 10485920) \
    X(i32, INDEX_READ, 33554434) \
    /* Mouse buttons. */ \
    X(i32, MOUSE_LEFT, 1) \
    X(i32, MOUSE_MIDDLE, 2) \
    X(i32, MOUSE_RIGHT, 3) \
    X(i32, MOUSE_X1, 4) \
    X(i32, MOUSE_X2, 5) \
    /* Input events, and the modifier keys held with a key. */ \
    X(i32, EVENT_KEY, 1) \
    X(i32, EVENT_TEXT, 2) \
    X(i32, EVENT_MOUSE_MOTION, 3) \
    X(i32, EVENT_MOUSE_BUTTON, 4) \
    X(i32, EVENT_MOUSE_WHEEL, 5) \
    X(i32, EVENT_FOCUS_GAINED, 6) \
    X(i32, EVENT_FOCUS_LOST, 7) \
    X(i32, MOD_SHIFT, 1) \
    X(i32, MOD_CTRL, 2) \
    X(i32, MOD_ALT, 4) \
    X(i32, MOD_GUI, 8)

#define NGFX_ENUM(type, name, value) NGFX_##name = value,
enum { NGFX_CONSTANTS(NGFX_ENUM) };
#undef NGFX_ENUM

#ifdef __cplusplus
}
#endif

#endif
