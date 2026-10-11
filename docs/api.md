# The ngfx API

`ngfx` is graphics on [NoGraphicsAPI](https://github.com/sebbbi/NoGraphicsAPI), over
Metal 4 or Vulkan 1.4. It keeps Goose gfx's window, input, time, screen, textures,
samplers, read-back, and `screenshot` by name and behavior, and draws the way
NoGraphicsAPI does: no bindings, no vertex formats, and no resource states. Everything
is in namespace `ngfx`.

The header of `ngfx.goose` is the reference, `samples/cube.goose` a small complete
program, and [design.md](design.md) how it works and what it costs.

```goose
import ngfx from "github.com/kaitk/goose-ngfx@v0.1.0";

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
- **Clip space is y down**, depth 0 to 1, and matrices are row-major `float4x4`s.
  `perspective`, `ortho`, and `look_at` produce them.
- **The program states the barriers between its own passes and dispatches**, with
  `barrier(before, after)`. `GOOSE_NGFX_SYNC=full` adds a full barrier around each, to
  check for a missing one.
- **`generate_mips` is a compute pass** on 2D `SAMPLED | STORAGE` textures, not sRGB.
- **Main thread only**, as gfx. A call from a `thread_fn` aborts the program at its next
  check, where gfx's is a compile error.

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
`ngfx_ui::input(c)` after `ngfx::frame()`, and `ngfx_ui::render(c)` or
`ngfx_ui::render(c, target)`, as `ui`'s gfx functions do. `samples/ui_todo.goose` uses
it.
