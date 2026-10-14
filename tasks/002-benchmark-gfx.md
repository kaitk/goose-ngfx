# 002: Benchmark ngfx against gfx

Status: in-progress

Run the plan in task 001's subtask 03, and record the numbers here with the commands
and machines that produced them.

## Acceptance criteria

- [x] `bench/run_bench.py` and the `draws` and `uploads` programs, as subtask 03 specifies
- [x] The GPU timestamps behind `GOOSE_NGFX_BENCH=1` in the layer
- [ ] Validate the harness against subtask 03's plan, including comparable headless GPU
      completion and gfx GPU timing; record any differences in method
- [ ] Results for every workload and condition in subtask 03, on the M1 Pro and the RTX
      4090, and ngfx's on Linux headless
- [ ] Each "doesn't hold" line in subtask 03 checked, and the decisions it names updated
      in `docs/design.md` or confirmed there

## Implemented support

`fbcf949` adds the harness, draw and upload workloads, GPU timestamps, and Slang timing.
Task 008 records limited Metal measurements made with this support; they do not replace
the full comparison required here. See [the benchmark instructions](../docs/development.md#benchmark)
for the harness's current generated-source and result locations.
