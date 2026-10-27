# Agent harness

`bin/harbagsa-agent` drives the simulation, runs checks, and writes exact
screenshots. It needs no window, compositor, cursor capture, or external image
tool. The user reference is `README.md`. This page is the operational guide for
agents.

## Quick start

```sh
tools/make.sh build
./bin/harbagsa-agent schema
./bin/harbagsa-agent run scenarios/smoke.json
```

Use `tools/make.sh` when another agent may build in the same checkout. It
serializes Make with `flock`. Read `runs/smoke/report.json` after a run. Exit 0
means every blocking check passed.

Five recipes:

```sh
# Capture the HUD.
make shot SCENARIO=hud OUT=runs/ui/hud

# Capture the settings menu.
./bin/harbagsa-agent run scenarios/settings-menu.json --out runs/ui/menu

# Assert state without a renderer.
./bin/harbagsa-agent run scenarios/smoke.json --no-render --out runs/smoke-cpu

# Run the short gate.
make quick

# Measure direct lights.
./bin/harbagsa-agent run scenarios/perf-lamps.json --out runs/perf-lamps
```

`run -` reads JSON from standard input. `--tag NAME` appends a directory to the
run path. `--out DIR` chooses the whole run directory.

## Surface map

| Task | Read or run |
| --- | --- |
| drive the simulation | **Scenario format** and **Commands** |
| place or remove an object | **Place and remove** |
| drive the editor | **Editor** |
| capture the final image | **Capture targets** |
| read velocity, history, depth, or scene colour | **Capture targets** |
| read numeric image statistics | **Capture targets** |
| read renderer state | **Renderer state** |
| change a renderer input | **Renderer debug overrides** |
| inspect static arena boxes | `harbagsa-agent boxes` |
| read check gates and margins | `harbagsa-agent checks RUN` |
| compare two runs | `compare`, `diff`, or `ab --visual` |
| test direct lighting | `scenarios/room-lighting.json`, `scenarios/light-move.json` |
| measure stability or banding | **Analysis** |
| measure performance | **Performance** |
| reproduce a live view | **Live repro** |
| understand a design choice | `docs/adr/0037-direct-dynamic-point-lights.md` |

## What one run writes

- `report.json`: result, final state, setup, captures, checks, failures, digest,
  error, and named perf reports.
- `state.json`: final state alone.
- `analysis.json`: image analysis when colour captures exist.
- `frames/`: PNG, float, or raw captures and optional analysis maps.
- `trace.jsonl`: opt-in perf samples.
- `run.log`: renderer, session, and runner logs.

A capture entry carries its name, note, target, format, PNG flag, path, render
digest, and renderer state. Each colour PNG after the first also carries delta
metrics against the previous colour capture.

Exit codes: 0 pass, 1 failed check or invariant, 2 bad arguments or scenario,
3 renderer, backend, or file failure.

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
  ],
  "checks": [
    {"field": "player.position.y", "op": "gt", "value": 0}
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
- `analysis: false` disables analysis. An analysis object selects window, maps,
  and region.
- `note` on the scenario or a capture is echoed into the report.

Every angle is degrees and ends in `_deg`. Positions, heights, and ranges are
metres. `look` deltas are pixels. Step and perf counts are frames. `perf.prime`
is seconds. Capture regions and crops are pixels unless `unit` is `normalized`.

## Commands

- `reset`: fresh simulation, settings, menu, and debug state.
- `look`: `dx`, `dy` through game sensitivity.
- `face`: direct player `yaw_deg` and `pitch_deg`.
- `input`: persistent `forward`, `right`, and `jump`.
- `step`: `frames` in the allowed fixed-step range.
- `settle`: `frames`, or `until: converged`.
- `state`: full current state.
- `capture`: one output with `name`, optional `frame`, `alpha`, `note`, target,
  format, and capture options.
- `captures`: up to eight outputs from one frame.
- `camera`: `position` plus `look_at` or `yaw_deg`/`pitch_deg`, optional
  `fov_deg`; `clear: true` removes the override.
- `view`: `hud`, `debug`, `hint`, and `perf` flags.
- `debug_mode`: `active` boolean.
- `editor`: palette, placement, object, light, camera, pointer, and history fields.
- `menu`: `open`, `item`, `activate`, `direction`, and `set`.
- `check`: `field`, `op`, `value` or `other`, optional `tolerance` and `advisory`.
- `record`: start with `path` and optional `actions`; stop with no path.
- `replay`: `path` to a recorded scenario.
- `repro`: `path` for a live scene snapshot.
- `perf`: `frames`, `warmup`, `prime`, `name`, and optional `trace`.
- `renderer_debug`: gated fields or `clear`. A field set to `null` resets it.
- `displays`: `set` a scripted list or `clear` it.
- `rows`: HUD and menu rows.
- `scene`: exact `camera`, `objects`, `settings`, `view`, `displays`, and
  `renderer_debug` blocks. Every block is optional; at least one is required.
- `place`: `prefab`, `position`, optional `yaw_deg`, `body`, `name`, and `light`.
- `remove`: object `id` or `name`.
- `get`: one `field` without adding a check.
- `quit`: stop the session.

Unknown keys, wrong types, and out-of-range values are command errors. A live
session remains usable. `step` and `settle` are errors while the menu is open.

A `shot` is scenario-only shorthand. It expands to an optional camera, a settle,
and one capture. It is not a live-session command.

## Place and remove

`place` creates one object without entering debug mode. It draws no editor
lines and adds no undo entry. `prefab` and `position` are required. `body`
defaults to the prefab. A name is unique, at most 31 letters, digits, `-`, or
`_`, and is neither all digits nor `count`.

```json
{"cmd":"place","prefab":"Lamp","position":[13.5,2.75,10.5],"body":"static",
 "name":"key-lamp","light":{"color":"warm","intensity":1.5,"range":8}}
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
  `duplicate` for an object.
- `turn`, `wheel`, `large`, `primary`, `secondary`, `drag_move`, and
  `drag_release` for pointer-relative input.
- `light_color`, `light_intensity`, and `light_range` for the next or selected lamp.
- `undo` and `redo` for history.
- `camera` for the free-fly camera.

Catalog order: Crate, Small crate, Wide crate, Block, Platform, Ramp, Pillar,
Wall, Lamp, Light panel, Beacon. Lamp light colour is warm, cool, red, green, or
blue. Intensity is in [0.2, 4.0]. Range is in [2, 20] metres.

`scenarios/editor-lamps.json` covers lamp previews, placement, light values,
selection, editing, and undo. `scenarios/editor-ghost.json` covers the armed
ghost. `scenarios/editor-object.json` covers object edits and history.

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
capture accepts `crop`. `captures` shares one rendered frame across all outputs.

A named capture exposes its own renderer state: for example,
`capture.named.lit.renderer.light_count` and
`capture.named.lit.render_digest`.

## Checks

Operators are `eq`, `ne`, `lt`, `le`, `gt`, and `ge`. A numeric `tolerance`
applies to `eq` and `ne`. A check compares with `value` or `other`.

```json
{"cmd":"check","field":"capture.named.near.stats.mean.y","op":"gt",
 "other":"capture.named.far.stats.mean.y"}
```

`capture.N` addresses a capture by index. `capture.first` and `capture.last` are
aliases. `capture.named.<name>` addresses one by name. Aggregate fields include
`capture.count`, `capture.worst_mean_delta`, `capture.worst_max_delta`, and
`capture.worst_over_16_fraction`. `warmup` skips captures. `window` selects a
start and count.

An advisory check records a miss without failing the run. A field or type error
still fails. `harbagsa-agent checks RUN` prints every gate and margin.

## Analysis

A run with colour captures writes `analysis.json`. It holds pair deltas, a
summary, dominant period, worst unstable pixels, and optional diff and variance
maps. Disable it with `analysis: false` or `--no-analysis`.

Checks can read `analysis.period.frames`, `analysis.period.correlation`,
`analysis.bands.longest_run`, `analysis.bands.median_run`, and the other analysis
fields in the schema. `scenarios/taa-static.json` and
`scenarios/taa-motion.json` gate temporal stability. `scenarios/banding.json`
gates output quantization on a direct-lamp gradient.

## Renderer state

`state.renderer` reports frame count, TAA state, jitter index, history validity,
convergence frames, history read index and weight, reset count and reason,
active light count, cluster overflow, atlas weight, text counters, and debug
line counts. `state.render_digest` covers target extent, camera, boxes,
emissive strengths, point lights, jitter, atlas weight, clip height, and view
flags. `setup.renderer.shader_digest` covers the embedded SPIR-V.

## Renderer debug overrides

Supported fields:

- `taa`, `jitter`, `history_weight`, `clamp`, and `depth_trust`.
- `synthetic_lights`: replace frame lights with a generated field of any count.
- `clip_height`: discard fragments above a world height for a plan view.
- `clear`: restore every default. Set one field to `null` to reset only that field.

A scenario declares `requires.renderer_debug`, or the run uses
`--debug-renderer`. Every effective change resets TAA history.

## Static boxes and plan views

`boxes` prints immutable arena geometry without a renderer. `static_boxes`
exposes the same data to checks. Each entry has centre, half extents, colour,
rotation, emissive strength, and visual-only flag.

`scenarios/box-plan.json` uses `renderer_debug.clip_height` to hide upper
geometry for a plan view.

## Suites

Manifests live in `suites/`: `fast`, `lighting`, `renderer`, `offscreen`, and
`ui`. An entry is a scenario name or an object with `scenario`, optional
`label`, `size`, `params`, and `no_render`.

```sh
./bin/harbagsa-agent suite renderer
./bin/harbagsa-agent suite renderer --list
./bin/harbagsa-agent suite lighting --only light-move
make validate-offscreen
```

The exit code is the highest entry code. `--fail-fast` stops at the first
failure. `--only` and `--skip` accept names and comma lists. `--timeout` applies
to each entry. `suite.json` holds every row and wall time.

## Performance

A `perf` command measures frames and can write one trace. `frames` defaults to
120, `warmup` to 60, and `prime` to 2 seconds. `prime: 0` disables the time loop.
Offscreen measures throughput. `--present` measures pacing.

GPU passes are cluster, depth, scene, TAA, and overlay. The report carries
`p50`, `p95`, and `mean` for each CPU phase and GPU pass. Perf data is wall-clock
data and is not deterministic.

Use `scenarios/perf.json` for the default view, `scenarios/perf-lamps.json` for
direct lights, and `scenarios/perf-crates.json` for many objects.
`harbagsa-agent ab` compares two builds. `ab --visual` runs one scenario on both
and writes a compare panel.

## Determinism and screenshots

The offscreen target submits one frame at a time because it owns one colour
image and one readback buffer. TAA history affects exact pixels, so before and
after runs must use the same command sequence and history. Use
`scenarios/capture-free.json` to check a capture-free sequence.

Run the same scenario for before and after evidence:

```sh
./bin/harbagsa-agent run scenarios/smoke.json --out runs/change/before
./bin/harbagsa-agent run scenarios/smoke.json --out runs/change/after
./bin/harbagsa-agent compare runs/change/before runs/change/after --delta
```

Keep output under `runs/`. Never commit images.
