# goose-ngfx

Graphics for [Goose](https://github.com/aardappel/goose) programs on Sebastian Aaltonen's
[NoGraphicsAPI](https://github.com/sebbbi/NoGraphicsAPI): a small API over Metal 4 and
Vulkan 1.4 with no bindings, no resource states, and GPU pointers in place of
descriptors. Shaders are [Slang](https://github.com/shader-slang/slang).

ngfx is a Goose package. It keeps Goose gfx's window, input, time, screen, textures, and
read-back, and draws the way NoGraphicsAPI does: a draw takes the GPU address of a root
struct the program fills, and shaders fetch their own vertices through pointers. Four of
Goose's samples are ported to it: a spinning cube, a ui to-do list, Mini Minecraft, and
Mini Doom.

This repository is a library for Goose, not a change to Goose (Kait, 2026-10-10). It
started as `ngfx` in a Goose fork. It moved out because Goose keeps its toolchain
light: its graphics compile GLSL in-process, with no Vulkan SDK or external shader
compiler, and ngfx needs both. Gaps found in Goose go to
[docs/goose-findings.md](docs/goose-findings.md), not into a Goose patch.

## Use it

Declare the package in your program's root file, and import it:

```goose
import vec;
import ngfx from "github.com/kaitk/goose-ngfx@v0.1.0";

fn main() {
    guard ngfx::open("Hello, ngfx", 640, 480) else { abort(ngfx::error()); }
    while ngfx::frame() {
        ngfx::begin_screen(float4 { 0.1, 0.2, 0.3, 1.0 });
        ngfx::end_pass();
    }
}
```

`goose hello.goose` runs it in the compiler's process; `goose build hello.goose` makes an
executable. The first time, the compiler fetches the package with its submodules into
`~/.goose` and builds its native part with CMake, which takes a few minutes. The machine
needs what that build needs: on Windows, Visual Studio 2026 Build Tools, the Vulkan SDK,
and slangc 2026.18.2 or later, named by `NGFX_SLANGC` unless it's first on `PATH`
([docs/development.md](docs/development.md)). `import ngfx.ngfx_ui;` draws Goose's
`ui` through ngfx ([docs/api.md](docs/api.md#ngfx_ui)).

## Status

Version 0.1.0: the API may still change. Built and tested on Windows 11 with Vulkan (RTX
4090), where the API check, every test, and every sample pass, run in the compiler and
built, with clang-cl and with MSVC. The ngfx code was tested on macOS
26 with Metal 4 (M1 Pro) while it lived in the fork; this repository has not run on a Mac
yet. Linux isn't supported: NoGraphicsAPI is headless-only there.

## Layout

```text
ngfx.goose      the package's entry, namespace ngfx
ngfx_ui.goose   import ngfx.ngfx_ui: Goose's ui drawn through ngfx
ngfx.build      the sidecar: the CMake target ngfx is the native part
CMakeLists.txt  the native part: SDL, NoGraphicsAPI, the layer, and its shaders
native/         the C and C++ layer the modules' extern fns call, and its own shaders
samples/        cube, ui_todo, mini_minecraft, mini_doom, with expected output
test/           one program per test, with expected output in test/expected/
scripts/        run_tests.py and api_check.py
docs/           the API, the design, development setup, and the Goose findings log
third_party/    NoGraphicsAPI and SDL, as submodules
```

The samples and tests declare the package from this checkout, `import ngfx from "../";`,
so they run against the working tree.

## Quick start

With a Goose compiler built at the pin below, in `GOOSE`
([docs/development.md](docs/development.md#get-the-source)):

```powershell
git clone --recursive https://github.com/kaitk/goose-ngfx.git
cd goose-ngfx
python scripts/run_tests.py
cd samples; & $env:GOOSE mini_minecraft.goose
```

## Docs

- [docs/api.md](docs/api.md): what `ngfx` and `ngfx_ui` offer, and how they differ from
  Goose's gfx. The header of `ngfx.goose` is the reference.
- [docs/design.md](docs/design.md): why the package is shaped as it is.
- [docs/development.md](docs/development.md): toolchain, how a program is built, tests,
  and moving the pins.
- [docs/goose-findings.md](docs/goose-findings.md): what Goose lacks for a library like
  this one.

## Pins

| What | Pin | Why |
|---|---|---|
| Goose | `aardappel/goose` `2de6d1d` (`master`, 2026-10-11): the compiler tested with | The language, the package system, and the runtime ABI change often |
| NoGraphicsAPI | `sebbbi/NoGraphicsAPI` `0400414` | Its API is young and changes without notice |
| SDL | `libsdl-org/SDL` `fa2c02b`, the commit `aardappel/goose_gfx` `v1` pins | A program that also imports `audio` or `ui` links both packages' SDL ([findings](docs/goose-findings.md#two-packages-cant-share-a-c-library)) |

Move a pin in its own commit, with the test results that still hold
([docs/development.md](docs/development.md#move-the-pins)).

## License

Apache 2.0, as Goose, from which the platform half of the layer and the samples come.
NoGraphicsAPI is MIT. `samples/data/` holds Goose's copies of the Freedoom E1M1 WAD
(BSD) and Roboto (Apache 2.0).
