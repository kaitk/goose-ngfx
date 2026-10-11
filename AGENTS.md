# Agent rules

## Project context

- What this is and its pins: `README.md`
- The API: `docs/api.md`, and the header of `ngfx.goose`
- Design decisions: `docs/design.md`
- Toolchain, build, and tests: `docs/development.md`
- Goose gaps found here: `docs/goose-findings.md`
- Task tracking: `tasks/` (see `tasks/README.md`)
- Writing docs: `.claude/skills/google-style/SKILL.md`
- The language: Goose's `docs/tutorial.md`, `goose_spec.md`, `stdlib.md`, and
  `packages.md`, in a clone of `aardappel/goose` at the pin (`../goose` on the
  maintainer's Windows machine; on the Mac, `../goose-upstream`, since `../goose` there
  is the old fork). Read the tutorial before writing Goose; check the spec before
  assuming a feature exists. gfx, audio, and ui are in `aardappel/goose_gfx`.

Follow the recorded decisions; if a change contradicts one, update the doc in the same
change or ask first. Record setup facts and environment traps you find in
`docs/development.md`, not in agent memory, so the next agent finds them.

Don't name this repository's maintainer in docs, Markdown, code, or comments; write
"the maintainer". The repository URL `github.com/kaitk/goose-ngfx` stays as it is.

## A library for Goose, not a change to Goose

- Goose changes daily. Fetch it at the start of a session and move the pin when it lags
  (`docs/development.md`, "Move the pins"). SDL moves only with `goose_gfx`'s.
- Don't edit Goose. When Goose rejects something it should accept,
  miscompiles, or lacks a hook this library needs, reduce it to a minimal case, record
  it in `docs/goose-findings.md`, and work around it here. Tell the maintainer about
  blockers.
- Write Goose the way Goose's own `samples/` and `stdlib/` do, and a package the way
  `goose_gfx` is one.
- `ngfx.goose` and `native/ngfx_api.h` describe one boundary. Change both together,
  and run `python scripts/api_check.py`.

## Tests

- `python scripts/run_tests.py`, with `GOOSE` set to a compiler at the pin. Every test
  must pass both plainly and under `GOOSE_NGFX_SYNC=full`.
- A sample's or test's expected output changes only with a reason in the commit.

## Code conventions

- Comment only where the code is hard to follow without it, and say only what a reader
  of that code needs: why, a constraint, or a contract the code can't show. Don't restate
  the next line, and don't describe earlier versions or the task that added the code;
  history belongs in git.
- An `extern fn` whose C side keeps or writes more than the spec's default (§7.10) says
  so in a comment.

## Commits

- One or two lean sentences, imperative mood.
- No body, no `Co-Authored-By` or any other trailers.
