# 002: Benchmark ngfx against gfx

Status: todo

Run the plan in task 001's subtask 03, and record the numbers here with the commands
and machines that produced them.

## Acceptance criteria

- [ ] `bench/run_bench.py` and the `draws` and `uploads` programs, as subtask 03 specifies
- [ ] The GPU timestamps behind `GOOSE_NGFX_BENCH=1` in the layer
- [ ] Results for every workload and condition in subtask 03, on the M1 Pro and the RTX
      4090, and ngfx's on Linux headless
- [ ] Each "doesn't hold" line in subtask 03 checked, and the decisions it names updated
      in `docs/design.md` or confirmed there
