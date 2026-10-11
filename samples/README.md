# Samples

Ports of Goose's gfx samples to ngfx. Each prints what its original prints, and with
`--frames N` stops after N frames and saves its last frame as a PNG here.
`scripts/run_tests.py` runs each with the arguments in `data/<name>.args` and compares
what it prints with `expected/<name>.out`. Run them from this directory, with `goose
<name>.goose` or `goose build <name>.goose`
([docs/development.md](../docs/development.md#run-the-samples)).

| Sample | What it shows |
|---|---|
| [cube](cube.goose) | Goose's 27_gfx_cube, drawn the way NoGraphicsAPI draws: one Slang module from `ngfx::slang`, vertices in a GPU buffer the vertex shader reads through a pointer in its root, and the root filled each frame with `ngfx::root`. |
| [ui_todo](ui_todo.goose) | Goose's 29_ui_todo, with `ui` drawn through ngfx by `ngfx_ui`, and Roboto embedded with `embed_file`. |
| [mini_minecraft](mini_minecraft.goose) | Goose's 30_mini_minecraft: chunk meshes in GPU buffers, the scene, HUD, and fragments in each frame's memory, and the sky, world, and HUD as Slang modules. |
| [mini_doom](mini_doom.goose) | Goose's 31_mini_doom: the world and HUD meshes rebuilt into each frame's memory and fetched by the shaders through their roots. It plays Goose's Freedoom WAD, copied to `data/`. |
