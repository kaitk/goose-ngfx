# Development

Windows with Vulkan is where this repository is built and tested. macOS with Metal 4
should build the same way, with Xcode in place of Visual Studio and the Vulkan SDK, but
hasn't been tried since the code left the Goose fork.

## Toolchain

| Tool | Where on Kait's machine | Version used (2026-10-11) |
|---|---|---|
| Goose compiler | built from `aardappel/goose` at the pin in `README.md`; `GOOSE` or `PATH` | `2de6d1d` |
| Visual Studio Build Tools | `C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools` | 2026 (18): clang-cl 22.1.3, MSVC 19.51 |
| CMake, Ninja | the Build Tools' own, which Goose finds by itself | CMake 4.3.1 |
| Vulkan SDK | `C:\VulkanSDK\1.4.363.0`, which also has `spirv-val` | 1.4.363 (1.4.357 or later) |
| slangc | `..\slang\bin\slangc.exe`, beside this repository | 2026.18.2 or later |
| Python | `PATH` | 3.14.6, for the scripts |
| GPU | | RTX 4090, driver 617.42 |

`goose toolchain` says which C compiler, CMake, and git the Goose compiler uses. On this
machine it picks clang-cl from the Build Tools; `--cc msvc` picks cl.

The package's CMake looks for slangc in `NGFX_SLANGC`, in `../slang/bin` beside the
package, then on `PATH`, and for `spirv-val` in `$VULKAN_SDK/Bin`. The Vulkan SDK puts
an older slangc on `PATH`, so a fetched copy of the package, which has no `../slang`
beside it, needs `NGFX_SLANGC`. A shell started before the Vulkan SDK was installed
lacks `VULKAN_SDK`; set it, or CMake doesn't find Vulkan.

On macOS: macOS 26, Xcode 26 with its Metal toolchain (`xcodebuild -downloadComponent
MetalToolchain`), and slangc. NoGraphicsAPI's Metal backend needs no Vulkan SDK.

## Get the source

```sh
git clone --recursive https://github.com/kaitk/goose-ngfx.git
```

or `git submodule update --init` in an existing clone. The submodules are NoGraphicsAPI
and SDL; Goose fetches them too when it fetches the package from git.

The Goose compiler isn't a submodule: a package fetched with its submodules would carry a
copy. Build it from a clone of `aardappel/goose` at the pin, as its README says, and
point `GOOSE` at it:

```powershell
cmake -S ..\goose -B ..\goose\build -G "Visual Studio 18 2026"
cmake --build ..\goose\build --config Release
$env:GOOSE = "..\goose\build\Release\goose.exe"
```

## How a program is built

ngfx is a Goose package: `ngfx.goose` and `ngfx_ui.goose` at the root, and `ngfx.build`,
which names the CMake target `ngfx` as its native part. A program declares it in its
root file, from a directory or from git, and imports the modules:

```goose
import ngfx from "../";                            // the samples and tests
import ngfx from "github.com/kaitk/goose-ngfx@v0.1.0";
import ngfx.ngfx_ui;                               // the ui bridge, if wanted
```

The first `goose run` or `goose build` of such a program configures `CMakeLists.txt`
through a wrapper project of the compiler's, with Ninja, and builds, under
`~/.goose/build/pkg/`:

1. SDL3, from `third_party/SDL`, static, configured as Goose's gfx package configures
   its own.
2. NoGraphicsAPI and its utility libraries, from `third_party/NoGraphicsAPI`.
3. The layer's own two shaders (`native/*.slang`), with slangc and `spirv-val`, into
   byte arrays.
4. The `ngfx` static library, from `native/`, and, for `goose run`, a DLL of it the JIT
   loads.

The first build takes a few minutes. After that, a package from a directory is handed to
CMake on every run, whose build is incremental; one fetched from git is never rebuilt.
A program that imports `ui` or `audio` also gets Goose's gfx package, fetched from
`aardappel/goose_gfx` into `~/.goose/pkg/` and built the same way, unless the compiler
has it built in.

`goose run` compiles the program with TinyCC in the compiler's process, at `-O1`.
`goose build` writes C, compiles it at `-O2`, and links it with each package's native
part into an executable beside the source, or at `-o`. Neither needs a CMake build of
this repository; `cmake -S . -B build` builds only the native part, to work on it.

## Test

```powershell
python scripts/run_tests.py                     # everything
python scripts/run_tests.py ngfx_render cube    # only these
python scripts/run_tests.py --aot               # build the tests rather than run them
python scripts/run_tests.py --cc msvc           # another C compiler
python scripts/api_check.py                     # only the API check
```

`run_tests.py` uses `GOOSE`, or `goose` on `PATH`. It runs, all off screen
(`GOOSE_GFX_HEADLESS=1`):

- `api_check.py`, which checks that `ngfx.goose` and `native/ngfx_api.h` declare the
  same functions, structs, and constants.
- Each test in `test/`, with `goose run`, from `test/`, so the Slang files the tests name
  are found there. A test passes when it exits with 0 and prints
  `test/expected/<name>.out`. A test with `expected/<name>.aborts` must fail instead, at
  compile time or when it runs, and print each line of `expected/<name>.stderr`. Each
  passing test runs again under `GOOSE_NGFX_SYNC=full`, which must not change its
  output.
- Each sample, built with `goose build` into `build/bin/`, run from `samples/` with the
  arguments in `samples/data/<name>.args`. Its screenshot lands in `samples/` (ignored by
  Git).

A run that finds no GPU device counts as a skip. Once the native part is built, the whole
suite takes about a minute on the RTX 4090; most of it is building the samples and
slangc.

## Run the samples

Run them from `samples/`, without `--frames`, to play them in a window:

```powershell
cd samples
& $env:GOOSE cube.goose
& $env:GOOSE ui_todo.goose
& $env:GOOSE mini_minecraft.goose
& $env:GOOSE mini_doom.goose
& $env:GOOSE build mini_doom.goose; .\mini_doom --wad data\freedoom1-e1m1.wad
```

Mini Doom plays Goose's Freedoom WAD, copied to `samples/data/` with the to-do list's
Roboto font, which the program embeds with `embed_file`. Mini Doom looks for the WAD
under `resource_dir()`, which is the source's directory in `goose run` and the
executable's once built.

## Environment variables

| Variable | Read by | Effect |
|---|---|---|
| `GOOSE` | `run_tests.py` | The Goose compiler |
| `GOOSE_GFX_HEADLESS` | the layer | `ngfx::open` opens no window, as `open_headless` |
| `GOOSE_NGFX_SYNC=full` | the layer | A full barrier around every pass and dispatch, to expose a missing `ngfx::barrier` |
| `NGFX_SLANGC` | the package's CMake, `ngfx::slang` | The slangc to build with and to run, in place of the one CMake found |
| `NGFX_SPIRV_VAL` | `ngfx::slang` | The `spirv-val` to run; empty skips validation |
| `NGFX_NOGRAPHICSAPI` | `ngfx::slang` | NoGraphicsAPI's source tree, for `<NoGraphicsAPI/shader.slang>` |

The defaults are the paths CMake found, built into the layer, so a program built here
runs only where those paths exist, unless these are set.

## Move the pins

Goose changes daily. Fetch it at the start of a session, and move the pin in its own
commit with the test results that still hold:

```sh
git -C ../goose fetch
git -C ../goose log --oneline <pin>..origin/master
```

Then rebuild the compiler, run `python scripts/run_tests.py`, and update the pin in
`README.md`. Things that tend to break:

- The package system: the sidecar's keys, the wrapper project, the import forms
  ([goose-findings.md](goose-findings.md)).
- The C that `extern fn` declarations cross as. `api_check.py` compares the two sides of
  ngfx's boundary, but not Goose's own layout rules; a change to those breaks a test.
- Goose's gfx or ui API, which `ngfx_platform.c` and `ngfx_ui.goose` copy. They live in
  `aardappel/goose_gfx` now, at the ref in Goose's `src/blessed.txt`. Port the change if
  it's a fix.
- The samples, which are ports of Goose's. When Goose's originals change, bring the ports
  in line and check the screenshots still match.

SDL moves with `goose_gfx`, never alone: `third_party/SDL` must be the commit
`goose_gfx` pins at the ref Goose blesses, and `CMakeLists.txt` must set the same SDL
options as its `CMakeLists.txt`
([findings](goose-findings.md#two-packages-cant-share-a-c-library)). When the blessed
ref moves, compare both and move SDL in the same commit.

## Traps

- The agent's Bash tool turns `\\` into `\` before the shell sees it, even inside a
  quoted heredoc, so `"\\n"` written through it reaches the file as a line break. Edit
  files with the file tools when the text has backslashes.
- Programs print CRLF on Windows. `run_tests.py` compares with line endings normalized.
- `goose run` prints its compile summary on stderr; a test's stdout is the program's
  alone.
- A path source must start with `./` or `../`: `".."` is taken for a git source.
- A first build that fails at configure, as it does without a new enough slangc, stays
  failed: delete the package's directory under `~/.goose/build/pkg/` (`goose-ngfx-*`
  for a git source, `local/*` for a directory), then run again
  ([findings](goose-findings.md#a-package-whose-configure-fails-is-never-configured-again)).
- A fetched copy of the package bakes the slangc and NoGraphicsAPI paths of the machine
  that built it into the layer, as a local build does.
