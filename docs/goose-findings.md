# Goose findings

What Goose lacks for a library like this one, found while moving `ngfx` out of the Goose
fork. Each entry has a minimal case, the Goose commit it was found on, the workaround
used here, and whether it has been reported upstream.

None of them blocks this repository. Together they are what the fork's compiler changes
did, and what any outside Goose library with a native layer will meet.

Format:

```markdown
## Short title

Found on `<goose commit>`. Status: open | reported | fixed in `<commit>`

What happens and what was expected.

    minimal case

Workaround: ...
```

## The JIT can't call an outside native library

Found on `bab8b6f`. Status: open

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

Found on `bab8b6f`. Status: open

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

Found on `bab8b6f`. Status: open, by design upstream

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

Found on `bab8b6f`. Status: open

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

Found on `bab8b6f`. Status: open

The compiler looks for the stdlib in `--stdlib`, `GOOSE_STDLIB`, and up to three
directories above its own binary (`StdlibDirs` in `src/main.cpp`). Built with
`add_subdirectory(third_party/goose)`, the binary is in `build/goose/Release/`, and
none of those directories is `third_party/goose/stdlib`. The compiler then reports the
first import as a missing file next to the program.

Workaround: CMake runs the compiler with `GOOSE_STDLIB=third_party/goose/stdlib`, and
passes `--stdlib lib` for this repository's modules, which is searched first.
