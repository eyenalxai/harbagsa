# harbagsa

A first-person game. The current slice is a walking demo.

## Language

**Player**:
The single first-person character.
_Avoid_: Avatar, pawn

**Character controller**:
The component that moves the player through the world and resolves walls and floors by collide-and-slide.
_Avoid_: Mover, motor

**Mover**:
Box3D's capsule query API. It gathers contact planes, sweeps the capsule, solves penetration, and clips velocity. The character controller uses the mover; the mover is not the controller.
_Avoid_: Character controller

**Capsule**:
The player's collision shape: a vertical cylinder with rounded ends. It sets the player's height and radius.
_Avoid_: Collider, cylinder

**Eye height**:
The camera height above the player's feet.
_Avoid_: Camera offset

**Grounded**:
The state where the character controller finds a floor under the player.
_Avoid_: On floor

**Air control**:
Steering while airborne. It changes direction up to the air cap; it never exceeds the cap.
_Avoid_: Air strafe

**Stance**:
The player's body height: Standing, Crouching, or Prone. It sets the capsule height, the eye height, and the movement speed.
_Avoid_: Posture, state

**Standing**:
The tallest stance. The capsule is 1.80 m high and the eye is 1.65 m above the feet.

**Crouching**:
The middle stance. The capsule is 1.20 m high and the eye is 1.05 m above the feet.

**Prone**:
The lowest stance. The capsule is 0.70 m high and the eye is 0.30 m above the feet. A prone player can crawl.

**Crawl**:
Movement while Prone. The crawl speed is 1.2 m/s along the walkable ground plane.
_Avoid_: Prone walk

**Gait**:
The ground movement mode: Walk or Sprint. Sprint applies only while Standing.
_Avoid_: Run mode

**Input mode**:
The way a key engages a setting: Hold while the key is down, or Toggle on each
press. The settings menu changes the sprint, crouch, and prone input modes.
_Avoid_: Key mode

**Sprint**:
The 8.0 m/s ground speed. The horizontal component is lower on a climb.
_Avoid_: Run

**Ground speed**:
The speed along the walkable ground plane. On a straight climb the horizontal speed is `ground speed * cos(slope)`.
_Avoid_: Surface speed

**Headroom**:
The clear space above the feet that a taller stance needs. The controller tests it before the capsule grows. A floor-level side obstacle does not reduce headroom; an overhead shape does.
_Avoid_: Ceiling check

**Dive**:
An 11.0 m/s lunge that starts in the air or from a sprint. The player lands Prone and slides.
_Avoid_: Lunge

**Slide**:
The locked-direction glide after a dive or a crouch slide. A dive slide ends Prone; a crouch slide ends Crouching.
_Avoid_: Skid

**Crouch slide**:
A 10.0 m/s slide that starts from Sprint. It ends Crouching.
_Avoid_: Power slide

**Mantle**:
A 0.25 s climb onto a ledge up to 1.5 m above the feet. A fresh jump press or a held jump with movement input starts it.
_Avoid_: Climb, vault

**Step-up**:
The automatic climb onto a near-vertical obstacle up to 0.35 m high while grounded. The top must be near flat; a walkable ramp is not a step-up.
_Avoid_: Autostep

**Ground snap**:
The downward correction that keeps a grounded player on a walkable surface within 0.30 m. A walkable slope can give a small positive vertical velocity; the surface clearance decides, not the sign of the velocity.
_Avoid_: Stick to ground

**Step smoothing**:
The short vertical camera lag after a step-up or step-down. It decays after the capsule settles and does not move the player.
_Avoid_: Camera lag

**Coyote time**:
The 0.10 s after leaving a walkable surface during which a jump still works.
_Avoid_: Grace period

**Jump buffer**:
The 0.12 s before landing during which a jump press is remembered.
_Avoid_: Input buffer

**Movement state**:
The exclusive action state: None, Diving, Sliding, or Mantling. Stance and gait are separate.
_Avoid_: Action state

**Arena**:
The fixed test level: a floor, walls, stairs, ramps, tunnels, mantle walls, a dive platform, a slide lane, and a few crates.
_Avoid_: Map, level

**Sun**:
The directional light that lights the arena and casts the sun shadows. Debug mode rotates it.
_Avoid_: Lamp, light source

**Sun angular diameter**:
The angle the sun disk subtends. It sets the penumbra width. The demo uses 3°; the real sun is about 0.53°. The wider disk makes the contact-hardening cue visible over the arena's short shadows.
_Avoid_: Light size

**Contact hardening**:
The shadow behavior where the penumbra grows with the distance between the blocker and the receiver. The shadow is sharp at contact and soft away from it.
_Avoid_: Soft shadow falloff

**Penumbra**:
The partly lit band between the umbra and the fully lit area. Its width grows with the blocker distance and the sun angular diameter.
_Avoid_: Soft edge, blur

**Top-level acceleration structure (TLAS)**:
The acceleration structure that holds the box instances for ray queries. The renderer rebuilds it each frame from the box transforms.
_Avoid_: Scene BVH

**Bottom-level acceleration structure (BLAS)**:
The acceleration structure for the unit cube mesh. Every TLAS instance shares it.
_Avoid_: Mesh BVH

**Ray query**:
A shader ray test against an acceleration structure. The sun shadow traces one ray per sun sample and counts the unblocked rays.
_Avoid_: Ray trace, RTX

**Shadow ray**:
A ray from a surface point toward a sample point on the sun. A hit means the sun sample is blocked.
_Avoid_: Light ray

**Crate**:
A dynamic box that the player can push.
_Avoid_: Prop, box

**Slide lane**:
The marked arena strip for crouch slides.
_Avoid_: Runway

**Mantle wall**:
The arena wall with a top at mantle height.
_Avoid_: Ledge

**Dive platform**:
The 2.5 m arena platform that starts dives.
_Avoid_: Tower

**Spawn**:
The point where the player starts and returns after a reset.
_Avoid_: Start, origin

**Simulation**:
The headless fixed-step update that owns the world, the player state, and the
settings.
_Avoid_: Game loop, engine

**Input snapshot**:
One frame of player intent: movement axes, sprint, crouch, prone, jump, and reset. Look is a separate frame call.
_Avoid_: Input state, controls

**Settings**:
The runtime window and input-mode choices: window mode, display, resolution,
and the sprint, crouch, and prone input modes. A new simulation starts Borderless
on display 0; the stored Windowed size is 1280x720, with sprint Hold, crouch
Toggle, and prone Toggle. A player reset keeps the current settings.
_Avoid_: Options, preferences

**Window mode**:
Borderless fills the selected display at its desktop size. Windowed requests a
fixed-size window at the selected resolution. The settings menu changes it. A
new simulation starts Borderless.
_Avoid_: Fullscreen mode, display mode

**Display**:
A connected output that shows the game. The settings menu chooses the display;
the game starts on the display where the window opened. Borderless fills it and
uses its desktop size. Windowed uses its resolution list, but on Wayland the
compositor decides where the window sits.
_Avoid_: Monitor, screen

**Resolution**:
The window size in Windowed mode, or the display's desktop size in Borderless
mode. The list comes from the selected display.
_Avoid_: Window size, video mode

**Render snapshot**:
The interpolatable view of the player after a simulation step.
_Avoid_: Frame state, view state

**Harness**:
The `harbagsa-agent` program that drives the simulation, runs checks, and writes
screenshots without the game loop.
_Avoid_: Bot, driver

**Scenario**:
A JSON document that compiles to one command list for the harness.
_Avoid_: Script, test case

**Capture**:
One rendered frame written as a PNG by the harness.
_Avoid_: Shot

**Capture target**:
The image a capture reads: the final color, the velocity target, the history, the depth buffer, or the scene color.
_Avoid_: Render layer

**Capture format**:
The output a capture writes: PNG for color, `float` for RGBA f32 values, `raw` for the stored texel bytes, or `stats` for the numeric summary.
_Avoid_: Export mode

**Capture statistics**:
The per-channel minimum, maximum, and mean of a capture, plus the median screen motion in texels for a velocity capture over covered pixels.
_Avoid_: Image metrics

**Analysis report**:
The `analysis.json` file from a run with color captures. It holds the capture window, the per-pair deltas, the summary, the dominant period, the worst unstable pixels' series, and the optional map paths.
_Avoid_: Diff report

**Capture check window**:
The slice of captures a check aggregates, `{"start": S, "count": N}`. Warmup is the shorthand for skipping the first N captures.
_Avoid_: Range

**Dominant period**:
The smallest lag within 10% of the strongest autocorrelation of the per-pair mean delta. A static TAA scene reports its jitter period.
_Avoid_: Frequency

**Worst unstable pixels**:
The eight pixels with the highest variance over the analysis window, with their per-frame mean channel value.
_Avoid_: Hot pixels

**Session**:
The live harness process that reads one JSON command per line and writes one
JSON reply per line.
_Avoid_: Daemon, server

**Offscreen target**:
The render target with a color image, a depth image, and a readback buffer, but
no surface or swapchain.
_Avoid_: Headless framebuffer

**Frame in flight**:
The number of submitted frames the CPU may record before the GPU completes one.
The swapchain target keeps two. The offscreen target keeps one, because it owns
a single color image and a single readback buffer.
_Avoid_: Queue depth

**Swapchain target**:
The render target that acquires and presents swapchain images for the window.
_Avoid_: Window target

**Cursor capture**:
The state where the mouse controls the camera and the pointer is hidden. The
settings menu releases the capture while it is open.
_Avoid_: Mouse lock

**Debug draw**:
The line pass that shows the physics world: shape bounds and contacts.
_Avoid_: Debug view, wireframe

**Overlay**:
The screen-space pass that draws the debug draw and the HUD over the scene. It does not write depth.
_Avoid_: UI layer

**Scene pass**:
The pair of scopes that draw the scene boxes into the depth, color, and velocity
targets: the depth prepass, then the lit pass.
_Avoid_: Main pass

**Depth prepass**:
The depth-only scope of the scene pass. It writes the nearest box surface before
the lit pass, so the sun rays run for the surface that reaches the frame.
_Avoid_: Z prepass

**Lit pass**:
The color scope of the scene pass. It loads the depth the prepass wrote and
shades the boxes, including the sun shadows.
_Avoid_: Main pass, color pass

**Backface culling**:
Dropping triangles whose winding faces away from the camera. The scene pass
culls back faces because every box is closed.
_Avoid_: Face culling

**Overdraw**:
Fragment work for a pixel that a nearer or later box covers again. The depth
prepass removes it from the scene pass.
_Avoid_: Overdrawing

**Render scope**:
One `vkCmdBeginRendering` to `vkCmdEndRendering` block. The scene pass uses one
for the depth prepass and one for the lit pass.
_Avoid_: Render pass (that word belongs to the Vulkan object)

**HUD**:
The 2D part of the overlay: crosshair and player state. It does not show the
control list.
_Avoid_: UI

**Settings menu**:
The paused overlay opened with `Esc`. It lists the active control set and changes
the window mode, display, resolution, and three input modes. The harness opens
it with the `menu` command and reports `settings.*` and `menu.*` in the state.
_Avoid_: Options screen, pause menu

**UI theme**:
The tokens the 2D layer draws with: colour, type, spacing, and the hairline
width. Built once per frame from the render height. `src/renderer/ui_theme.odin`
is the only place a colour or a size is written.
_Avoid_: Style sheet, skin

**Density**:
The type and spacing scale factor, `clamp(render height / 720, 1, 2)`. A 720p
target gets 1, a 1080p target 1.5, a 1440p target 2.
_Avoid_: DPI scale, zoom

**Type scale**:
The five type roles the overlay uses: title, body, label, detail, and section
header. Each role fixes an em size, leading, weight, and tracking. A size is the
em in device pixels, so a 15 px role draws a 15 px em. See `docs/ui/type.md`.
_Avoid_: Font sizes, text styles

**Coverage atlas**:
The one texture that holds every glyph as the fraction of each pixel the glyph
covers, rasterized at the device pixel size from the three subset Noto faces. It
holds one layer per face and pixel size the theme can draw, and it is repacked
when the density changes.
_Avoid_: SDF atlas, font texture, bitmap font, glyph sheet

**Sub-pixel phase**:
One of four horizontal offsets a glyph is rasterized at, so text placed on a
fraction of a pixel still lands on the pixel grid. The glyph keeps its fractional
advance; the phase absorbs the fraction.
_Avoid_: Sub-pixel offset, hinting

**Glyph**:
One drawable letter in the coverage atlas: a uv rectangle per sub-pixel phase, an
offset from the pen, and an advance. The HUD never draws a character directly; it
draws glyphs.
_Avoid_: Character, letter

**Row**:
One line of the overlay: a kind, a label, a value, and whether the value is
numeric. The game fills rows; the renderer lays them out. The kind set is closed:
setting, action, metric, detail, header, divider, spacer.
_Avoid_: Line, item, entry

**Value column**:
The measured x where row values start, or end when they are right-aligned. It is
the widest label plus one gutter, so every value in a panel shares one edge.
_Avoid_: Column, tab stop

**Hint legend**:
The control list inside the settings menu, drawn as a grid of keyboard keys and
their actions. Not a list of rows: it is documentation, so it must not look
selectable.
_Avoid_: Control list, key list

**Selection band**:
The two signals that mark the selected menu row: the raised surface and the
accent bar on the leading edge. Neither alone is enough.
_Avoid_: Highlight, hover, cursor

**Pause**:
The state while the settings menu is open. The simulation and debug camera do
not update.
_Avoid_: Freeze

**Temporal anti-aliasing (TAA)**:
The render path that jitters the camera and averages frames through a history buffer to smooth edges.
_Avoid_: Temporal filtering, accumulation

**Jitter**:
The subpixel camera offset applied each frame for TAA.
_Avoid_: Shake, offset

**History**:
The previous resolved frame, with linear color, view depth, and sample count, that TAA blends into the current frame.
_Avoid_: Accumulation buffer, cache

**Sample count**:
The number of frames accumulated into a history pixel. The resolve weights a new sample by one over the count plus one, and stops at 512.
_Avoid_: Frame counter, age

**Screen motion**:
The screen-space movement of a surface point from the previous frame to the
current frame, measured in unjittered UV space.
_Avoid_: Motion vector, optical flow

**Velocity target**:
The offscreen image that stores each pixel's previous-to-current screen motion and linear view depth.
_Avoid_: Motion buffer, motion vectors

**Resolve**:
The fullscreen pass that reprojects, tests the depth range, clamps, and averages the history into the current frame.
_Avoid_: Composite, merge

**Disocclusion**:
A pixel that was hidden by a surface and becomes visible after the camera or a surface moves.
_Avoid_: Reveal

**Depth range**:
The smallest and largest current view depth in a pixel's 3x3 neighborhood. The resolve accepts a history depth inside the range; a disocclusion falls outside it.
_Avoid_: Depth bounds, depth span

**History reset**:
The state where TAA ignores the previous history and starts a new accumulation.
_Avoid_: Clear, flush

**Convergence**:
The frames after a history reset while the sample count grows from 1 to 512. The first frames change the image quickly; later frames add small corrections.
_Avoid_: Warmup

**Renderer state**:
The harness state block that describes the last rendered frame: frame count, TAA state, jitter index, history validity, convergence frames, history read index and weight, reset count and reason, and shadow phase.
_Avoid_: Render stats, GPU state

**Render digest**:
The FNV-1a hash of the effective render inputs: camera, sun, boxes, jitter, shadow phase, and view flags. It is separate from the simulation digest.
_Avoid_: Frame hash, image hash

**History reset reason**:
The cause recorded at each TAA history reset: create, extent, toggle, teleport, scene change, debug override, player reset, or scene reset.
_Avoid_: Reset flag

**Renderer debug override**:
A gated change to a TAA input for diagnosis: TAA, jitter, history weight, clamp, depth trust, or shadow phase. Every change resets history.
_Avoid_: Debug flag

**Debug override gate**:
The `ENABLE_RENDERER_DEBUG` build define or the `--debug-renderer` flag that lets a run use renderer debug overrides. A release build without either rejects the command.
_Avoid_: Debug mode (that word belongs to `F2`)

**View flags**:
The toggles that change the overlay: HUD, menu, debug draw, capture hint, and perf. The render digest covers them because they change the image.
_Avoid_: Draw flags

**TAA toggle**:
The `F3` control that enables or disables temporal anti-aliasing.
_Avoid_: AA switch

**Debug mode**:
The `F2` mode where the player becomes a free-fly camera and can edit crates and the sun.
_Avoid_: Edit mode, sandbox

**Free-fly camera**:
The debug mode camera that ignores gravity and collision.
_Avoid_: Noclip, spectator

**Selection**:
The crate or the sun that debug mode acts on.
_Avoid_: Focus, target

**Scene reset**:
The `Shift+R` action that restores the starting crates, the sun, and the player.
_Avoid_: Reload, wipe

**Frame interval**:
The wall-clock time between two consecutive iterations of the game loop. With
the swapchain in FIFO it follows the display refresh, not the GPU cost.
_Avoid_: Frametime, frame time, delta

**CPU frame time**:
The wall-clock time the CPU spends in one iteration of the game loop, from frame
start to present.
_Avoid_: Main thread time

**CPU mark**:
A named instant in the game loop where the CPU reads the monotonic clock. The
difference between two neighbouring marks is one CPU phase duration.
_Avoid_: Checkpoint, sample point

**GPU pass time**:
The elapsed GPU clock between the timestamps around one renderer pass. It is the
pass's own cost, not the present interval.
_Avoid_: Render time, draw time

**Perf sample**:
One frame of performance data: the frame interval, the CPU phase durations, and
the GPU pass times.
_Avoid_: Frame stats, metrics

**Perf ring**:
The fixed-size buffer of the most recent perf samples that the live overlay and
the aggregate stats read.
_Avoid_: History buffer, window

**Perf overlay**:
The on-screen lines toggled with `F4` that show the live frame interval, the
CPU frame time, and the GPU pass times.
_Avoid_: FPS counter, stats overlay

**Perf run**:
A harness run that measures frames instead of checking simulation state. It reads
the wall clock, so its numbers are not deterministic.
_Avoid_: Benchmark, stress test

**Perf report**:
The `perf` object in a harness reply and in `report.json` that holds the
percentiles and per-pass means of a perf run.
_Avoid_: Benchmark result, profile

**Perf trace**:
The opt-in per-frame file from a perf run. It holds one JSON object per perf
sample.
_Avoid_: Log, dump

**Perf warmup**:
The frames a perf run measures but does not count, so shader and swapchain
warmup does not pollute the numbers. One priming frame always runs before it.
_Avoid_: Warmup (that word belongs to convergence)

**Spike**:
A frame interval above 1.5 times the median interval of the measured window.
_Avoid_: Hitch, stutter
