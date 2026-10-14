# Agent rules

## Project context

- What this is and its pins: `README.md`
- The API: `docs/api.md`, and the header of `ngfx.goose`
- Design decisions: `docs/design.md`
- Toolchain, build, and tests: `docs/development.md`
- Goose gaps found here: `docs/goose-findings.md`
- Task tracking: `tasks/` (see `tasks/README.md`)
- Substantial doc drafts and requested prose reviews:
  `.claude/skills/google-style/SKILL.md`; other writing follows "Writing" below
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

## Writing

- Lead with the decision, behavior, or action, then explain why. Name the responsible
  component and use concrete facts. Cut filler and repeated summaries.
- Preserve technical meaning when editing: actors, negations, conditions, numbers,
  versions, commands, paths, and identifiers. Keep decided/proposed/open,
  implemented/planned, and must/should/can distinct. Flag contradictions instead of
  silently resolving them while copyediting.
- Record a decision with its reason and the trade-off that matters. Keep each fact in
  one place and link to it elsewhere. Use absolute dates for dated events.
- Match the document's format. Tasks follow `tasks/README.md`, with concrete acceptance
  criteria. Use sentence-case headings, backticks for code identifiers and commands,
  and descriptive links. Wrap prose at about 90 characters.
- Use prose for connected ideas, lists for steps or separate items, and tables for
  comparisons. Keep structure proportional to the content.

## A library for Goose, not a change to Goose

- Goose changes daily. Fetch it at the start of a session and move the pin when it lags
  (`docs/development.md`, "Move the pins"). SDL moves only with `goose_gfx`'s.
- Don't edit Goose. When Goose rejects something it should accept,
  miscompiles, or lacks a hook this library needs, reduce it to a minimal case, record
  it in `docs/goose-findings.md`, and work around it here. Tell the maintainer about
  blockers.
- Every finding names the Goose commit it was found on, the pin at the time. When one
  lacks it, recover it from this repository's history: the pin in the commit that added
  the entry.
- `docs/goose-findings.md` lists bugs first and feature requests after, each part from
  the least work a fix is expected to take to the most. Place a new entry by that
  order, and delete an entry once the pin has its fix, or once this repository no
  longer needs what it asks for (2026-10-14).
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
