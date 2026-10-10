# goose-ngfx

Graphics for [Goose](https://github.com/aardappel/goose) programs on Sebastian Aaltonen's
[NoGraphicsAPI](https://github.com/sebbbi/NoGraphicsAPI): a small API over Metal 4 and
Vulkan 1.4 with no bindings, no resource states, and GPU pointers in place of
descriptors. Shaders are [Slang](https://github.com/shader-slang/slang).

`import ngfx;` keeps Goose gfx's window, input, time, screen, textures, and read-back,
and draws the way NoGraphicsAPI does: a draw takes the GPU address of a root struct the
program fills, and shaders fetch their own vertices through pointers. Four of Goose's
samples are ported to it: a spinning cube, a ui to-do list, Mini Minecraft, and Mini
Doom.

This repository is a library for Goose, not a change to Goose (Kait, 2026-10-10). It
started as `ngfx` in a Goose fork. It moved out because Goose keeps its toolchain
light: its graphics compile GLSL in-process, with no Vulkan SDK or external shader
compiler, and ngfx needs both. Gaps found in Goose go to
[docs/goose-findings.md](docs/goose-findings.md), not into a Goose patch.

## Status

Built and tested on Windows 11 with Vulkan (RTX 4090), where the API check, every test,
and every sample pass. The ngfx code was tested on macOS 26 with Metal 4 (M1 Pro) while
it lived in the fork; this repository's build has not run on a Mac yet. Linux isn't
supported: NoGraphicsAPI is headless-only there.

## Layout

```text
lib/           the Goose modules: ngfx.goose and ngfx_ui.goose
native/        the C and C++ layer the modules' extern fns call, and its own shaders
samples/       cube, ui_todo, mini_minecraft, mini_doom, with expected output
test/          one program per test, with expected output in test/expected/
scripts/       run_tests.py and api_check.py
docs/          the API, the design, development setup, and the Goose findings log
third_party/   goose and NoGraphicsAPI, as submodules
```

Goose programs that use ngfx are built through C: the Goose compiler writes C, and
CMake compiles it and links the layer. `goose file.goose`, which runs a program in
process with TinyCC, can't load an outside library
([findings](docs/goose-findings.md#the-jit-cant-call-an-outside-native-library)).

## Quick start

On Windows, with Visual Studio 2026 Build Tools, the Vulkan SDK, and slangc
([docs/development.md](docs/development.md) has versions and paths):

```powershell
git clone --recursive https://github.com/kaitk/goose-ngfx.git
cd goose-ngfx
cmake -S . -B build -G "Visual Studio 18 2026"
cmake --build build --config Release
python scripts/run_tests.py
cd samples; ..\build\bin\mini_minecraft
```

## Docs

- [docs/api.md](docs/api.md): what `ngfx` and `ngfx_ui` offer, and how they differ from
  Goose's gfx. The header of `lib/ngfx.goose` is the reference.
- [docs/design.md](docs/design.md): why the module is shaped as it is.
- [docs/development.md](docs/development.md): toolchain, build, tests, and moving the
  Goose pin.
- [docs/goose-findings.md](docs/goose-findings.md): what Goose lacks for a library like
  this one.

## Pins

| What | Pin | Why |
|---|---|---|
| Goose | `aardappel/goose` `bab8b6f` (`master`, 2026-10-10) | The language, the stdlib, and the runtime ABI change often |
| NoGraphicsAPI | `sebbbi/NoGraphicsAPI` `0400414` | Its API is young and changes without notice |

Move a pin in its own commit, with the test results that still hold
([docs/development.md](docs/development.md#move-the-goose-pin)).

## License

Apache 2.0, as Goose, from which the platform half of the layer and the samples come.
NoGraphicsAPI is MIT.
