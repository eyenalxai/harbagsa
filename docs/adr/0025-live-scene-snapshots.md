# A live view writes one scene snapshot

> Superseded in part by ADR 0043: the scene player block reports body and camera
> yaw plus planted feet, not a stance, eye height, or step smoothing.

`F5` in the game writes a normal scenario with one `scene` command. The command
carries the exact camera, placed objects, settings, display list, and view
flags. `record` starts with the same command, so a recording and a keyed repro
share one writer and one load path.

## Why

- A renderer investigation spent most of its time guessing the view. The
  harness measured each candidate well, but nothing tied a candidate to the
  screen the investigator saw.
- `record` is an action recorder. It starts from `reset` and records what the
  operator sends. It cannot see a live game view, and a placed object edited
  before recording was reduced to the commands that made it.
- A sequence of existing commands cannot express exact object rotation, a lamp's
  live light values, or the settings block. A single scene value can.
- The key must not become a second control channel. A file write keeps the
  agent as the only scenario runner, so the game gains no socket and no server.

## Decisions

- **One `scene` command.** It applies a camera, object list, settings,
  display list, and view flags. A block is optional, so a hand-written scenario
  can set only what it needs.
- **The serializer lives below both binaries.** `src/frame/scene.odin` owns the
  scene type, the live capture, the JSON text, and the destroy path. The game
  and the harness call it. There is no second schema.
- **The key writes a file.** `F5` writes `runs/repro/repro-<unix>.json` and logs
  the absolute path. The file is a scenario; the next step is `run`.
- **The load is a state load, not an edit intent.** Objects go through
  `simulation_apply_snapshot`, the same path as undo and redo. The scene does not
  call `edit_apply` for every object.
- **`record` seeds the same scene.** A recording starts with `reset`, one
  `scene`, and the current input. The scene is absolute, so the reset is only a
  clean baseline.
- **The camera is exact.** A player scene stores the feet position, yaw, pitch,
  and stance, and sets the eye height from the stance. A debug scene stores the
  debug camera. An override scene stores the eye directly.
- **The renderer debug block is one patch.** `renderer.Renderer_Debug_Patch` is
  the JSON shape, the command patch, and the scene snapshot. A snapshot writes
  every effective field, so a `repro` restores the override exactly; a command
  may omit a field and keep the live value.

## Consequences

- A keyed repro replays the image with no socket, cursor, or compositor.
- Object velocity, spawn animation, TAA history, and the transient editor
  palette are not captured. A settled scene is the contract; motion still comes
  from `record`.
- The scene JSON is larger than a few commands. That is the price of exactness.
- A scene load closes the settings menu, because a step is illegal while the
  menu is open.
