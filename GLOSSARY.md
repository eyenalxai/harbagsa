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

**Settle time**:
The time a smoothed value takes to close 99% of the gap to its target. The eye
height settles in 0.184 s and the step offset in 0.256 s, both continuous
values from the exponential rate constants. At 60 Hz the next whole step lands
at 0.20 s and 0.27 s.
_Avoid_: Smoothing time, decay time

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

**World palette**:
The scene colours, authored as linear RGBA floats because the renderer shades in
linear space. The 2D layer authors sRGB hex instead; a value does not move
between the two tables.
_Avoid_: Scene colours, 3D palette

**Sun**:
The directional light that lights the arena and casts the sun shadows. Debug mode rotates it.
_Avoid_: Light source

**Point light**:
A light with a position, colour, intensity, and range. The renderer holds up to 8 per frame, and each costs one hard shadow ray per fragment. A lamp prefab owns one.
_Avoid_: Lamp (the prefab), bulb

**Emissive box**:
A box whose colour adds to its shaded colour after the sun and point lights. It carries an emissive strength in the box data. Lamps are emissive so they glow even when their light is not in the active eight.
_Avoid_: Glow shader, unlit material

**Light mask**:
The TLAS instance mask that decides which acceleration-structure ray queries see a box. Normal boxes use `0xFF`, lamps use `0x01`, the point-light shadow ray tests `0x02`, and the sun ray tests `0xFF`.
_Avoid_: Layer mask, collision mask

**Synthetic light**:
A fixed test light that the renderer debug override injects, so a perf run can measure the light budget before the game has lamp prefabs.
_Avoid_: Fake light

**Sun direction**:
The unit vector from a point in the world toward the sun. The sky angles describe
it: azimuth from `+z` toward `+x`, and elevation above the horizon.
_Avoid_: Sun vector, light vector

**Light direction**:
The direction the sun's light travels. It is the opposite of the sun direction.
The renderer shades with it.
_Avoid_: Sun direction

**Sun angular diameter**:
The angle the sun disk subtends. It sets the penumbra width and it is the same
for every shadow. The demo uses the real 0.53°. A wider disk softens every
shadow by the same factor, and a wall shadow smears when the sun sits low.
_Avoid_: Light size

**Contact hardening**:
The shadow behavior where the penumbra grows with the distance between the blocker and the receiver. The shadow is sharp at contact and soft away from it.
_Avoid_: Soft shadow falloff

**Penumbra**:
The partly lit band between the umbra and the fully lit area. Its width grows with the blocker distance and the sun angular diameter.
_Avoid_: Soft edge, blur

**Ambient occlusion**:
The cosine-weighted fraction of the hemisphere at a surface point that visible geometry does not block. It scales ambient light. It is not global illumination, because it adds no bounce light.
_Avoid_: SSAO (that is one estimator), GI (that adds bounce light)

**Sky**:
The analytic gradient that fills the background: a horizon-to-zenith ramp, a darker ground color below the horizon, and a sun disk with a glow. It draws after the lit pass and shades only the pixels that no box covers.
_Avoid_: Skybox, cubemap, backdrop

**Sky ambient**:
A two-colour hemisphere ramp on the surface normal, scaled to the scene exposure. The lit pass uses it as the ambient term, and ambient occlusion scales it. It is not the integral of the visible sky.
_Avoid_: IBL, environment light, ambient probe

**AO radius**:
The maximum distance an ambient occlusion ray travels: 1.5 m. A surface beyond that distance does not count as an occluder.
_Avoid_: AO distance, occlusion range

**Top-level acceleration structure (TLAS)**:
The acceleration structure that holds the box instances for ray queries. The renderer rebuilds it each frame from the box transforms.
_Avoid_: Scene BVH

**Bottom-level acceleration structure (BLAS)**:
The acceleration structure for the unit cube mesh. Every TLAS instance shares it.
_Avoid_: Mesh BVH

**Ray query**:
A shader ray test against an acceleration structure. The sun shadow traces one ray per sun sample and counts the unblocked rays; each point light traces one ray.
_Avoid_: Ray trace, RTX

**Shadow ray**:
A ray from a surface point toward a sun sample or a point light. A hit means the sample or light is blocked.
_Avoid_: Light ray

**Crate**:
The 1 m dynamic box prefab. The three starting objects use it.
_Avoid_: Prop, box

**Placed object**:
One prefab instance in the simulation: a stable id, a prefab, a body mode, a
physics body, and a spawn time. Debug mode edits placed objects; the static
arena is separate.
_Avoid_: Prop, entity, crate

**Prefab**:
A named box archetype in the fixed catalog: half extents, colour, default body
mode, and an optional base pitch. The ramp carries a 20 degree base pitch.
_Avoid_: Template, class, prototype

**Body mode**:
Static or dynamic. A static placed object collides and never moves. A dynamic
placed object uses the prefab density and can be pushed.
_Avoid_: Body type

**Object id**:
The stable number that addresses a placed object through the game API and the
harness. The list index stays internal.
_Avoid_: Handle, slot

**Object palette**:
The debug-mode prefab chooser. It holds the open flag, the selected catalog
index, and the body mode for the next placement. The bottom dock draws twelve
cells, an isometric preview, and the key hints.
_Avoid_: Toolbar, inventory

**Placement**:
The armed debug tool state: the prefab, the surface anchor, the height offset,
the yaw, and the grid snap flag. Picking a palette card arms it; placing keeps
it armed.
_Avoid_: Spawn mode, build mode

**Ghost**:
The wireframe preview of the armed placement: the oriented box, its footprint on
the surface, and the height guide. It is a planning aid, not a collision test.
_Avoid_: Preview, hologram

**Grid snap**:
The optional 0.25 m X/Z rounding of the ghost's bottom anchor. It is off by
default.
_Avoid_: Grid, quantization

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

**Build revision**:
The short HEAD and dirty flag the agent build injects into `setup`. A direct
`odin run` or a test build reports `unknown` and `false`.
_Avoid_: Version, commit

**Offscreen validation**:
The `make validate-offscreen` target. It builds the validation agent and runs the
smoke and UI scenarios without a window.
_Avoid_: Headless validate

**Scenario**:
A JSON document with one `commands` list for the harness. It runs verbatim, and
only a `capture` command captures.
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

**Overlay budget**:
The fixed cost of the 2D layer: one coverage atlas, 24576 HUD vertices, and 32768
debug vertices. A change that needs more is a design change.
_Avoid_: UI budget, draw budget

**Scene pass**:
The scopes that draw the scene into the depth, color, and velocity targets: the
depth prepass, the lit pass, and the sky pass. The perf report times the depth
prepass, the lit pass, and the sky pass as separate GPU passes.
_Avoid_: Main pass

**Depth prepass**:
The depth-only scope of the scene pass. It writes the nearest box surface before
the lit pass, so the sun rays run for the surface that reaches the frame. It is
its own GPU pass in the perf report.
_Avoid_: Z prepass

**Lit pass**:
The color scope of the scene pass. It loads the depth the prepass wrote and
shades the boxes, including the sun and point-light shadows and the emissive
term.
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
for the depth prepass, one for the lit pass, and one for the sky pass.
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

**OKLCH**:
A perceptual colour space with lightness, chroma, and hue. The neutral tokens
are authored in it so one hue can be held across the ramp.
_Avoid_: HSL, HSV

**Neutral ramp**:
The six cool ink and surface tokens: `text_primary`, `text_secondary`,
`text_tertiary`, `surface_hud`, `surface_menu`, and `surface_raised`. They are
authored at OKLCH hue 253; the 8-bit hex leaves a measured spread of 7.8
degrees.
_Avoid_: Grey scale, grey ramp

**WCAG 2**:
The W3C contrast standard for text and non-text elements. The 2D layer uses its
4.5:1 body-text floor as the gate.
_Avoid_: Contrast score

**APCA**:
The perceptual contrast algorithm built for WCAG 3. It reports Lc and accounts
for font size and weight. The project records its scores as a reference, not a
gate.
_Avoid_: Contrast ratio

**Type scale**:
The five type roles the overlay uses: title, body, label, detail, and section
header. Each role fixes an em size, leading, and tracking, and derives its weight
from the base axis position. A size is the em in device pixels, so a 15 px role
draws a 15 px em. See `docs/ui/type.md`.
_Avoid_: Font sizes, text styles

**Weight axis**:
The `wght` variation coordinate of a variable face. Roboto Condensed runs from
100 to 900; Roboto Mono runs from 100 to 700. The base weight is a settings value,
not a state. Body and detail use the base, title and labels use base + 100, and
mono clamps at 700.
_Avoid_: Font weight, boldness, thickness

**Named instance**:
A labelled stop on a weight axis: Thin 100, ExtraLight 200, Light 300, Regular
400, Medium 500, SemiBold 600, Bold 700, ExtraBold 800, Black 900. The slider
marks all nine, but it can land on any whole unit between them.
_Avoid_: Variant, preset, style

**Shaped run**:
The glyph IDs, x offsets, and advances HarfBuzz returns for one string. Measuring
and drawing walk the same run, so they cannot drift apart. The atlas is keyed by
glyph ID, not by character.
_Avoid_: Text layout, glyph list

**Slider row**:
A two-line settings row for one continuous value. Line one holds the label and the
number; line two holds a full-width track with named-instance ticks. It is
selectable, and a drag maps the cursor onto the track.
_Avoid_: Seek bar, range, gauge

**Coverage atlas**:
The one texture that holds every glyph as the fraction of each pixel the glyph
covers, rasterized at the device pixel size from the two subset Roboto variable
faces. A layer is keyed by face, weight, and pixel size. The first build is
synchronous at startup; later weight or density changes repack on a worker.
_Avoid_: SDF atlas, font texture, bitmap font, glyph sheet

**Applied atlas weight**:
The weight the active coverage atlas holds. The renderer reports it as
`renderer.atlas_weight`; `settings.type_weight` is only the request.
_Avoid_: Requested weight, font weight

**Sub-pixel phase**:
One of four horizontal offsets a glyph is rasterized at, so text placed on a
fraction of a pixel still lands on the pixel grid. The glyph keeps its fractional
advance; the phase absorbs the fraction.
_Avoid_: Sub-pixel offset, hinting

**Glyph**:
One drawable letter in the coverage atlas: a uv rectangle and an offset from the
pen for each sub-pixel phase. HarfBuzz supplies the advance at draw time. The HUD
never draws a character directly; it draws glyphs.
_Avoid_: Character, letter

**Row**:
One line of the overlay: a kind, a label, a value, whether the value is numeric,
and whether the value is blocked. A slider row also carries a ratio and a tick
count. The game fills rows; the renderer lays them out. The kind set is closed:
setting, action, metric, detail, slider, header, divider.
_Avoid_: Line, item, entry

**Blocked row**:
A settings row that cannot change in the current state. It stays selectable and
keeps its selection band; only its value moves to `text_secondary`. Display and
Resolution can be blocked. The Type weight row is not blocked at an axis end,
because one direction still moves.
_Avoid_: Disabled row, greyed row

**Status note**:
The one-line reason under the settings panel after a blocked change. It holds
for two seconds of frame time, then the default note returns. A new blocked
press restarts the hold; a successful change clears it.
_Avoid_: Error message, toast, tooltip

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
accent bar on the leading edge. Neither alone is enough. It applies to a setting,
an action, or a slider row.
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
The harness state block that describes the last rendered frame: frame count, TAA state, jitter index, history validity, convergence frames, history read index and weight, reset count and reason, shadow phase, and active point-light count.
_Avoid_: Render stats, GPU state

**Render digest**:
The FNV-1a hash of the effective render inputs: camera, sun, boxes, box emissive strengths, point lights, jitter, shadow phase, and view flags. It is separate from the simulation digest.
_Avoid_: Frame hash, image hash

**History reset reason**:
The cause recorded at each TAA history reset: create, extent, toggle, teleport, scene change, debug override, player reset, or scene reset.
_Avoid_: Reset flag

**Renderer debug override**:
A gated change to a TAA or point-light input for diagnosis: TAA, jitter, history weight, clamp, depth trust, shadow phase, point-light shadows, or synthetic lights. Every change resets history.
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
The `F2` mode where the player becomes a free-fly camera and can edit placed
objects and the sun.
_Avoid_: Edit mode, sandbox

**Free-fly camera**:
The debug mode camera that ignores gravity and collision.
_Avoid_: Noclip, spectator

**Selection**:
The placed object or the sun that debug mode acts on.
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
The `perf` list in `report.json` and the `perf` object in a harness reply. Each
named report holds the interval distribution, the `p50`/`p95`/`mean` of every CPU
phase and GPU pass, and the prime fields. The session reply keeps the last one.
_Avoid_: Benchmark result, profile

**Perf trace**:
The opt-in per-frame file from a perf run. It holds one JSON object per perf
sample. A run holds one trace.
_Avoid_: Log, dump

**Perf warmup**:
The frames a perf run measures but does not count, so shader and swapchain
warmup does not pollute the numbers. The perf prime runs before it, and one
priming frame always runs first.
_Avoid_: Warmup (that word belongs to convergence)

**Perf prime**:
The wall-clock warm-up before the perf warmup frames. It lets the GPU clock and
the shader cache settle; its frames never enter the trace or the statistics.
_Avoid_: Warmup (see convergence and perf warmup)

**Spike**:
A frame interval above 1.5 times the median interval of the measured window.
_Avoid_: Hitch, stutter

## Harness measurement terms

### Banding
A run of identical 8-bit values along a gradient. **Avoid**: stepping, contouring.

### Dither
A fixed, per-pixel offset applied before an 8-bit quantization. The output
dither on the resolve breaks a band without entering the TAA history.
**Avoid**: noise, grain.

### Region
A rectangle of the source image that limits a capture's statistics or
histogram. **Avoid**: window, crop (a crop changes the written image).

### Crop
A scaled PNG written from a rectangle of a capture. The capture keeps its source
extent and reports the written size. **Avoid**: region, zoom.

### Profile
A line or mean span of a capture, decoded from sRGB to linear, that reports the
10%-90% crossing width. **Avoid**: scanline, slice.

### Histogram
Per-channel bin counts over a region. **Avoid**: distribution.

### Settle convergence
A settle that renders until the TAA sample count reaches the 512 cap.
**Avoid**: settle, warmup.

### Scenario extension
An `extends` path that merges a base scenario object with a child that wins.
**Avoid**: include, import.

### Run tag
A directory name appended to the run path so two runs coexist. **Avoid**:
label, suffix.

### Display list
The harness's scripted set of displays and modes. It replaces the compositor
snapshot for a scenario. **Avoid**: monitor list.
