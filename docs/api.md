# The ngfx API

`ngfx` is graphics on [NoGraphicsAPI](https://github.com/sebbbi/NoGraphicsAPI), over
Metal 4 or Vulkan 1.4, into a native window the program gives it. It keeps Goose gfx's
screen, textures, samplers, read-back, and `screenshot` by name and behavior, and draws
the way NoGraphicsAPI does: no bindings, no vertex formats, and no resource states.
Everything is in namespace `ngfx`. The window, input, events, and time are the
program's: Goose gfx's, opened `WINDOW_ONLY` ([The platform](#the-platform)).

The header of `ngfx.goose` is the reference, `samples/cube.goose` a small complete
program, and [design.md](design.md) how it works and what it costs.

```goose
import ngfx from "github.com/kaitk/goose-ngfx@v0.5.0";

struct Root { vertices: u64, transform: ngfx::float4x4 }

let shaders = ngfx::slang_file("cube.slang");      // every entry point of one Slang module
let pipeline = ngfx::pipeline(shaders);            // its vertex and fragment entry points
let vertices = ngfx::buffer(bytes_of(cube));       // plain GPU memory
let root = ngfx::root(Root { vertices: ngfx::address(vertices), transform: m });
ngfx::draw(root, 36);                              // the shader fetches its own vertices
```

A program declares the package in its root file, as above or from a directory, and runs
with `goose file.goose` or builds with `goose build file.goose`
([development.md](development.md#how-a-program-is-built)).

## How it differs from gfx

- **Shaders are Slang modules**, compiled while the program runs by `ngfx::slang(source)`
  or `ngfx::slang_file(path)`. Each runs slangc, and on macOS Xcode's Metal tools, and
  returns a blob with SPIR-V, a metallib on a Mac, and every entry point with its stage.
  A module that doesn't compile aborts the program with slangc's message. Compile each
  module once, before the frame loop: it takes a fraction of a second.
- **A draw or dispatch takes a root**: the GPU address of a struct the program fills,
  usually with `root(value)` or `frame_data(bytes)` in this frame's memory. The shader
  reads buffers through GPU addresses (`address(b)`), and textures and samplers through
  descriptor indices (`index(t)`, `storage_index(t, mip)`).
- **Pipelines are made for the formats of the passes they draw in**, at their first draw
  into each, or before it with `prepare(pipeline, pass)` or `prepare_screen(pipeline)`.
- **`draw_indexed` takes its indices as a `Range`**, an address and a size: a buffer's
  (`range(b)`, or the buffer itself) or this frame's memory (`frame_range(bytes)`).
- **Indirect draws and dispatches** (`draw_indirect`, `draw_indexed_indirect`,
  `dispatch_indirect`) read their arguments from a GPU address, so a compute pass can
  write them, behind `barrier(COMPUTE_WRITE, STAGE_INDIRECT | ACCESS_INDIRECT_READ)`.
- **Clip space is y down**, depth 0 to 1, and matrices are row-major `float4x4`s.
  `perspective`, `ortho`, and `look_at` produce them.
- **The program states the barriers between its own passes and dispatches**, with
  `barrier(before, after)`. `GOOSE_NGFX_SYNC=full` adds a full barrier around each, to
  check for a missing one.
- **`generate_mips` is a compute pass** on 2D `SAMPLED | STORAGE` textures, not sRGB.
- **Block-compressed textures**: `BC3`, `BC7`, `ASTC_4x4`, and `ASTC_6x6`, gfx's numbers
  for the formats NoGraphicsAPI has. They are `SAMPLED` only, uploaded in whole blocks (a
  region starts on a block; the mip's edge may cut its last ones), never read back, and
  have no generated mips. `format_supported(format, usage)` says whether the device takes
  one: ASTC on Apple silicon and phones, BC on desktop GPUs.
- **`present()` ends each frame**, at the bottom of the loop: it submits the frame and
  shows the screen if the frame drew into it, and says whether it showed one. Handed to
  gfx's `presented`, a frame that showed nothing makes the next `gfx::frame()` wait for
  an event, so an idle program uses no GPU and next to no CPU: drawing on demand is
  skipping the passes when nothing changed, and drawing when gfx's `needs_present()`
  says the window was exposed, shown, or resized.
- **In a window, the screen is the window's image** (BGRA8): a frame's first pass into
  it acquires the image and `present()` shows it. Only a pass can draw into it, and it
  holds nothing of the last frame, so that pass clears it. It can't be sampled, read
  back, updated, or saved; `screenshot` returns false there. A `flush()` after drawing
  into it presents it, and a later pass acquires the next. Headless, the screen is an
  RGBA8 texture that keeps what the last frame drew and can be read and saved.
- **Main thread only**, as gfx: a `thread_fn` that reaches ngfx is a compile error, from
  `main_thread_only` in `ngfx.build`.

## The platform

ngfx has none. `open(window, width, height, flags, display, kind)` takes a native
window's handle as a `u64`: a `CAMetalLayer` on Apple's systems, an `HWND` on Windows, or
0 for headless. On Linux a window is a Wayland surface or an X11 window on its display, so
`display` and `kind` (`NATIVE_WAYLAND` or `NATIVE_X11`) say which; gfx gives both
(`native_display()`, `native_kind()`), 0 elsewhere, where they can be left out.
Goose gfx opened with `WINDOW_ONLY` gives one (`native_window()`), and keeps its window,
keys, the mouse, events, typed text, the clipboard, fullscreen, pixel density and display
scale, cursors, gamepads, and time, under the names gfx programs know:

```goose
guard gfx::open("title", w, h, gfx::WINDOW_RESIZABLE | gfx::WINDOW_ONLY) else { ... }
let size = gfx::screen_size();
guard ngfx::open(gfx::native_window(), size.x, size.y, 0, gfx::native_display(), gfx::native_kind()) else { ... }
while gfx::frame() {                              // events; waits when idle
    ngfx::resize(gfx::screen_size());             // the screen follows the window
    if changed || gfx::needs_present() { ... }    // draw into screen()
    gfx::presented(ngfx::present());
}
ngfx::close();
gfx::close();
```

`WINDOW_ONLY` is in `kaitk/goose_gfx`'s `main`, proposed to Goose's gfx. Any other
source of a native window does as well. The flag `NO_VSYNC` presents without waiting
for the display, for benchmarks.

## Shaders

```goose
let shared = """
    #include <NoGraphicsAPI/shader.slang>
    float doubled(float x) { return x * 2.0; }
    """;

let a = ngfx::slang("""
    #include <NoGraphicsAPI/shader.slang>
    ...
    """);
let b = ngfx::slang(shared, """ ... """);       // parts, joined as lines
let c = ngfx::slang_file("shaders/world.slang");
```

- `slang(source)`, `slang(a, b)`, and `slang(a, b, c)` compile Slang source; parts are
  the module's lines in order, so a `let` global can hold code several modules share. An
  `#include` also looks in the working directory.
- `slang_file(path)` compiles a file, relative to the working directory; its `#include`
  also looks in the file's directory.
- Errors read `ngfx::slang: <slang source>:3: error: undefined identifier 'oops'.`, with
  the line in the joined source.
- `pipeline(blob)` takes the module's only vertex and fragment entry points, and
  `pipeline(blob, vertex, fragment, desc)` names them. `compute_pipeline(blob)` takes its
  only compute entry point, and `compute_pipeline(blob, entry)` names it.
- `NGFX_SLANGC`, `NGFX_SPIRV_VAL`, and `NGFX_NOGRAPHICSAPI` override the tool paths the
  build found ([development.md](development.md#environment-variables)).

## ngfx_ui

`import ngfx.ngfx_ui;` draws Goose's
[`ui`](https://github.com/aardappel/goose_gfx/blob/v1/docs/ui.md) through ngfx:
`ngfx_ui::input(c)` after `gfx::frame()` (gfx's events), and `ngfx_ui::render(c)` or
`ngfx_ui::render(c, target)`, as `ui`'s gfx functions do. `ngfx_ui::prepare()`, once
before the frame loop, makes its pipeline for the screen then rather than in the first
frame. `samples/ui_todo.goose` uses
it.
