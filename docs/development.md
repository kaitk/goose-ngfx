# Development

Windows with Vulkan is where this repository is built and tested. macOS with Metal 4
should build the same way, with Xcode in place of Visual Studio and the Vulkan SDK, but
hasn't been tried since the code left the Goose fork.

## Toolchain

| Tool | Where on Kait's machine | Version used (2026-10-10) |
|---|---|---|
| Visual Studio Build Tools | `C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools` | 2026 (18), MSVC 19.51 |
| CMake | the Build Tools' `Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe`, not on `PATH` | 4.3.1 |
| Vulkan SDK | `C:\VulkanSDK\1.4.363.0`, which also has `spirv-val` | 1.4.363 (1.4.357 or later) |
| slangc | `..\slang\bin\slangc.exe`, beside this repository | 2026.18.2 or later |
| Python | `PATH` | 3.14.6, for the scripts |
| GPU | | RTX 4090, driver 617.42 |

CMake looks for slangc on `PATH` and in `../slang/bin`, and for `spirv-val` in
`$VULKAN_SDK/Bin`. A shell started before the Vulkan SDK was installed lacks
`VULKAN_SDK`; set it, or CMake doesn't find Vulkan.

On macOS: macOS 26, Xcode 26 with its Metal toolchain (`xcodebuild -downloadComponent
MetalToolchain`), and slangc. NoGraphicsAPI's Metal backend needs no Vulkan SDK.

## Get the source

```sh
git clone --recursive https://github.com/kaitk/goose-ngfx.git
```

or, in an existing clone:

```sh
git submodule update --init
git -C third_party/goose submodule update --init third_party/SDL third_party/nuklear
```

Goose needs only its SDL and Nuklear submodules here. `--recursive` also fetches its
TinyCC and Box3D, which this build turns off.

## Build

```powershell
cmake -S . -B build -G "Visual Studio 18 2026"
cmake --build build --config Release
```

One build makes everything, in this order:

1. The Goose compiler and its gfx, audio, and ui layers, from `third_party/goose`, as a
   CMake subproject in `build/goose`. TinyCC and physics are off.
2. NoGraphicsAPI and its utility libraries, from `third_party/NoGraphicsAPI`.
3. The layer's own two shaders (`native/*.slang`), with slangc and `spirv-val`, into
   byte arrays in `build/shaders`.
4. The `ngfx` static library, from `native/`.
5. Every program in `samples/` and `test/`: the Goose compiler writes
   `build/programs/<name>.c` (`-O2 --standalone`, with `--stdlib lib`), and MSVC compiles
   it into `build/bin/<name>.exe`, linked with `ngfx` and Goose's gfx, audio, and ui
   layers. They share one SDL3.

The Goose compiler, built as a subproject, can't find its own standard library from
`build/goose/Release`, so the build passes `GOOSE_STDLIB=third_party/goose/stdlib`
([findings](goose-findings.md#a-compiler-built-as-a-cmake-subproject-cant-find-its-stdlib)).
`--stdlib lib` is searched first, so `import ngfx;` finds `lib/ngfx.goose`, and every
other import falls through to Goose's.

`NGFX_GOOSE_OPT` (default `-O2`) sets the Goose compiler's optimization level for the
programs.

## Test

```powershell
python scripts/run_tests.py            # everything
python scripts/run_tests.py ngfx_render cube   # only these
python scripts/api_check.py            # only the API check
```

`run_tests.py` doesn't build; run `cmake --build` first. It runs, all off screen
(`GOOSE_GFX_HEADLESS=1`):

- `api_check.py`, which checks that `lib/ngfx.goose` and `native/ngfx_api.h` declare the
  same functions, structs, and constants.
- Each test in `test/`, from `test/`, so the Slang files the tests name are found there.
  A test passes when it exits with 0 and prints `test/expected/<name>.out`. A test with
  `expected/<name>.aborts` must fail instead, and print each line of
  `expected/<name>.stderr`. Each passing test runs again under `GOOSE_NGFX_SYNC=full`,
  which must not change its output.
- Each sample, from `samples/`, with the arguments in `samples/data/<name>.args`. Its
  screenshot lands in `samples/` (ignored by Git).

A run that finds no GPU device counts as a skip. The whole suite takes about 15 s on the
RTX 4090; most of it is slangc.

## Run the samples

Run them from `samples/`, without `--frames`, to play them in a window:

```powershell
cd samples
..\build\bin\cube
..\build\bin\ui_todo
..\build\bin\mini_minecraft
..\build\bin\mini_doom --wad ..\third_party\goose\samples\data\freedoom1-e1m1.wad
```

Mini Doom's map and art are Goose's Freedoom WAD. The ui to-do list reads Goose's copy of
Nuklear's Roboto font. Both are found through `third_party/goose`.

## Environment variables

| Variable | Read by | Effect |
|---|---|---|
| `GOOSE_GFX_HEADLESS` | the layer | `ngfx::open` opens no window, as `open_headless` |
| `GOOSE_NGFX_SYNC=full` | the layer | A full barrier around every pass and dispatch, to expose a missing `ngfx::barrier` |
| `NGFX_SLANGC` | `ngfx::slang` | The slangc to run, in place of the one CMake found |
| `NGFX_SPIRV_VAL` | `ngfx::slang` | The `spirv-val` to run; empty skips validation |
| `NGFX_NOGRAPHICSAPI` | `ngfx::slang` | NoGraphicsAPI's source tree, for `<NoGraphicsAPI/shader.slang>` |

The defaults are the paths CMake found, built into the layer, so a program built here
runs only where those paths exist, unless these are set.

## Move the Goose pin

Goose changes daily. Fetch it at the start of a session, and move the pin in its own
commit with the test results that still hold:

```sh
git -C third_party/goose fetch
git -C third_party/goose log --oneline HEAD..origin/master
git -C third_party/goose checkout origin/master
git -C third_party/goose submodule update third_party/SDL third_party/nuklear
```

Then rebuild, run `python scripts/run_tests.py`, and update the pin in `README.md`.
Things that tend to break:

- The C that `extern fn` declarations cross as. `api_check.py` compares the two sides of
  ngfx's boundary, but not Goose's own layout rules; a change to those breaks a test.
- Goose's gfx or ui API, which `ngfx_platform.c` and `lib/ngfx_ui.goose` copy. Port the
  change if it's a fix.
- The samples, which are ports of Goose's. When Goose's originals change, bring the ports
  in line and check the screenshots still match.

## Traps

- The agent's Bash tool turns `\\` into `\` before the shell sees it, even inside a
  quoted heredoc, so `"\\n"` written through it reaches the file as a line break. Edit
  files with the file tools when the text has backslashes.
- Programs print CRLF on Windows. `run_tests.py` compares with line endings normalized.
