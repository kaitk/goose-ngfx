# 001: Review the architecture

Status: todo

ngfx matches gfx on correctness (screenshots and tests), but it has no performance
numbers. Nobody has checked the policies ngfx's module owns against what NoGraphicsAPI is
meant to be. This task answers whether the architecture in
[docs/design.md](../../docs/design.md) holds up on two counts. First, it should use
NoGraphicsAPI the way Sebastian Aaltonen intends. Second, as a replacement for gfx, it
should cost no more CPU or GPU time per frame.

Subtasks:

- 01: the intent audit, which needs no GPU
- 02: a code review against gfx, which needs no GPU
- 03: the benchmark plan, written but not run

Running the benchmark is a later task. Subtask 03 creates it.

## Sources of intent

- `third_party/NoGraphicsAPI`: `README.md`, `docs/no-graphics-api-comparison.md`, and
  `AGENTS.md`. Its `AGENTS.md` says to review all code for performance.
- Sebastian Aaltonen's "No Graphics API" blog post, which the README says it implements.
  The post isn't stored here. Cite it by section.
- The earlier work:
  - `../goose-nogfx-prototype/AGENTS.md`, which says to mirror the examples and
    `upload_queue.cpp` "barrier for barrier".
  - `docs/design/ngfx.md` in the fork `../goose-nogfx`, commits `cc98116` and `c87a4a3`.
- The fork's `docs/nogfx/sync-analysis.md` and `docs/nogfx/mips-research.md`. Both were
  deleted. Recover them from that repository's history, or from the goose-nogfx Claude
  session transcripts, if they were never committed.

## Acceptance criteria

- [ ] Subtasks 01, 02, and 03 are done
- [ ] One summary in `docs/design.md` says whether the architecture holds, and names
      each decision this task changed
