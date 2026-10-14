# Development

This repository is built and tested on macOS with Metal 4 and on Windows with Vulkan,
and built headless on Linux. The build and the tests are the same everywhere; the
toolchains differ.

## Toolchain

Everywhere, the Goose compiler is built from `aardappel/goose` at the pin in `README.md`,
and named by `GOOSE` or found on `PATH`. Python runs the scripts.

macOS, tested on an M1 Pro (2026-10-11):

| Tool | Where | Version |
|---|---|---|
| macOS | | 26.3.1 |
| Xcode, with its Metal toolchain | `xcodebuild -downloadComponent MetalToolchain` adds the toolchain | 26.4: Apple clang 21, `metal` 32023.883 |
| CMake | Homebrew | 4.4.4 |
| slangc | `../slang/bin/slangc`, beside this repository, from Slang's `macos-aarch64` release | 2026.18.3 (2026.18.2 or later) |
| Python | `python3` | 3.14.8 |

The Mac needs no Vulkan SDK or `spirv-val`: NoGraphicsAPI's backend there is Metal, and
the layer compiles its shaders with Xcode's `metal` and `metallib`. Without Ninja, the
compiler builds packages with Unix Makefiles. Fetch Slang with `curl`, as the README's
quick start does. A browser's download carries macOS's quarantine attribute, which
`xattr -dr com.apple.quarantine slang` removes.

Windows 11, tested on an RTX 4090 (driver 617.42):

| Tool | Where | Version |
|---|---|---|
| Visual Studio Build Tools | `C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools` | 2026 (18): clang-cl 22.1.3, MSVC 19.51 |
| CMake, Ninja | the Build Tools' own, which Goose finds by itself | CMake 4.3.1 |
| Vulkan SDK | `C:\VulkanSDK\1.4.363.0`, which also has `spirv-val` | 1.4.363 (1.4.357 or later) |
| slangc | `..\slang\bin\slangc.exe`, beside this repository, from Slang's `windows-x86_64` release | 2026.18.3 (2026.18.2 or later) |
| Python | `PATH` | 3.14.6 |

Linux, tested in WSL 2 on Ubuntu 26.04 (2026-10-11), headless only:

| Tool | Where | Version |
|---|---|---|
| gcc, CMake, Ninja, git | the distribution's | gcc 15.2, CMake 4.2.3 |
| Vulkan SDK | LunarG's Linux tarball, `source <sdk>/setup-env.sh`, which also has `spirv-val` | 1.4.363 (1.4.357 or later) |
| slangc | Slang's `linux-x86_64` release | 2026.18.3 (2026.18.2 or later) |
| X11 headers, for `ui` and `audio` | `libx11-dev libxext-dev libxrandr-dev libxcursor-dev libxfixes-dev libxi-dev libxss-dev libxtst-dev libxkbcommon-dev` | |
| Python | `python3` | 3.14 |

The distribution's Vulkan headers may be older than 1.4.357 (Ubuntu 26.04's are
1.4.341), hence the SDK. ngfx's own SDL needs no X11: it never opens a window on Linux.
Goose's gfx package, which `ui` and `audio` come from, builds nothing without X11 or
Wayland headers, and SDL then wants all of the X11 ones above, not only the two gfx's
message names. Without them, a program importing `ui` or `audio` fails to link
(`cannot find -lgoose_gfx_package`). On an immutable distribution such as Bazzite,
build inside a toolbox or distrobox container (untried).

`goose toolchain` says which C compiler, CMake, and git the Goose compiler uses. On the
Mac it picks `/usr/bin/cc`, Apple clang; on Linux `cc`. On Windows it picks clang-cl
from the Build Tools; `--cc msvc` picks cl.

The package's CMake looks for slangc in `NGFX_SLANGC`, in `../slang/bin` beside the
package, then on `PATH`, and for `spirv-val` in `$VULKAN_SDK/Bin`. A fetched copy of the
package has no `../slang` beside it, so it needs `NGFX_SLANGC` unless slangc 2026.18.2
or later is first on `PATH`. On Windows, the Vulkan SDK puts an older slangc on `PATH`,
and a shell started before the SDK was installed lacks `VULKAN_SDK`; set it, or CMake
doesn't find Vulkan.

## Get the source

```sh
git clone --recursive https://github.com/kaitk/goose-ngfx.git
```

or `git submodule update --init` in an existing clone. The submodules are NoGraphicsAPI
and SDL; Goose fetches them too when it fetches the package from git.

The Goose compiler isn't a submodule: a package fetched with its submodules would carry a
copy. Build it from a clone of `aardappel/goose` at the pin, as its README says, and
point `GOOSE` at it. On macOS and Linux:

```sh
cmake -S ../goose -B ../goose/build -DCMAKE_BUILD_TYPE=Release
cmake --build ../goose/build -j
export GOOSE=$PWD/../goose/build/goose
```

On Windows:

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
import ngfx from "github.com/kaitk/goose-ngfx@v0.1.2";
import ngfx.ngfx_ui;                               // the ui bridge, if wanted
```

The first `goose run` or `goose build` of such a program configures `CMakeLists.txt`
through a wrapper project of the compiler's, with Ninja where the compiler finds it and
the platform's generator otherwise (Unix Makefiles on a Mac without Ninja), and builds,
under `~/.goose/build/pkg/`:

1. SDL3, from `third_party/SDL`, static, configured as Goose's gfx package configures
   its own.
2. NoGraphicsAPI and its utility libraries, from `third_party/NoGraphicsAPI`.
3. The layer's own two shaders (`native/*.slang`), into byte arrays: SPIR-V, with
   slangc and `spirv-val`, or on macOS a metallib, with slangc and Xcode's `metal` and
   `metallib`.
4. The `ngfx` static library, from `native/`, and, for `goose run`, a shared library of
   it the JIT loads.

The first build takes a few minutes; fetching and building it from git took 85 s on
the M1 Pro. After that, a package from a directory is handed to
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
slangc. On the M1 Pro it took 3.5 minutes, the first build of the native part included.

On Vulkan, the Khronos validation layer checks the suite, synchronization included. The
layer prints what it finds on stdout, so any message fails the test or sample it comes
from:

```powershell
$env:VK_INSTANCE_LAYERS = "VK_LAYER_KHRONOS_validation"
$env:VK_KHRONOS_VALIDATION_REPORT_FLAGS = "error,warn"
$env:VK_KHRONOS_VALIDATION_VALIDATE_SYNC = "true"
python scripts/run_tests.py
```

## Linux, headless

NoGraphicsAPI can't present on Linux, so `ngfx::open` fails there with "NoGraphicsAPI
cannot present on this platform; use ngfx::open_headless", unless `GOOSE_GFX_HEADLESS=1`
makes it open headless, as `run_tests.py` does. A machine without a qualifying Vulkan
driver gets "no NoGraphicsAPI device ... No compatible GPU found", which names the
extensions, and the runner counts it as a skip. In WSL, then, `run_tests.py` passes the
API check, the Slang error tests, the thread test, and `ngfx_slang_sources`, which need
no device, and builds every sample.

```sh
source ~/vulkansdk/1.4.363.0/setup-env.sh
export NGFX_SLANGC=~/slang/bin/slangc GOOSE=~/goose/build/goose
python3 scripts/run_tests.py
```

## Run the samples

Run them from `samples/`, without `--frames`, to play them in a window:

```sh
cd samples
$GOOSE cube.goose
$GOOSE ui_todo.goose
$GOOSE mini_minecraft.goose
$GOOSE mini_doom.goose
$GOOSE build mini_doom.goose && ./mini_doom --wad data/freedoom1-e1m1.wad
```

or in PowerShell:

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

On the Mac the clone is `../goose-upstream`, and its remote is named `upstream`, so
the range there is `<pin>..upstream/master`.

Then rebuild the compiler, run `python scripts/run_tests.py`, and update the pin in
`README.md`, in the table and in both quick starts. Things that tend to break:

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
- On Windows, keep `GOOSE_HOME` short. Goose's cache adds about 110 characters below it
  (`build\pkg\local\<hash>\<toolchain>\cmake`), and CMake's compiler check about 120
  more, so a `GOOSE_HOME` much longer than `C:\Users\<name>\.goose` passes Windows'
  260-character path limit, and the first configure fails with `RC1109: error creating
  ...manifest.res` (clang-cl) or `C1041: cannot open program database` (MSVC).
- A fetched copy of the package bakes the slangc and NoGraphicsAPI paths of the machine
  that built it into the layer, as a local build does.
- A `git worktree` of this repository starts without its submodules: run
  `git submodule update --init` in it. Git then refuses to remove it ("working trees
  containing submodules cannot be moved or removed"), and `git submodule deinit --all -f`
  in the worktree, which lets `git worktree remove --force` remove it, also unregisters
  the submodules of the main checkout, which share its config. Run
  `git submodule update --init` there afterwards; the checked-out files stay.
- To try the package as users get it before pushing, commit, and import it from the
  local clone by its full commit hash:
  `import ngfx from "file:///path/to/goose-ngfx@<40-hex hash>";`. Git can't fetch an
  abbreviated hash.
- The package's native part rebuilds by file time. A source restored with its old time
  (`cp -p` from a backup) keeps the object built from the edit, and every program built
  afterwards links it. `touch` the file.
- On the Mac, a GPU restart leaves `gpuEvent-*.ips` in `/Library/Logs/DiagnosticReports/`
  (later moved to `Retired/`), with the restart reason and which GPU slots were busy. In
  zsh, `log` is a builtin: read the system log with `/usr/bin/log show`.
- A program that opens ngfx holds macOS's `PreventUserIdleDisplaySleep`, even headless,
  because SDL disables the screen saver. A loop of runs keeps the display awake;
  `pmset displaysleepnow` turns it off.
