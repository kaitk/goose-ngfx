# Goose findings

What Goose lacks for a library like this one, as of the pin. Each entry has a minimal
case, the Goose commit it was found on, the workaround used here, and whether it has
been reported upstream. None of the open ones blocks this repository. Every entry was
checked again at the pin, `v2026.4` (`6c1fbc7`), on 2026-11-11.

The entries come in two parts: [bugs](#bugs), where Goose does something wrong or other
than its spec says, then [feature requests](#feature-requests), for what it lacks. What
the spec or Goose's package design defines on purpose is neither, and isn't listed. Each
part runs from the least work a fix is expected to take to the most, so the cheap fixes
come first. The order is an estimate from reading the compiler. Place a new entry where
its expected work puts it, and delete an entry once the pin has its fix or this
repository no longer needs it: git keeps it.

Format:

```markdown
### Short title

Found on `<goose commit>`. Status: open | reported

What happens and what was expected.

    minimal case

Workaround: ...
```

## Bugs

### A build folder named after Fedora's GCC breaks SDL's Wayland step

Found on `6c1fbc7`. Status: open

Goose names a package's build folder after the C compiler's version, which it takes
from `gcc --version`. Fedora's GCC prints `gcc (GCC) 15.3.1 20251201 (Red Hat 15.3.1-1)`,
so the folder is `gcc-15.3.1-1)-a920ca84`, with a stray parenthesis. The gfx package's
SDL, configured with the Wayland headers, runs `wayland-scanner` in that folder through
`/bin/sh`, which stops at the `)`: `/bin/sh: -c: line 1: cd ".../gcc-15.3.1-1)-a920ca84/
cmake/pkg/SDL" && /usr/bin/wayland-scanner client-header ...`, and every program
importing gfx fails to link. `goose toolchain` shows the same: `gcc 15.3.1-1)`. Expected:
the folder name keeps only the version's own characters.

    # Fedora 43, gcc 15.3.1, wayland-devel installed
    goose build samples/cube.goose

Workaround: `--cc clang` (`clang-21.1.8-d8e5c55a`), for `goose build` and
`scripts/run_tests.py`.

## Feature requests

### Shaders in an outside language compile at run time

Found on `bab8b6f`. Status: open; planned upstream as build steps, a tool a package runs
while the program compiles, not built on `v2026.4` ([Goose package design, §11](https://github.com/aardappel/goose/blob/v2026.4/docs/design/packages.md#11-deferred-and-open))

`embed_shader` compiles GLSL into the program while Goose compiles it, with Goose's
built-in SPIR-V compiler. Nothing lets a package do the same for another language.
Expected: a package can run its own shader compiler while the program compiles.

Workaround: `ngfx::slang(source)` and `ngfx::slang_file(path)` run slangc when the
program calls them, which costs:

- A Slang error aborts the program when it runs, at `<slang source>:line`, rather than
  failing the Goose compile at the line in the program.
- The machine running the program needs slangc, `spirv-val` if validation is wanted, and
  NoGraphicsAPI's shader headers ([toolchain setup](development.md#toolchain)).
- Each module takes about 0.2 s to compile on the Windows test machine, every run. A
  cache keyed on the source would remove that if it starts to matter.
