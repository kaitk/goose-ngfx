# Tasks

Markdown-based task tracking. One file per task, or one folder for a task with
several subtasks or its own supporting files.

## Naming

`NNN-short-slug.md`: a zero-padded sequential number plus a kebab-case slug, for example
`002-copy-queue-uploads.md`.

A task with subtasks or supporting files is a folder with the same name,
`NNN-short-slug/`, holding the task itself as `README.md` and one file per subtask as
`NN-short-slug.md`, numbered within the folder. Subtasks use the same format as tasks.

## Format

```markdown
# NNN: Title

Status: todo | in-progress | done | cancelled

Short description of what and why.

## Acceptance criteria

- [ ] Concrete, verifiable outcome
- [ ] ...
```

Update the status line as work progresses, and tick criteria as they are met. A cancelled
task says who cancelled it, when, and why. A task that measures something records the
numbers in its own file, with how they were measured. Decisions a task reaches go into
`docs/design.md` too, and Goose gaps into `docs/goose-findings.md`.

## Archive

When a task is done and nothing still builds on its file, move it to `000-archive/` with
`git mv`, keeping its name. The main folder then lists only open work. Numbers stay
unique across both folders: pick the next number after the highest in either. Refer to
tasks by number ("task 001"), not by path, so a move breaks no reference.

## Order

Task 001 completed the architecture audits and benchmark plan. It remains here because
task 002 builds on that plan. Task 002 has a harness, workloads, and GPU timestamps;
its full measurements and design conclusions remain open.

Task 003 implements overlapping frames but still needs before/after measurements from
task 002. Task 004 waits for task 002's pacing results. Tasks 005 to 007 are implemented
and archived. Task 008 implements the Metal hang workaround but still needs validation
on a later macOS version, a multipass comparison, and upstream reports.
