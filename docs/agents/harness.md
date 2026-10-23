# Agent harness

`bin/harbagsa-agent` drives the simulation, runs checks, and writes exact
screenshots. It needs no window, compositor, cursor capture, or `grim`.

The user-facing command reference is `README.md` under **Agent harness**. This
page is the short operational guide for agents.

## First move

```sh
tools/make.sh build
./bin/harbagsa-agent run scenarios/smoke.json
```

Read `runs/smoke/report.json`. Use the absolute paths in `screenshots`. Exit
code 0 means every check passed.

Use `tools/make.sh` when another agent may build in the same checkout. It
serializes Make with `flock`.

## What one run writes

`runs/<scenario-stem>/`

- `report.json`: `ok`, `exit_code`, `frame`, `state`, `screenshots`, `checks`,
  `failures`, `digest`, and `error`.
- `state.json`: the final state alone.
- `frames/frame_NNNN.png`: zero-padded captures.
- `run.log`: log lines from the renderer, the session, and the runner.

Standard output is one JSON summary. Standard error holds logs.

Exit codes:

- `0`: pass.
- `1`: a check or an invariant failed.
- `2`: bad arguments or a bad scenario.
- `3`: render/init or file I/O failed.

## Scenario format

```json
{
  "view": {"hud": false, "debug": false, "hint": false},
  "steps": [
    {"frames": 90, "forward": 1, "look": [220, 0]},
    {"frames": 1, "jump": true},
    {"frames": 30, "forward": 1}
  ],
  "capture": [0, 90, 121],
  "checks": [
    {"field": "crates.0.position.z", "op": "lt", "value": 7.5}
  ]
}
```

Rules:

- One step is one `SIMULATION_STEP` (1/60 s). The harness does not use wall-clock
  time.
- `look` applies once before the block.
- `forward`, `right`, and `jump` persist. `jump` is an edge on the first frame of
  its block.
- A capture frame is a zero-based frame number. The final frame is captured by
  default. `"capture": []` opts out of rendering for that scenario.
- A check uses the `state.json` shape. Operators: `eq`, `ne`, `lt`, `le`, `gt`,
  `ge`.
- A `commands` array runs verbatim. It is the form that `record` writes. It does
  not add a default capture.

## Commands

- `{"cmd": "reset"}`
- `{"cmd": "look", "dx": 220, "dy": 0}`
- `{"cmd": "face", "yaw": 0, "pitch": 0}`
- `{"cmd": "input", "forward": 1, "right": 0, "jump": false}`
- `{"cmd": "step", "frames": 60}`
- `{"cmd": "state"}`
- `{"cmd": "capture", "name": "shot", "frame": 90, "alpha": 1.0}`
- `{"cmd": "camera", "position": [0, 2, 12], "yaw": 0, "pitch": 0}`
- `{"cmd": "camera", "clear": true}`
- `{"cmd": "view", "hud": true, "debug": false, "hint": false}`
- `{"cmd": "check", "field": "player.position.y", "op": "gt", "value": 0}`
- `{"cmd": "record", "path": "scenarios/walk.json"}`
- `{"cmd": "record"}`
- `{"cmd": "replay", "path": "scenarios/walk.json"}`
- `{"cmd": "quit"}`

A past capture frame is an error. A future capture frame queues. Unknown keys,
wrong types, and out-of-range values are per-command errors; the session stays
usable.

## Live session

```sh
printf '%s\n' \
  '{"cmd": "step", "frames": 60}' \
  '{"cmd": "state"}' \
  '{"cmd": "quit"}' |
  ./bin/harbagsa-agent session

./bin/harbagsa-agent session --socket /tmp/harbagsa.sock
socat - UNIX-CONNECT:/tmp/harbagsa.sock
```

One JSON command per line. One JSON reply per line. The socket mode prints one
ready line on standard output. Capture files go to `runs/session/frames/` unless
`--out` selects another directory.

`record PATH` starts recording. A second `record` with no path stops and writes
the scenario. Recording starts with a fresh reset, so send the actions after the
start command if you want them in the scenario. `replay PATH` resets and runs the
scenario.

## Screenshots

- Headless runs use the offscreen target. The default is 1280x720 with the HUD,
  debug draw, and capture hint off.
- `--present` opens the real window and captures the swapchain image before
  present. The compositor controls the window size.
- TAA history affects exact pixels. The first frame matches exactly. Later frames
  match when both runs share the same history. See the README note.
- `--no-render` and capture-free scenarios never create a Vulkan device.

Use `capture` or `--present`. Do not use `grim` for automated screenshots.

## Determinism

- Fixed 60 Hz. Never sleep or use a wall-clock delta.
- `reset` creates a fresh `Simulation`. Crates return to spawn.
- `look` uses the game sensitivity and pitch clamp. `face` sets yaw and pitch
  directly.
- Capture alpha defaults to 1.0 (post-step), so a capture matches `state` at the
  same frame.
- The digest is FNV-1a over frame, player, and crate state. Use it in reports and
  regression checks.

## Where the code lives

- `src/harness/`: CLI, scenario compiler, commands, session, runner, socket, PNG.
- `src/frame/`: shared scene assembly and draw for the game and the harness.
- `src/renderer/`: `Target` and `Platform` ports, swapchain/offscreen targets,
  TAA, capture readback.
- `src/platform/`: SDL and headless adapters.
- `tests/harness/`, `tests/frame/`, `tests/renderer/target.odin`.
- `scenarios/smoke.json`.

## Adding a command

Change:

- `Command_Kind` and `Command` in `src/harness/command.odin`.
- `command_name` and `command_destroy`.
- `command_parse` and a parser in `src/harness/command_parsers.odin`.
- `session_execute` and `session_record_command` in
  `src/harness/session_commands.odin`.
- README and, for a new domain word, `GLOSSARY.md`.
- A test in `tests/harness/`.

## Checks

```sh
tools/make.sh check
tools/make.sh test
tools/make.sh build
```

`make validate` builds the agent with validation enabled and runs
`scenarios/smoke.json` offscreen, then with `--present` when a display is
available. `make validate-demo` runs the game with validation enabled.

## Pitfalls

- Do not add a control socket to the game. The agent is a separate binary.
- Do not duplicate frame assembly. The game and the harness call `src/frame`.
- Keep the offscreen target lazy. Simulation-only runs must not create a Vulkan
  device.
- Keep `renderer.Target` and `renderer.Platform` as the seams. The renderer core
  must not import `src:platform`.
