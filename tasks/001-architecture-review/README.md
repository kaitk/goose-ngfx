# 001: Review the architecture

Status: done

The audits reviewed ngfx's policies against NoGraphicsAPI's intent and gfx's CPU and
GPU work. Their conclusions and implemented changes are summarized in
[the design status](../../docs/design.md#status). Correctness is tested; performance
parity remains a measurement question for task 002, under the plan in subtask 03.
This completed task stays outside the archive while task 002 builds on that plan.

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
- Historical design in the Goose fork:
  [`docs/design/ngfx.md` at `cc98116`](https://github.com/kaitk/goose/blob/cc98116/docs/design/ngfx.md)
  and [`c87a4a3`](https://github.com/kaitk/goose/blob/c87a4a3/docs/design/ngfx.md).
  The audit also used prototype notes and recovered synchronization and mip research
  that are not tracked here. Current decisions are in `docs/design.md`; those local
  working files are not prerequisites for setup or further work.

## Acceptance criteria

- [x] Subtasks 01, 02, and 03 are done
- [x] One summary in `docs/design.md` says whether the architecture holds, and names
      each decision this task changed
