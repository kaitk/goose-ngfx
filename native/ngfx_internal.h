/* Shared by the ngfx layer's own files in native/, never by a program.
   ngfx_core.c holds errors, open and close, and the frame's end; the GPU
   half is C++ over NoGraphicsAPI (ngfx_gpu.hpp), reached through the hooks
   below. Everything is main-thread only, as the window it draws into is. */

#ifndef NGFX_INTERNAL_H
#define NGFX_INTERNAL_H

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>

#include "ngfx_api.h"

#ifdef __cplusplus
extern "C" {
#endif

/* --- errors (ngfx_core.c) ------------------------------------------------- */

/* Something outside the program's control failed: the reason is kept for
   ngfx_error. Returns false, for `return ngfx_fail(...)`. */
bool ngfx_fail(const char *fmt, ...);
/* The program used the API wrongly: kept, counted and printed, and the
   Goose side aborts on it at the next frame. Returns false. */
bool ngfx_misuse(const char *fmt, ...);
/* True inside open() .. close() on the main thread; a misuse to call
   `what` otherwise. */
bool ngfx_need_device(const char *what);
/* ngfx_need_device without the thread check, for the calls made per draw:
   main_thread_only in ngfx.build already makes the compiler reject a
   thread_fn that reaches them. */
bool ngfx_need_open(const char *what);
/* False, after counting a misuse, off the main thread. */
bool ngfx_need_main_thread(const char *what);
/* The text of the last failure, for keeping across a close(). */
const char *ngfx_error_text(void);
/* `s` as a NUL-terminated string in `buf`, cut to fit. */
const char *ngfx_cstr(ngfx_bytes s, char *buf, size_t cap);

/* --- the GPU half (ngfx_device.cpp) ----------------------------------------- */

/* The device, drawing to `layer` (a CAMetalLayer on Apple, an HWND on
   Windows, on Linux a Wayland surface, or an X11 window for x11, on `display`)
   or headless for NULL, with a screen of w x h pixels. */
bool ngfx_gpu_open(void *layer, void *display, bool x11, int w, int h, bool vsync);
/* Waits for the GPU and releases everything; safe after a failed open. */
void ngfx_gpu_close(void);
/* Ends the frame being recorded: submits it, presenting the window's image
   if the frame drew into it, and starts the next one. Whether it presented
   one (a flush() after drawing into it presents too). */
bool ngfx_gpu_next_frame(void);
/* Replaces the screen's textures with ones of w x h pixels, keeping their
   handles. */
bool ngfx_gpu_resize(int w, int h);
/* Inside a render pass. */
bool ngfx_gpu_in_pass(void);
/* Submits what has been recorded and waits for the GPU to finish it. */
void ngfx_gpu_finish(void);
/* "metal" or "vulkan". */
const char *ngfx_gpu_driver(void);
void ngfx_gpu_screen_size(int *w, int *h);
/* Whether this is the thread that started the program. */
bool ngfx_gpu_on_main_thread(void);

/* The time the ngfx::slang compiles have taken so far, and how many there
   were (ngfx_slang.cpp), for GOOSE_NGFX_BENCH. */
void ngfx_slang_time(double *seconds, int *modules);

/* For load_texture and save_png (ngfx_core.c, with stb_image). */
bool ngfx_png_load(const char *path, uint8_t **rgba, int *w, int *h);
bool ngfx_png_save(const char *path, const uint8_t *rgba, int w, int h, bool bgra);
void ngfx_png_free(uint8_t *rgba);

#ifdef __cplusplus
}
#endif

#endif
