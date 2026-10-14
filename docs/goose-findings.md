# Goose findings

What Goose lacks for a library like this one, as of the pin. Each entry has a minimal
case, the Goose commit it was found on, the workaround used here, and whether it has
been reported upstream. None of the open ones blocks this repository.

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

None open.

## Feature requests

### Shaders in an outside language compile at run time

Found on `bab8b6f`. Status: open; planned upstream as build steps, a tool a package runs
while the program compiles, not built on `46356c2` ([Goose package design, §11](https://github.com/aardappel/goose/blob/46356c2/docs/design/packages.md#11-deferred-and-open))

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
