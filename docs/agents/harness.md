# Agent harness

`bin/harbagsa-agent` drives the simulation and writes exact screenshots. It
needs no window, compositor, cursor capture, or external image tool. The user
reference is `README.md`. This page is the operational guide for agents.

## Quick start

```sh
tools/make.sh build
./bin/harbagsa-agent schema
./bin/harbagsa-agent run scenarios/lamp-threshold.json
```

Use `tools/make.sh` when another agent may build in the same checkout. It
serializes Make with `flock`. Read `runs/lamp-threshold/report.json` after a run.
Exit 0 means the run completed.

Recipes:

```sh
# Capture a lamp wall plane.
make shot SCENARIO=lamp-threshold OUT=runs/lamp-threshold

# Run without a renderer.
./bin/harbagsa-agent run scenarios/perf.json --no-render --out runs/perf-cpu

# Measure the default view.
./bin/harbagsa-agent run scenarios/perf.json --out runs/perf

# Measure the arena from above.
./bin/harbagsa-agent run scenarios/perf-arena.json --out runs/perf-arena
```

`run -` reads JSON from standard input. `--tag NAME` appends a directory to the
run path. `--out DIR` chooses the whole run directory.

## Surface map

| Task | Read or run |
| --- | --- |
| drive the simulation | **Scenario format** and **Commands** |
| place or remove an object | **Place and remove** |
| drive the editor | **Editor** |
| build and publish a bake | **Bake lifecycle** |
| capture the final image | **Capture targets** |
| capture one lighting term | **Capture targets** and **Diagnostic views** |
| resolve one pixel | **Pick** |
| read velocity, history, depth, or scene colour | **Capture targets** |
| read numeric image statistics | **Capture targets** |
| read renderer state | **Renderer state** |
| change a renderer input | **Renderer debug overrides** |
| inspect static arena boxes | `harbagsa-agent boxes` |
| compare two runs | `compare`, `diff`, or `ab --visual` |
| capture a lamp wall plane | `scenarios/lamp-threshold.json` |
| measure the default view | `scenarios/perf.json` |
| measure the arena from above | `scenarios/perf-arena.json` |
| measure 96 lights at 1080p | `scenarios/perf-mixed.json` |
| review the mixed-lighting evidence | `docs/evidence/mixed-lighting.md` |
| measure performance | **Performance** |
| reproduce a live view | **Live repro** |
| understand a design choice | `docs/adr/0045-mixed-static-baked-indirect.md` |
| understand diagnostic views | `docs/adr/0046-diagnostic-views.md` |

## What one run writes

- `report.json`: result, final state, setup, captures, picks, failures, digest,
  error, and named perf reports.
- `state.json`: final state alone.
- `frames/`: PNG, float, or raw captures.
- `trace.jsonl`: opt-in perf samples.
- `run.log`: renderer, session, and runner logs.

A capture entry carries its name, note, target, format, PNG flag, path, render
digest, and renderer state. Each colour PNG after the first also carries delta
metrics against the previous colour capture.

Exit codes: 0 the run completed, 1 a command failed, 2 bad arguments or
scenario, 3 renderer, backend, or file failure.

## Scenario format

```json
{
  "view": {"hud": false, "debug": false, "hint": false, "perf": false},
  "commands": [
    {"cmd": "look", "dx": 220, "dy": 0},
    {"cmd": "input", "forward": 1},
    {"cmd": "step", "frames": 90},
    {"cmd": "input", "jump": true},
    {"cmd": "step", "frames": 1},
    {"cmd": "capture", "name": "after-jump"}
  ]
}
```

Rules:

- Commands run verbatim. `record` writes the same form.
- One step is one fixed simulation step. The runner does not use wall time.
- `look` applies once. `input` persists. Jump is an edge on the first frame.
- Only `capture` or `captures` writes an image. A scenario without captures or
  perf does not create a Vulkan device unless `--present` is set.
- Capture frame numbers are zero-based. A past frame is an error; a future frame
  queues.
- `settle` renders without writing a capture. Under `--no-render`, it is a plain
  step.
- `size` pins the extent. A scenario `size` and `--size` together are an error.
- `extends` merges a base scenario and lets the child win.
- `parameters` substitutes `${name}` in command values. `--param` overrides it;
  comma values run a sweep.
- `requires.renderer_debug` enables the debug gate for that scenario.
- A top-level `renderer_debug` compiles to one command before the command list.
- `note` on the scenario or a capture is echoed into the report.

Every angle is degrees and ends in `_deg`. Positions, heights, and ranges are
metres. `look` deltas are pixels. Step and perf counts are frames. `perf.prime`
is seconds or `"once"`. Capture regions and crops are pixels unless `unit` is
`normalized`.

## Commands

- `reset`: fresh simulation, settings, menu, and debug state.
- `look`: `dx`, `dy` through game sensitivity.
- `face`: direct camera `yaw_deg` and `pitch_deg`. The body keeps its heading.
- `input`: persistent `forward`, `right`, and `sprint`; `jump` is a one-step edge.
- `step`: `frames` in the allowed fixed-step range.
- `settle`: `frames`, or `until: converged`.
- `state`: full current state.
- `capture`: one output with `name`, optional `frame`, `alpha`, `note`, target,
  format, capture options, and an optional `views` list.
- `captures`: up to eight outputs from one frame.
- `camera`: `position` plus `look_at` or `yaw_deg`/`pitch_deg`, optional
  `fov_deg`; `clear: true` removes the override.
- `view`: `hud`, `debug`, `hint`, and `perf` flags.
- `debug_mode`: `active` boolean.
- `editor`: palette, placement, object, light, camera, pointer, and history fields.
- `menu`: `open`, `item`, `activate`, `direction`, and `set`.
- `record`: start with `path` and optional `actions`; stop with no path.
- `replay`: `path` to a recorded scenario.
- `repro`: `path` for a live scene snapshot.
- `perf`: `frames`, `warmup`, `prime`, `name`, `variants`, `rounds`,
  `baseline`, `discard`, and optional `trace`.
- `renderer_debug`: gated fields or `clear`. A field set to `null` resets it.
- `displays`: `set` a scripted list or `clear` it.
- `rows`: HUD and menu rows.
- `scene`: exact `camera`, `objects`, `settings`, `view`, `displays`, and
  `renderer_debug` blocks. Every block is optional; at least one is required.
- `place`: `prefab`, `position`, optional `yaw_deg`, `body`, `name`, and `light`.
- `remove`: object `id` or `name`.
- `bake`: rebuild and publish the static indirect; optional `probe_spacing`,
  `threads`, and `out`.
- `pick`: resolve one pixel with `at`; see **Pick**.
- `get`: one state or capture `field`.
- `quit`: stop the session.

Unknown keys, wrong types, and out-of-range values are command errors. A live
session remains usable. `step` and `settle` are errors while the menu is open.

A `shot` is scenario-only shorthand. It expands to an optional camera, a settle,
and one capture. It is not a live-session command.

## Player state

`state.player` reports the body position, the body yaw, the camera yaw and pitch,
the gait, the grounded flag, `legs_planted`, and one entry per leg. Each leg
entry holds `foot` and `planted`. `state.camera` reports the computed
third-person camera with the source `third_person`.

A scene player block takes `position` and `yaw_deg`, plus optional
`camera_yaw_deg`, `camera_pitch_deg`, `velocity`, and `grounded`. A scene camera
source may be `third_person` or `player`; both mean the orbit camera. Older
stance, eye-height, and step-smoothing keys are command errors.

## Place and remove

`place` creates one object without entering debug mode. It draws no editor
lines and adds no undo entry. `prefab` and `position` are required. `body`
defaults to the prefab. A lamp body follows its `light.kind`: `static` gives a
static fixture, and `dynamic` gives a dynamic lamp. A name is unique, at most 31
letters, digits, `-`, or `_`, and is neither all digits nor `count`.

```json
{"cmd":"place","prefab":"Lamp","position":[13.5,2.75,10.5],"body":"static",
 "name":"key-lamp","light":{"kind":"static","color":"warm","intensity":1.5,"range":8}}
```

A `light` block is valid only for a lamp prefab. Omitted fields keep prefab
defaults. `remove` deletes by id or name. Names survive undo and scene snapshots.

## Editor

Enter debug mode before `editor`. The keyboard and harness build the same edit
actions. Fields cover:

- `open`, `select`, `palette_step`, and `palette_number` for the catalog.
- `pick`, `height`, `yaw_deg`, `snap`, and `cancel` for the armed placement.
- `place` for an exact transform without a placement ray.
- `select_object`, `move`, `rotate_deg`, `body`, `flip_body`, `delete`, and
  `duplicate` for an object. A body request on a lamp fails with `a lamp body
  follows its kind`; change `light_kind` instead.
- `turn`, `wheel`, `large`, `primary`, `secondary`, `drag_move`, and
  `drag_release` for pointer-relative input.
- `light_kind`, `light_color`, `light_intensity`, and `light_range` for the next
  or selected lamp.
- `undo` and `redo` for history.
- `camera` for the free-fly camera.

Catalog order: Crate, Small crate, Wide crate, Block, Platform, Ramp, Pillar,
Wall, Lamp, Light panel, Beacon. A lamp kind is `static` or `dynamic`; a static
fixture uses a static body and bakes indirect, and a dynamic lamp uses a dynamic
body and contributes direct light only. Newly placed lamps default to dynamic.
Lamp light colour is warm, cool, red, green, or blue. Intensity is in [0.2, 4.0].
Range is in [2, 20] metres.

## Live session

```sh
printf '%s\n' \
  '{"cmd":"step","frames":60}' \
  '{"cmd":"state"}' \
  '{"cmd":"get","field":"objects.count"}' \
  '{"cmd":"quit"}' |
  ./bin/harbagsa-agent session
```

Standard input and output carry one JSON object per line. `session --socket
/tmp/harbagsa.sock` serves the same protocol on a Unix socket. Capture files go
to `runs/session/frames/` unless `--out` selects another directory.

`record PATH` starts a recording. A second `record` stops and writes it. The
recording starts with `reset`, one `scene` snapshot, and current input.
`actions: true` omits the snapshot. `replay PATH` resets and runs a scenario.

## Live repro

`F5` in the game and `repro` in the harness write one normal scenario with one
`scene` command. The scene carries the exact camera, placed objects and lights,
settings, display list, view flags, and effective renderer debug overrides.
`record` starts with the same scene.

The default game path is `runs/repro/repro-<unix-ms>.json`. `--repro-dir DIR` or
`HARBAGSA_REPRO_DIR` moves it. A harness-relative path resolves under the run or
session output directory. A notice reports success or failure.

## Capture targets

| Target | Image | Default format |
| --- | --- | --- |
| `color` | final image after overlay | `png` |
| `velocity` | screen motion in unjittered UV and linear view depth in `.z` | `stats` |
| `history` | resolved history with linear colour and view depth in `.a` | `stats` |
| `depth` | hardware depth in [0, 1] | `stats` |
| `scene_color` | linear scene colour before resolve | `stats` |

Formats:

- `png`: 8-bit RGBA sRGB for colour.
- `float`: RGBA little-endian `f32` for an intermediate target.
- `raw`: exact texel bytes for an intermediate target. The report names the
  Vulkan format.
- `stats`: per-channel minimum, maximum, mean, standard deviation, and gradient.
  It writes no file unless `png: true` adds a colour sidecar.
- `profile`: a line or mean-span measurement with a 10%–90% crossing width.

A stats capture accepts `region` or `rect`, `histogram`, `steps`, `color_key`,
and `coverage`. A normalized region uses fractions of the frame. Coverage
reports exact-zero fraction and optional black and lit fractions. A colour
capture accepts `crop`. `captures` shares one rendered frame across all outputs, and each output may
name its own `views`.

### Diagnostic views

`views` on a `capture` output names one to eight views. One simulation frame
writes one capture entry per view, named `<name>-<view>`, each with a `view`
field and the same `frame`, camera, and renderer report. `target` and `views` are
mutually exclusive, and per-view output options apply to every view.

| View | Image |
| --- | --- |
| `beauty` | the composed frame, identical to a color capture of that frame |
| `direct` | shadowed direct light times albedo |
| `lightmap` | the weighted baked lightmap term times albedo |
| `probe` | the weighted static probe term times albedo |
| `emissive` | the emission term times albedo |
| `shadow` | shadow visibility as a grey ramp: shadowed direct over open direct |
| `lightmap_grid` | atlas texel checker plus a red chart-edge line; magenta with no tile |
| `probe_cell` | hashed probe cell id hue; red when a cell probe is invalid; magenta outside the volume |

Each term view is one extra lit pass at the same jitter and shares the TAA
history: the resolve reads and writes no history, and the next beauty frame is
unaffected. A term view is a single sample, so a noisy bake stays noisy in the
term image. A `float` or `raw` view is a command error; use `scene_color` for
linear analysis. A capture without `views` is the beauty path and is byte
identical to the same capture before views existed.

```json
{"cmd":"capture","name":"terms","views":["beauty","direct","lightmap","probe"]}
```

`scenarios/capture-views.json` captures all eight views in one frame and then a
plain color capture to prove the history survived.

A named capture exposes its own renderer state through `get`, for example
`capture.named.lit.renderer.light_count` and
`capture.named.lit.render_digest`.

## Pick

`pick` resolves one pixel to the surface under it. `at` is `[x, y]` in the
capture extent with the origin at the top left. The renderer draws one frame
with no capture, forces that frame's TLAS build, and traces the pixel's camera
ray in a one-pixel compute pass. The pass evaluates the shared term include, so
a pick names the same direct, shadow, lightmap, probe, and emissive values the
lit pass wrote. The frame uses the unjittered camera, consumes no jitter sample,
and advances TAA history like a settle frame; a pick writes no capture and no
render digest of its own.

A hit carries:

- `object`: the scene identity. Static arena boxes carry `kind: "static_box"`
  and `index`. Placed objects carry `kind: "object"`, `id`, `prefab`, and
  `name` when the object has one. Spider boxes carry `kind: "spider"` and
  `index`.
- `prefab`: the placed object's prefab, when there is one.
- `distance`, `position`, and `normal`: the ray distance, world hit point, and
  world normal.
- `face`: the box face index in `+X, -X, +Y, -Y, +Z, -Z` order.
- `lightmap`: `rect` in atlas UV and the `texel` the face sample read. A surface
  with no tile reports a zero rect and `texel: [-1, -1]`.
- `probe_cell`: the `base` cell, the `invalid` probe count, and whether the hit
  is `inside` the probe volume.
- `terms`: linear `direct`, `shadow`, `lightmap`, `probe`, and `emissive`.

A miss reports `hit: false` and no other key. A run appends every pick to
`report.picks`; a session reply carries the same object under `pick`. `pick`
needs a renderer, so it is a command error under `--no-render`. It is also a
command error while the menu is open and when `at` is outside the capture
extent.

```json
{"cmd": "pick", "at": [640, 360]}
```

`scenarios/pick.json` picks a lit static crate and then empty space. The
instance custom index is the scene box order: static arena boxes, placed
objects, then the spider.

## Renderer state

`state.renderer` reports frame count, TAA state, jitter index, history validity,
convergence frames, history read index and weight, reset count and reason,
active light count, cluster overflow, atlas weight, text counters, timestamp
period, and debug line counts. `state.bake` is the lifecycle view and `state.renderer.bake` is the
same report inside the renderer block. Both report the status (`missing`,
`stale`, `current`, or `failed`), the current key, the artifact key, format and
tool versions, the measured bake time, atlas and probe counts, probe spacing,
the invalid-probe count before dilation, the dynamic boxes whose centre is
outside the probe volume (`probe_missing`), artifact and GPU bytes, and the load
or publish error. `state.render_digest` covers target extent, camera, boxes, box
slots, emissive strengths, point lights, jitter, atlas weight, clip height,
shadow visibility, lightmap, probe, bake key, bake status, and view flags.
`setup.renderer.shader_digest` covers the embedded SPIR-V.

## Bake lifecycle

The renderer loads `build/bake/arena.hbake` by default. `make bake` writes it
from the static arena boxes, placed static bodies, and static fixtures; dynamic
lamps and dynamic bodies never enter the bake. `bin/harbagsa-bake
--probe-spacing 2` writes the 2 m fallback, and the runtime validates either
spacing against the artifact's own quality block. The tool reports its bake
time, ray counts, static light count, byte sizes, invalid and dilated texels,
and invalid and dilated probes. The artifact stores zero bake time so identical
inputs produce identical bytes.

A current artifact is sampled by both indirect paths. Each static face derives
its atlas UV from the local position and local face normal, so no vertex UV
channel is added. The lightmap carries static indirect only; direct light and
hard shadows stay real-time. Dynamic boxes sample the probe field tetrahedrally
over the four probes of the containing cell: normal bias, facing weight, and the
baked depth-moment test select and weight the probes. The stored probe
irradiance is `(radiance/2)^(1/5)`; the shader decodes it with
`pow(encoded, 2.5)`, averages, squares, and applies the 2x factor, which puts
probes and the lightmap on one scale. Invalid probes are skipped, never
black-filled. The bake dilates a probe that the virtual offset could not repair
by copying the nearest valid probe and pointing the offset at that probe's
sample position, so the copied moments keep their origin.
`state.bake.invalid_probes` is the count before that dilation.

The `bake` command rebuilds from the current static input and publishes the new
artifact without restarting the renderer. It accepts optional `probe_spacing`
(1 or 2), `threads` (1 to 256), and `out` (write the artifact to this path).
The command requires a renderer. The default build uses 1 m probes, 128 lightmap
rays, 1024 probe rays, and one bounce; it takes about 5 s at 16 threads. Use
`probe_spacing: 2` for the measured fallback when probe work or memory is the
limit. `make bake` writes `<artifact>.time` beside the artifact; the renderer
reads that sidecar so a loaded bake reports its measured time without changing
the artifact bytes. `state.bake.bake_ms` is the measured wall time of the last
publish or the loaded sidecar.

```json
{"cmd":"bake","out":"build/bake/arena.hbake"}
```

A static fixture or static geometry edit changes the key and sets the status to
`stale` immediately, even before the next frame. Direct light updates at once;
the old indirect stays bound and visible until the publish. A dynamic lamp or
crate move leaves the key unchanged and the status `current`. A publish failure
leaves the old artifact bound and reports `failed`; it never falls back to black
or to another bake. Removing every static fixture and publishing a fresh bake
yields zero indirect, and a lamp-free view stays black.

Use `--bake PATH` on `run` or `session` to load another artifact:

```sh
./bin/harbagsa-agent run scenarios/lamp-threshold.json \
  --bake build/bake/arena.hbake --out runs/bake/current
```

A version or layout mismatch sets `status` to `failed` and records the loader
error. The artifact format is documented in
`docs/adr/0044-bake-data-contract.md`; the mixed-lighting decision is
`docs/adr/0045-mixed-static-baked-indirect.md`. `scenarios/bake-lifecycle.json`
exercises the current, stale, and dynamic-move states;
`scenarios/bake-empty.json` removes every static fixture and captures the
lamp-free result; `scenarios/bake-hud.json` captures the lamp kind and bake
status in the debug HUD.

The measurement pass has its own scenarios. `scenarios/lighting-quality.json`
pairs the baked bounce with the direct-only view, then moves a crate, moves a
dynamic lamp, and removes a static fixture. `scenarios/lighting-wall.json` seals
a fixture inside a four-wall cell and moves it out of range.
`scenarios/lighting-seam.json` looks at lightmap chart borders with the term on
and off. `scenarios/lighting-noise.json` measures the baked indirect's texel
noise on an unlit wall, with a clean window and the term off as the control.
`scenarios/lighting-missing.json` is the missing-artifact view; run it
with `--bake` pointing at a path that does not exist. The numbers and the
accepted limits are in `docs/evidence/mixed-lighting.md`.

## Renderer debug overrides

Supported fields:

- `taa`, `jitter`, `history_weight`, `clamp`, and `depth_trust`.
- `synthetic_lights`: replace frame lights with a generated field of any count.
- `clip_height`: discard fragments above a world height for a plan view.
- `light_shadows`: trace point-light shadow rays. It defaults true. Set false to
  isolate the shadow term in a paired capture; a frame-budget run keeps it on.
- `lightmap`: add the baked static lightmap term. It defaults true.
- `probe`: add the baked probe term. It defaults true. Set both `lightmap` and
  `probe` to false for a direct-light capture.
- `clear`: restore every default. Set one field to `null` to reset only that field.

A scenario declares `requires.renderer_debug`, or the run uses
`--debug-renderer`. Every effective change resets TAA history.

## Static boxes and plan views

`boxes` prints immutable arena geometry without a renderer. `state.static_boxes`
exposes the same data. Each entry has centre, half extents, colour, rotation,
emissive strength, and visual-only flag.

Use `renderer_debug.clip_height` in a scenario to hide upper geometry for a plan
view.

## Performance

A `perf` command measures frames and can write one trace. `frames` defaults to
120, `warmup` to 60, and `prime` to 2 seconds. `prime` is a number of seconds or
`"once"`. A number primes before every measured window; `"once"` primes before
the first one only. `prime: 0` disables the time loop. Offscreen measures
throughput. `--present` measures pacing.

`variants` names a renderer-debug patch per variant, including
`synthetic_lights`. A perf command with variants needs the renderer-debug gate,
just like a `renderer_debug` command. `rounds` repeats the schedule, `baseline`
names the reference variant, and `discard` asks to drop that many opening
rounds. Both default to one; the baseline defaults to the first variant in name
order, and at most `rounds - 1` rounds are dropped so one round is always kept.
The report carries the requested `discard` and the effective `discarded`. Each
round runs the baseline, then every other variant with a baseline window after
it, so every variant is bracketed by two baseline windows. The report carries
the interval, CPU, and GPU stats per variant, the per-round delta against the
mean of the two bracketing baseline windows for the frame interval p50 and the
GPU total p50, and the mean, minimum, maximum, and spread of each delta. The
baseline variant is the reference, so it reports no delta. A perf command
without `variants` measures one window per round and reports the same stats as
before; `discard` applies there the same way.

The report also carries `timestamp_period`, the GPU clock at start and end, and
the 1, 5, and 15 minute load average at start and end. `nvidia-smi` or
`rocm-smi` supplies the clock, whichever matches the rendering device first.
When neither answers, the clock is `known: false` and the report warns; the load
average warns the same way when `/proc/loadavg` cannot be read.

A perf frame draws the scene without a capture request, so it does no readback
and adds no capture entry. A capture after the perf windows still runs. A
pending capture when the perf command starts is an error: a queued readback
would otherwise be measured as frame time. The interval is comparable with the
GPU total plus submit cost. Do not compare an interval measured before that
change with one measured after it.

GPU passes are TLAS, cluster, depth, scene, TAA, and overlay. A capture with
diagnostic views adds one untimed lit pass and one resolve per view after the
measured passes, so a perf window never includes them. The report carries
`p50`, `p95`, and `mean` for each CPU phase and GPU pass. Perf data is
wall-clock data and is not deterministic.

Use `scenarios/perf.json` for the default view, `scenarios/perf-arena.json` for
the arena from above, and `scenarios/perf-mixed.json` for 96 synthetic lights at
1080p, where one perf command brackets direct, lightmap, probe, and mixed
variants over three rounds. `harbagsa-agent ab` compares two builds. `ab
--visual` runs one scenario on both and writes a compare panel.

## Determinism and screenshots

The offscreen target submits one frame at a time because it owns one colour
image and one readback buffer. TAA history affects exact pixels, so before and
after runs must use the same command sequence and history. Term views do not
advance or reset that history, so a capture with views and a capture without
them agree on every later frame.

Run the same scenario for before and after evidence:

```sh
./bin/harbagsa-agent run scenarios/lamp-threshold.json --out runs/change/before
./bin/harbagsa-agent run scenarios/lamp-threshold.json --out runs/change/after
./bin/harbagsa-agent compare runs/change/before runs/change/after --delta
```

Keep output under `runs/`. Never commit images.
