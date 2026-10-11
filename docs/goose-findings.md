# Goose findings

What Goose lacks for a library like this one, found while moving `ngfx` out of the Goose
fork and making it a Goose package. Each entry has a minimal case, the Goose commit it
was found on, the workaround used here, and whether it has been reported upstream.

None of the open ones blocks this repository.

Format:

```markdown
## Short title

Found on `<goose commit>`. Status: open | reported | fixed in `<commit>`

What happens and what was expected.

    minimal case

Workaround: ...
```

## The JIT can't call an outside native library

Found on `bab8b6f`. Status: fixed in `b533b47`: a package's native part is built into a
shared library the JIT loads, and `goose run` runs every ngfx test.

`goose file.goose` compiles a program with TinyCC and runs it in process. TinyCC resolves
an `extern fn` only against the symbols of Goose's own layers, which `src/jit.h`
registers (`AddGfxSymbols` and the like), and against functions defined in an
`--include` header. A symbol from any other library is unresolved, and there is no
option to name a library or a DLL to load.

    // main.goose
    extern fn mylib_answer() -> i64;
    fn main() { print(mylib_answer()); }

    > goose main.goose
    libtcc: running the generated C failed
    tcc: error: unresolved reference to 'mylib_answer'

An `--include` header works for C that TinyCC can compile, which is how goose-http's
shim works. ngfx's layer is C++ over NoGraphicsAPI, so it can't go in a header.

Workaround: every program that uses ngfx is built through C (`goose -o`, then MSVC),
which CMake does for the samples and tests. There is no `goose file.goose` for them.

## A C library can't append to a Goose builder

Found on `bab8b6f`. Status: open; still so on `2de6d1d`

The spec (§7.10) lets an `extern fn` take a `u8[>..]&`, which C appends to with
`gs_bld_append(ref, p, n)`. That function is `static` in
`src/runtime/runtime_ext.h`, which only the program's own C includes. It writes
through `gs_rhdr` and `gs_stack`, which are the runtime's internals. A library compiled
on its own has no function to call and no stable layout to write through.

    // mylib.c, compiled separately and linked with the program
    uint8_t mylib_fill(gs_rref out);   /* no gs_rref, no gs_bld_append here */

Workaround: the call is split in two, as the layer's error text already was. One call
does the work and returns the result's size, and keeps the result. The Goose side
resizes an array to that size, and a second call copies the result in
(`ngfx_compile_slang`, then `ngfx_slang_result`).

## Shaders in an outside language compile at run time

Found on `bab8b6f`. Status: open, by design upstream. Goose's package design plans build
steps, a tool a package runs while the program compiles, but hasn't built them
(`docs/design/packages.md` §11).

`embed_shader` compiles GLSL into the program while Goose compiles it, with Goose's
built-in SPIR-V compiler. Nothing lets a library do the same for another language. In
the fork, `embed_slang` was a builtin that ran slangc while typechecking. That compiler
change is why ngfx left Goose: Goose keeps external shader compilers out of its build.

Workaround: `ngfx::slang(source)` and `ngfx::slang_file(path)` run slangc when the
program calls them, which costs:

- A Slang error aborts the program when it runs, at `<slang source>:line`, rather than
  failing the Goose compile at the line in the program.
- The machine running the program needs slangc, `spirv-val` if validation is wanted, and
  NoGraphicsAPI's shader headers (`docs/development.md`).
- Each module takes about 0.2 s to compile on Kait's machine, every run. A cache keyed
  on the source would remove that if it starts to matter.

## A main-thread-only layer can't say so to the compiler

Found on `bab8b6f`. Status: fixed in `9a3c810`: `main_thread_only = true;` in
`ngfx.build`, and `test/ngfx_err_thread.goose` now expects the compiler's error. The
layer's own check stays.

Goose rejects a call from a `thread_fn` into a main-thread-only layer at compile time.
It recognizes those layers by their C prefix (`gs_audio_`, `gs_gfx_`, `gs_phys_`,
`gs_ui_`, in `src/typecheck.h`), so an outside layer can't join the check, and `gs_` is
reserved for Goose.

    thread_fn render() { ngfx::frame(); }
    fn main() { thread_wait(thread_spawn(render)); }

Workaround: the layer checks the thread at run time, in every call that needs the
device and in `open`, and counts a call from another thread as a misuse, which aborts
the program at its next check (`test/ngfx_err_thread.goose`).

## A compiler built as a CMake subproject can't find its stdlib

Found on `bab8b6f`. Status: no longer met: this repository stopped building the compiler
when ngfx became a package.

The compiler looks for the stdlib in `--stdlib`, `GOOSE_STDLIB`, and up to three
directories above its own binary (`StdlibDirs` in `src/main.cpp`). Built with
`add_subdirectory(third_party/goose)`, the binary is in `build/goose/Release/`, and
none of those directories is `third_party/goose/stdlib`. The compiler then reports the
first import as a missing file next to the program.

Workaround: CMake runs the compiler with `GOOSE_STDLIB=third_party/goose/stdlib`, and
passes `--stdlib lib` for this repository's modules, which is searched first.

## A path source must start with `./` or `../`

Found on `2de6d1d`. Status: open

`import ngfx from "..";` in `samples/cube.goose` is read as a git source, so the error
asks for a ref. `".."` names a directory as clearly as `"../"`.

    import ngfx from "..";
    // cube.goose:21: error: the git source .. needs a ref: host/owner/repo@tag, @branch or @commit

Workaround: the samples and tests write `"../"`.

## A CMake package can't publish a C++ standard to the wrapper

Found on `2de6d1d`. Status: open

The compiler builds a CMake package through a wrapper project whose top level is
`project(goose_pkg_<name> C)`, and links the package's target into a JIT library and a
link probe declared there (`src/native.h`, `BuildCMakePart`). A target that publishes a
C++ compile feature, as NoGraphicsAPI's `target_compile_features(NoGraphicsAPI PUBLIC
cxx_std_20)` does, reaches those two targets, and CMake's generate step fails, since C++
isn't enabled at the top:

    CMake Error in CMakeLists.txt:
      No known features for CXX compiler

`docs/design/packages.md` §5.2 shows the wrapper as `project(... C CXX)`.

Workaround: `ngfx` links its dependencies `PRIVATE`, so only their link closure leaves
the package.

## Two packages can't share a C library

Found on `2de6d1d`. Status: open, by design upstream

A package's C is self-contained, and packages that must share C share a repository
(`docs/packages.md`, "The native part"). ngfx and Goose's gfx package both need SDL3:
ngfx for its window and input, gfx for its window, audio, and ui. They can't share a
repository, so each builds its own.

A program that imports `ngfx` and `audio` or `ui` then links two SDL archives. The
linker takes each object from the first archive that defines it, so this works only
while both are the same SDL, built the same way. In a `goose run`, each package's JIT
library holds a whole SDL, and the program has two SDL states: one with ngfx's window,
one with audio's device. Mini Doom (ngfx and `audio`) and the to-do list (ngfx and `ui`)
pass both ways.

Workaround: `third_party/SDL` is pinned to the commit `goose_gfx` pins, and
`CMakeLists.txt` configures it with the same options. Moving either pin means moving
both ([development.md](development.md#move-the-pins)).

## A package whose configure fails is never configured again

Found on `2de6d1d`. Status: open

The compiler configures a CMake package only when its build directory has no
`CMakeCache.txt` (`src/native.h`, `BuildCMakePart`). A configure that fails writes one
anyway, so every later run skips the configure and only builds, which fails for want of
the build files, even once what made the configure fail is fixed:

    No slangc 2026.18.2 or later (NGFX_SLANGC-NOTFOUND): set NGFX_SLANGC ...
    # set NGFX_SLANGC, run again:
    ninja: error: loading 'build.ninja': The system cannot find the file specified.

Workaround: delete the package's directory under `~/.goose/build/pkg/` and run again
([development.md](development.md#traps)).

## `goose build -o` doesn't make the output's directory

Found on `2de6d1d`. Status: open

`goose build -o build/bin/cube.exe cube.goose` with no `build/bin` fails at the link:

    LINK : fatal error LNK1104: cannot open file '...\build\bin\cube.exe'

The C and the objects go under `~/.goose`, which the compiler makes as it needs.

Workaround: `run_tests.py` makes `build/bin` first.
