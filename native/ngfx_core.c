/* The ngfx layer's core: errors, open and close, and the end of each frame.
   ngfx has no window of its own: the program hands it a native one (a
   CAMetalLayer on Apple's systems, an HWND on Windows), usually from gfx
   opened WINDOW_ONLY, and owns its input, events and time. The GPU half is
   ngfx_device.cpp. */

#include "ngfx_internal.h"

#include <stdarg.h>
#include <stdlib.h>
#include <string.h>

#if defined(__APPLE__)
#include <objc/message.h>
#endif

/* Static, so a program that compiles stb itself links with ngfx. */
#define STB_IMAGE_STATIC
#define STB_IMAGE_IMPLEMENTATION
#define STBI_ONLY_PNG
#define STBI_ONLY_BMP
#define STBI_NO_STDIO_WIDE
#include "stb_image.h"
#define STB_IMAGE_WRITE_STATIC
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"

typedef struct {
    bool open;
    bool windowed;
    void *layer;
    int64_t frames;                     /* frames presented since open */
    char error[1024];
    int64_t misuse;
} ngfx_core_state;

static ngfx_core_state ngfx;

/* How many times ngfx was opened, which close() leaves. */
static int64_t ngfx_opens;

/* --- errors ---------------------------------------------------------------- */

static void ngfx_vset(const char *fmt, va_list args) {
    vsnprintf(ngfx.error, sizeof ngfx.error, fmt, args);
}

bool ngfx_fail(const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    ngfx_vset(fmt, args);
    va_end(args);
    return false;
}

bool ngfx_misuse(const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    ngfx_vset(fmt, args);
    va_end(args);
    if (++ngfx.misuse <= 8) fprintf(stderr, "ngfx: %s\n", ngfx.error);
    return false;
}

bool ngfx_need_main_thread(const char *what) {
    if (ngfx_gpu_on_main_thread()) return true;
    return ngfx_misuse("%s: ngfx runs on the main thread only", what);
}

bool ngfx_need_open(const char *what) {
    if (ngfx.open) return true;
    return ngfx_misuse("%s: ngfx is not open (call ngfx::open or ngfx::open_headless first)", what);
}

bool ngfx_need_device(const char *what) {
    return ngfx_need_main_thread(what) && ngfx_need_open(what);
}

const char *ngfx_error_text(void) { return ngfx.error; }

void ngfx_error(gs_rref out) { gs_bld_append(out, ngfx.error, (int64_t)strlen(ngfx.error)); }

int64_t ngfx_misuse_count(void) { return ngfx.misuse; }

const char *ngfx_cstr(ngfx_bytes s, char *buf, size_t cap) {
    size_t n = s.len < 0 ? 0 : (size_t)s.len;
    if (n >= cap) n = cap - 1;
    if (n) memcpy(buf, s.data, n);
    buf[n] = 0;
    return buf;
}

/* --- open and close -------------------------------------------------------- */

/* The window's image at the screen's size, which a pass into the screen
   needs; on Apple's systems the layer is told, as SDL's view may not have
   followed a resize yet. Elsewhere the swapchain follows the window, or on
   Wayland the screen's size (create_screen). */
static void ngfx_size_layer(int64_t width, int64_t height) {
#if defined(__APPLE__)
    if (!ngfx.layer) return;
    typedef struct { double width, height; } size;
    ((void (*)(void *, SEL, size))objc_msgSend)(ngfx.layer, sel_registerName("setDrawableSize:"),
                                                (size){(double)width, (double)height});
#else
    (void)width;
    (void)height;
#endif
}

uint8_t ngfx_available(void) { return 1; }

/* The device, drawing into `window`; on Linux a Wayland surface or an X11
   window, as `kind` says, on `display`. */
uint8_t ngfx_open(uint64_t window, int64_t width, int64_t height, int64_t flags,
                  uint64_t display, int64_t kind) {
    if (!ngfx_need_main_thread("open")) return 0;
    if (ngfx.open) return ngfx_misuse("ngfx is already open: close() it first");
    if (width < 1 || height < 1 || width > 16384 || height > 16384)
        return ngfx_misuse("a screen of %lld x %lld pixels", (long long)width, (long long)height);
    void *layer = (void *)(uintptr_t)window;
#if defined(__linux__) && !defined(__ANDROID__)
    if (layer && (!display || (kind != NGFX_NATIVE_WAYLAND && kind != NGFX_NATIVE_X11)))
        return ngfx_misuse("open() on Linux takes the window's display and kind (gfx's "
                           "native_display() and native_kind()), not %llx and %lld",
                           (unsigned long long)display, (long long)kind);
#elif !defined(__APPLE__) && !defined(_WIN32)
    if (layer) return ngfx_fail("NoGraphicsAPI cannot present on this platform; open headless");
#endif
    /* For the benchmarks (bench/run_bench.py), as the flag. */
    const char *no_vsync = getenv("GOOSE_NGFX_NO_VSYNC");
    if (no_vsync && atoi(no_vsync)) flags |= NGFX_NO_VSYNC;
#if defined(__APPLE__)
    /* NoGraphicsAPI leaves the layer's displaySyncEnabled alone; on Vulkan it
       fixes FIFO. */
    if (layer && (flags & NGFX_NO_VSYNC))
        ((void (*)(void *, SEL, bool))objc_msgSend)(layer, sel_registerName("setDisplaySyncEnabled:"), false);
#endif
    ngfx.error[0] = 0;
    ngfx.open = true;
    ngfx.windowed = layer != NULL;
    ngfx.layer = layer;
    ngfx_size_layer(width, height);
    if (!ngfx_gpu_open(layer, (void *)(uintptr_t)display, kind == NGFX_NATIVE_X11, (int)width,
                       (int)height, !(flags & NGFX_NO_VSYNC))) {
        char why[sizeof ngfx.error];
        memcpy(why, ngfx.error, sizeof why);
        ngfx_close();
        memcpy(ngfx.error, why, sizeof why);
        return false;
    }
    ngfx_opens++;
    return true;
}

uint8_t ngfx_open_headless(int64_t width, int64_t height, int64_t flags) {
    return ngfx_open(0, width, height, flags, 0, 0);
}

void ngfx_close(void) {
    ngfx_gpu_close();
    char error[sizeof ngfx.error];
    memcpy(error, ngfx.error, sizeof error);
    int64_t misuse = ngfx.misuse;
    memset(&ngfx, 0, sizeof ngfx);
    memcpy(ngfx.error, error, sizeof error);
    ngfx.misuse = misuse;
}

void ngfx_driver(gs_rref out) {
    const char *name = ngfx.open ? ngfx_gpu_driver() : "";
    gs_bld_append(out, name, (int64_t)strlen(name));
}

/* --- frames ------------------------------------------------------------------ */

/* Ends the frame: submits it, showing it in the window when it drew into
   the screen; then starts the next one. Whether it showed one, for the
   program's platform to wait on when not. */
uint8_t ngfx_present(void) {
    if (!ngfx_need_device("present")) return 0;
    if (ngfx_gpu_in_pass()) return ngfx_misuse("present() inside a pass: end the pass first");
    bool shown = ngfx_gpu_next_frame();
    if (shown) ngfx.frames++;
    return shown;
}

/* The window's new size in pixels: the screen follows it. */
void ngfx_resize(int64_t width, int64_t height) {
    if (!ngfx_need_device("resize")) return;
    if (width < 1 || height < 1 || width > 16384 || height > 16384) {
        ngfx_misuse("resize to %lld x %lld pixels", (long long)width, (long long)height);
        return;
    }
    int w, h;
    ngfx_gpu_screen_size(&w, &h);
    if (w == width && h == height) return;
    ngfx_size_layer(width, height);
    ngfx_gpu_resize((int)width, (int)height);
}

void ngfx_flush(void) {
    if (!ngfx_need_device("flush")) return;
    if (ngfx_gpu_in_pass()) {
        ngfx_misuse("flush inside a pass: end the pass first");
        return;
    }
    ngfx_gpu_finish();
}

void ngfx_screen_size(ngfx_int2 *out) {
    int w = 0, h = 0;
    if (ngfx.open) ngfx_gpu_screen_size(&w, &h);
    out->x = w;
    out->y = h;
}

int64_t ngfx_frame_count(void) { return ngfx.frames; }

int64_t ngfx_open_count(void) { return ngfx_opens; }

/* --- images ------------------------------------------------------------------ */

bool ngfx_png_load(const char *path, uint8_t **rgba, int *w, int *h) {
    int channels = 0;
    uint8_t *px = stbi_load(path, w, h, &channels, 4);
    if (!px) return ngfx_fail("cannot load %s: %s", path, stbi_failure_reason());
    *rgba = px;
    return true;
}

bool ngfx_png_save(const char *path, const uint8_t *rgba, int w, int h, bool bgra) {
    const uint8_t *px = rgba;
    uint8_t *swapped = NULL;
    if (bgra) {
        size_t n = (size_t)w * (size_t)h * 4;
        swapped = (uint8_t *)malloc(n);
        if (!swapped) return ngfx_fail("save_png: out of memory");
        for (size_t i = 0; i < n; i += 4) {
            swapped[i] = rgba[i + 2];
            swapped[i + 1] = rgba[i + 1];
            swapped[i + 2] = rgba[i];
            swapped[i + 3] = rgba[i + 3];
        }
        px = swapped;
    }
    bool ok = stbi_write_png(path, w, h, 4, px, w * 4) != 0;
    free(swapped);
    return ok || ngfx_fail("save_png: cannot write %s", path);
}

void ngfx_png_free(uint8_t *rgba) { stbi_image_free(rgba); }
