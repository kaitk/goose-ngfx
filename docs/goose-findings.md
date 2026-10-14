# Goose findings

What Goose lacks for a library like this one, found while moving `ngfx` out of the Goose
fork and making it a Goose package. Each entry has a minimal case, the Goose commit it
was found on, the workaround used here, and whether it has been reported upstream.
None of the open ones blocks this repository.

The entries come in two parts: [bugs](#bugs), where Goose does something wrong or other
than its spec says, then [feature requests](#feature-requests), for what it lacks. Each
part runs from the least work a fix is expected to take to the most, so the cheap fixes
come first. The order is an estimate from reading the compiler. Place a new entry where
its expected work puts it, and delete an entry once the pin has its fix: git keeps it.

Format:

```markdown
### Short title

Found on `<goose commit>`. Status: open | reported

What happens and what was expected.

    minimal case

Workaround: ...
```

## Bugs

None open.

## Feature requests

### Shaders in an outside language compile at run time

Found on `bab8b6f`. Status: open, by design upstream; unchanged on `46356c2`. Goose's
package design plans build steps, a tool a package runs while the program compiles, but
hasn't built them (`docs/design/packages.md` §11).

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
- Each module takes about 0.2 s to compile on the Windows test machine, every run. A
  cache keyed on the source would remove that if it starts to matter.

### Two packages can't share a C library

Found on `2de6d1d`. Status: open, by design upstream; unchanged on `46356c2`

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
