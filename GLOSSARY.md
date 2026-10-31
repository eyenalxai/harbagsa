# harbagsa

A third-person game. The current slice is a spider movement demo.

## Language

**Player**:
The single third-person spider.
_Avoid_: Avatar, pawn

**Spider**:
The player creature: a cephalothorax, an abdomen, and eight legs. The body hangs
above the feet, and the legs plant on the floor.
_Avoid_: Character model, monster

**Character controller**:
The component that moves the player through the world and resolves walls and floors by collide-and-slide.
_Avoid_: Mover, motor

**Mover**:
Box3D's capsule query API. It gathers contact planes, sweeps the capsule, solves penetration, and clips velocity. The character controller uses the mover; the mover is not the controller.
_Avoid_: Character controller

**Capsule**:
The spider body's collision shape: a vertical cylinder with rounded ends. It is
0.84 m high and 0.42 m in radius. The legs are visual, so they do not widen the
collision shape.
_Avoid_: Collider, cylinder

**Leg**:
One two-bone chain from a hip to a foot, with a knee between them. The femur runs
from the hip to the knee; the tibia runs from the knee to the foot.
_Avoid_: Limb

**Hip**:
The leg's body-space anchor. Four hips sit on each side of the body, between the
cephalothorax and the abdomen.
_Avoid_: Shoulder, root

**Foot**:
The world point a leg ends at. A planted foot does not move.
_Avoid_: End effector, toe

**Knee**:
The joint between the femur and the tibia. The solver puts it above the body
line, so the leg folds the way an arachnid leg does.
_Avoid_: Elbow, joint

**Inverse kinematics**:
The solve that finds the knee for a hip and a foot. The game uses one analytic
two-bone solve per leg and clamps the foot inside the reach, so the chain never
straightens into a lock.
_Avoid_: IK rig, animation IK

**Reach**:
The longest hip-to-foot distance a leg may use: 94 percent of the femur plus the
tibia. A foot target past the reach is pulled toward the hip.
_Avoid_: Leg length, range

**Rest point**:
The body-space ground point a leg stands on when the body is still. It moves with
the body yaw.
_Avoid_: Home pose, default foot

**Planted**:
A foot that rests on the floor and holds its world position between steps.
_Avoid_: Locked, grounded

**Swing**:
The short arc from one foot position to the next. A swing lifts the foot and
returns it to the floor.
_Avoid_: Step animation, stride

**Step trigger**:
The 0.30 m drift from the rest point that starts a swing. A planted foot that
lags farther than this steps forward.
_Avoid_: Threshold, tolerance

**Gait group**:
One half of the alternating tetrapod. The front-left, rear-left, front-right,
and rear-right legs move together; the other four hold the floor.
_Avoid_: Leg set, phase

**Body yaw**:
The direction the spider faces. It turns toward the movement direction; the
camera yaw does not turn it.
_Avoid_: Heading, facing

**Orbit camera**:
The third-person camera that circles the body. The mouse sets its yaw and pitch.
_Avoid_: Follow camera, chase camera

**Camera pivot**:
The point the orbit camera looks along, 1.03 m above the feet. It follows the
interpolated body and the step-smoothing offset.
_Avoid_: Camera target, look-at

**Spring arm**:
The camera distance that a capsule cast shortens before the arm crosses a wall,
floor, or prop. The arm never leaves the cast's safe distance.
_Avoid_: Camera boom, collision camera

**Orbit yaw**:
The camera's horizontal angle. Movement input is relative to it.
_Avoid_: Look yaw

**Orbit pitch**:
The camera's vertical angle, clamped from -70 degrees (looking down) to +45
degrees (looking up). A new player starts at -15 degrees.
_Avoid_: Look pitch

**Grounded**:
The state where the character controller finds a floor under the player.
_Avoid_: On floor

**Air control**:
Steering while airborne. It changes direction up to the air cap; it never exceeds the cap.
_Avoid_: Air strafe

**Gait**:
The ground movement mode: Walk or Sprint.
_Avoid_: Run mode

**Input mode**:
The way a key engages a setting: Hold while the key is down, or Toggle on each
press. The settings menu changes the sprint input mode.
_Avoid_: Key mode

**Sprint**:
The 8.0 m/s ground speed. The horizontal component is lower on a climb.
_Avoid_: Run

**Ground speed**:
The speed along the walkable ground plane. On a straight climb the horizontal speed is `ground speed * cos(slope)`.
_Avoid_: Surface speed

**Step-up**:
The automatic climb onto a near-vertical obstacle up to 0.35 m high while grounded. The top must be near flat; a walkable ramp is not a step-up.
_Avoid_: Autostep

**Ground snap**:
The downward correction that keeps a grounded player on a walkable surface within 0.30 m. A walkable slope can give a small positive vertical velocity; the surface clearance decides, not the sign of the velocity.
_Avoid_: Stick to ground

**Step smoothing**:
The short vertical camera lag after a step-up or step-down. It decays after the capsule settles.
_Avoid_: Camera lag

**Settle time**:
The time a smoothed value takes to close 99% of the gap to its target. The step
offset settles in 0.256 s, a continuous value from the exponential rate constant.
At 60 Hz the next whole step lands at 0.27 s.
_Avoid_: Smoothing time, decay time

**Coyote time**:
The 0.10 s after leaving a walkable surface during which a jump still works.
_Avoid_: Grace period

**Jump buffer**:
The 0.12 s before landing during which a jump press is remembered.
_Avoid_: Input buffer

**Arena**:
The fixed demo level: a floor, walls, ceiling, stairs, ramps, tunnels, the tall
west walls, the high platform, a marked strip, and a few crates.
_Avoid_: Map, level

**World palette**:
The scene colours, authored as linear RGBA floats because the renderer shades in
linear space. The 2D layer authors sRGB hex instead; a value does not move
between the two tables.
_Avoid_: Scene colours, 3D palette

**Point light**:
A light with a position, colour, intensity, and range. The renderer holds every active point light in a growable buffer. The lit pass reads the current position, colour, intensity, and range each frame. A lamp prefab owns one; its lamp kind decides whether it contributes baked indirect.
_Avoid_: Lamp (the prefab), bulb

**Lamp kind**:
Static fixture or dynamic lamp. A static fixture uses a static body and bakes one diffuse bounce; a dynamic lamp uses a dynamic body and contributes direct light and hard shadows only. The kind is separate from the prefab and from an ordinary box body mode. Newly placed lamps default to dynamic; `K` toggles the kind and the body follows it.
_Avoid_: Light type, lamp mode

**Static fixture**:
A lamp whose kind is `Static_Fixture`. Its body is static, and the bake traces it as a static light. The three starting lamps are static fixtures.
_Avoid_: Baked lamp, fixed light

**Dynamic lamp**:
A lamp whose kind is `Dynamic_Lamp`. Its body is dynamic, and it contributes no indirect light. A newly placed lamp defaults to this kind.
_Avoid_: Moving fixture, dynamic fixture

**Darkness**:
The zero-light state. A surface with no direct point light, no baked indirect, and no emissive strength renders black. It is the intended default, not a missing light or a background.
_Avoid_: Ambient floor, fill light, black level

**Point-light shadow**:
The visibility term for one point light. The lit pass traces one hard ray from the surface to the lamp against the scene TLAS. A hit removes that lamp's contribution. Lamp instances are excluded so a lamp does not block its own light, and the ray stops one millimetre short of the light. The edge is hard because the light has no radius.
_Avoid_: Shadow map, soft shadow, baked shadow

**TLAS**:
The top-level acceleration structure. It holds one instance per current box and
points at the one cube BLAS. The renderer rebuilds it each frame while
point-light shadows are enabled. The bake builds its own static BVH; it never
reads the frame TLAS.
_Avoid_: Scene BVH, instance list

**Cluster**:
A cell of the camera frustum, 16 by 9 by 24 with logarithmic depth slices. A light belongs to a cluster when its range sphere overlaps the cell. The lit pass shades only the lights of the fragment's cluster.
_Avoid_: Tile, bin

**Clustered forward+**:
The forward lighting path that builds a light index list per cluster in a compute pass, then reads that list in the lit pass. It keeps the per-pixel light loop proportional to the lights that can reach the surface.
_Avoid_: Tiled forward, light grid

**Indirect light (GI)**:
Light that reaches a surface after one diffuse bounce from a static fixture or a static emissive box. Static boxes read it from the lightmap; dynamic boxes read it from the probe field. It is baked, not updated per frame. It is not a default fill: with no static fixture, it is zero.
_Avoid_: Ambient, global illumination cache

**Bake**:
The explicit CPU pass that traces the static indirect and writes the versioned artifact. Its inputs are the static boxes, active static fixtures, static emissive boxes, and quality. The frame never runs it.
_Avoid_: GI pass, probe pass

**Bake key**:
The FNV hash of the canonical static boxes, active static fixtures, quality, and tool version. The renderer recomputes it from the current static input; a mismatch is `stale`.
_Avoid_: Scene hash, light hash

**Bake status**:
The applied artifact state: `missing`, `stale`, `current`, or `failed`. A
missing or failed load binds placeholders and reports the reason; a failed
publish leaves the old artifact bound. It never falls back to black or to
another artifact.
_Avoid_: Bake state (use the status name), load flag

**Bake artifact**:
The versioned `.hbake` file that carries the lightmap atlas, face rects, slots,
probe atlases, probe states, quality, and stats. `make bake` writes
`build/bake/arena.hbake`; the harness can publish one at runtime. The measured
time lives in a `.time` sidecar so the artifact bytes stay deterministic.
_Avoid_: Bake file, lightmap file

**Lightmap**:
The one linear `1024²` `RGBA16F` atlas that holds one tile per static box face. It carries static indirect only; direct light and hard shadows stay real-time. It is lighting data, not a surface or material texture.
_Avoid_: Baked texture, GI map

**Lightmap denoise**:
The separable 3x3 binomial pass that the bake runs over one chart after the buried fill and before the gutter, with clamp-to-edge weights that sum to one. One chart is one planar face, so the pass cannot bleed across a surface and the gutter still isolates neighbouring charts. The texel seed follows the surface, not the atlas position.
_Avoid_: Blur, smoothing, post-process

**Probe**:
One sample point in the baked static probe field. The bake traces 1024 rays and stores an 8 x 8 octahedral irradiance and depth atlas.
_Avoid_: Light sample, photon

**Probe volume**:
The axis-aligned grid of probes. The default covers the arena at 1 m spacing: 40 x 5 x 40 probes. The 2 m quality fallback uses 20 x 3 x 20. A probe inside static geometry is invalid.
_Avoid_: GI grid, light grid

**Probe atlas**:
The irradiance and depth maps for one probe. Irradiance uses an 8 x 8 octahedral map with gamma encoding; depth stores the first and second moments. The lit pass samples the four probes of the containing tetrahedron.
_Avoid_: Irradiance map, probe texture

**Coverage fraction**:
The share of the sampled capture region that is exactly zero, at or below a black threshold, or at or above a lit threshold. A `coverage` block on a stats capture reports it as `capture.stats.coverage.zero_fraction`, `.black_fraction`, and `.lit_fraction`. A threshold is in the target's own values.
_Avoid_: Black ratio, lit ratio

**Lamp prefab**:
A prefab with an active point light and an emissive box. The catalog has the Lamp, the Light panel, and the Beacon. A lamp is placed like any other object and carries a lamp kind; a static fixture uses a static body, and a dynamic lamp uses a dynamic body.
_Avoid_: Light object, bulb

**Light budget**:
The set of active point lights. Every placed lamp with an active light is in the budget; the renderer no longer keeps a nearest subset. The inspector shows the active count against the lamp count.
_Avoid_: Light cap, light count (that is the reported number)

**Emissive box**:
A box whose colour adds to its shaded colour after the direct point lights. It carries an emissive strength in the box data. Lamps are emissive so they glow even when their light is inactive.
_Avoid_: Glow shader, unlit material

**Synthetic light**:
A generated light that the renderer debug override injects, so a perf run can
fill the frame with an arbitrary light count without placing lamps.
_Avoid_: Fake light

**Degree boundary**:
The scenario, `state.json`, and `report.json` express every angle in degrees.
Every angle key ends in `_deg`. The engine converts to radians at the edge.
_Avoid_: mixed angle units, implicit units

**Crate**:
The 1 m dynamic box prefab. Three crates and three static fixture lamps make up
the six starting objects.
_Avoid_: Prop, box

**Placed object**:
One prefab instance in the simulation: a stable id, a prefab, a body mode, a
physics body, and a spawn time. Debug mode edits placed objects; the static
arena is separate.
_Avoid_: Prop, entity, crate

**Prefab**:
A named box archetype in the fixed catalog: half extents, colour, default body
mode, an optional base pitch, and an optional point light. The ramp carries a
20 degree base pitch; the Lamp, Light panel, and Beacon carry a light.
_Avoid_: Template, class, prototype

**Body mode**:
Static or dynamic. A static placed object collides and never moves. A dynamic
placed object uses the prefab density and can be pushed. A lamp body follows its
kind: a static fixture is static, a dynamic lamp is dynamic. A body request that
would contradict the kind is refused.
_Avoid_: Body type

**Object id**:
The stable number that addresses a placed object through the game API and the
harness. The list index stays internal.
_Avoid_: Handle, slot

**Active tool**:
The one debug tool that owns the frame: the Object palette or the Placement
tool. `active_tool` reads it; `take_tool` cancels the other. Arming the Placement
tool closes the palette.
_Avoid_: Current mode, tool state

**Object palette**:
The debug-mode prefab chooser. It holds the open flag, the selected catalog
index, and the body and light settings for the next placement. The bottom dock
draws twelve cells, an isometric preview, and the key hints.
_Avoid_: Toolbar, inventory

**Placement**:
The armed debug tool state: the prefab, the surface anchor, the height offset,
the yaw, and the grid snap flag. Picking a palette card arms it; placing keeps
it armed.
_Avoid_: Spawn mode, build mode

**Editing action**:
One intent that the keyboard or the harness sends to the edit facade: palette,
placement, object, light, pointer, or cancel. One apply proc owns its rule.
_Avoid_: Edit command, tool call

**Edit result**:
The outcome of one editing action: applied, or a reason the action did not run.
_Avoid_: Error code, status

**Next placement light**:
The light the next placement uses. The open palette or the armed tool holds the
tuned values; otherwise the prefab default applies. The state and the HUD read
one proc.
_Avoid_: Placement light state, preview light

**Ghost**:
The wireframe preview of the armed placement: the oriented box, its footprint on
the surface, and the height guide. It is a planning aid, not a collision test.
_Avoid_: Preview, hologram

**Spawn pop**:
The short scale animation that a newly placed or duplicated object plays. It
starts at a 0.01 floor, overshoots by about 8 percent, and settles at full size
in 0.28 s with the AABB bottom fixed. The physics body keeps its full size.
Initial objects and undo or redo restores do not pop.
_Avoid_: Spawn animation, grow effect

**Grid snap**:
The optional 0.25 m X/Z rounding of the ghost's bottom anchor. It is off by
default.
_Avoid_: Grid, quantization

**Marked strip**:
The yellow arena strip on the east side. It is left from the crouch slide that
the arena used to train.
_Avoid_: Slide lane, runway

**West wall**:
One of the two 1.2 m and 1.5 m walls on the west side. The spider walks around
them; it cannot climb.
_Avoid_: Mantle wall, ledge

**High platform**:
The 2.5 m arena platform at the north end.
_Avoid_: Dive platform, tower

**Spawn**:
The point where the player starts and returns after a reset.
_Avoid_: Start, origin

**Simulation**:
The headless fixed-step update that owns the world, the player state, and the
settings.
_Avoid_: Game loop, engine

**Input snapshot**:
One frame of player intent: movement axes, sprint, jump, and reset. Look is a
separate frame call.
_Avoid_: Input state, controls

**Frame input**:
The resolved intent of one frame: the Input snapshot, the Editing actions, the
menu intents, the view intents, and the pause and cursor state. `src/input` turns
one `platform.Events` value into one `Frame_Input`. The resolver holds only the
edge latches.
_Avoid_: Input state, input command

**Settings**:
The runtime window and input-mode choices: window mode, display, resolution,
and the sprint input mode. A new simulation starts Borderless on display 0; the
stored Windowed size is 1280x720, with sprint Hold. A player reset keeps the
current settings.
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
The `harbagsa-agent` program that drives the simulation and writes screenshots
without the game loop.
_Avoid_: Bot, driver

**Scenario**:
A JSON document that compiles to one command list for the harness.
_Avoid_: Script

**Capture**:
One rendered frame written as a PNG, a float or raw image, a statistics summary, or a profile by the harness.
_Avoid_: Shot

**Capture group**:
One rendered frame that writes several capture outputs from the same pixels.
_Avoid_: Batch, multi-shot

**Capture target**:
The image a capture reads: the final color, the velocity target, the history, the depth buffer, or the scene color.
_Avoid_: Render layer

**Diagnostic view**:
One named image a capture can request from one simulation frame: `beauty`, `direct`, `lightmap`, `probe`, `emissive`, `shadow`, `lightmap_grid`, or `probe_cell`. A `views` list writes one capture entry per view, named `<name>-<view>`, each with a `view` field. A view is not a capture target, and `target` and `views` are mutually exclusive.
_Avoid_: Debug view, render layer

**Term view**:
A diagnostic view of one radiance term or of the data that term reads. It is one extra lit pass at the same camera and jitter, resolved through the gamma path with history read and write disabled, so it neither resets nor advances TAA.
_Avoid_: Light pass, debug pass

**View image**:
The renderer-owned color image a term view resolves into before the readback copy. It is allocated on the first term-view capture and reused until the target extent changes; the game binary that never captures owns none.
_Avoid_: View buffer, view target

**Pick**:
One pixel resolved to the surface under it: the object identity, distance, world position and normal, face, lightmap rect and texel, probe cell, and the five terms. The renderer traces the pixel's camera ray against the frame TLAS in a one-pixel compute pass that reads the shared term include; the harness maps the instance custom index to the scene object. `pick` is a command error while the menu is open and when `at` is outside the capture extent.
_Avoid_: Pixel probe, raycast (that word belongs to the bake)

**Capture format**:
The output a capture writes: PNG for color, `float` for RGBA f32 values, `raw` for the stored texel bytes, `stats` for the numeric summary, or `profile` for a line or mean span.
_Avoid_: Export mode

**Capture option**:
One extra capture block: region, profile, crop, histogram, steps, or color key. The parser checks the option against the format, and the recorder writes every option back into the recorded command.
_Avoid_: Capture flag, modifier

**Capture statistics**:
The per-channel minimum, maximum, mean, standard deviation, and gradient of a capture over an optional region, plus the median screen motion in texels for a velocity capture over covered pixels. Each block names its channels `x`, `y`, `z`, and `w`. The gradient is the mean absolute difference between 4-neighbour pixels; a region with no neighbour pair reports zero. A colour key adds the count of pixels within a tolerance of one RGB value.
_Avoid_: Image metrics

**Shader digest**:
The FNV hash of the SPIR-V embedded in the binary, reported at `setup.renderer.shader_digest`. Unlike the render digest, it changes when a shader changes.
_Avoid_: Build hash, shader version

**Harness schema**:
The JSON document from `harbagsa-agent schema` that names the command fields, units, scenario keys, capture targets and formats, and state field tree.
_Avoid_: Command list

**Static box**:
An immutable box in the arena: the floor, a wall, the ceiling, or a prop. It is
not a placed object and it does not enter the simulation digest. It receives
direct light, hard shadows, and a lightmap tile. `static_boxes` reports every
static box; `harbagsa-agent boxes` prints the same list without a renderer.
_Avoid_: Arena mesh, level mesh

**Shot**:
A scenario-only shorthand that compiles to an optional camera, a settle, and one
capture. A live session does not accept it.
_Avoid_: Preset, view

**Visual A/B**:
The `ab --visual` flow that builds a base ref and the current tree, runs one scenario on both, and writes a labeled compare panel with the delta column.
_Avoid_: Montage, image diff

**Session**:
The live harness process that reads one JSON command per line and writes one
JSON reply per line.
_Avoid_: Daemon, server

**Offscreen target**:
The render target with a color image and a depth image, but no surface or
swapchain. Its capture readback buffer is allocated on the first capture.
_Avoid_: Headless framebuffer

**Capture readback**:
The mapped GPU buffer that receives a capture copy. It is allocated on the first
frame that asks for a capture, so the live game without a capture owns no
readback buffer. The error names the target, format, required bytes, and buffer
size when it does not fit.
_Avoid_: Capture buffer, staging buffer

**Frame in flight**:
The number of submitted frames the CPU may record before the GPU completes one.
The swapchain target keeps two. The offscreen target keeps one, because it owns
a single color image and a single capture readback buffer.
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
The scopes that draw the scene into the depth, color, and velocity targets: the
depth prepass and the lit pass. The perf report times them as separate GPU
passes.
_Avoid_: Main pass

**Depth prepass**:
The depth-only scope of the scene pass. It writes the nearest box surface before
the lit pass, so point-light loops run only for the surface that reaches the
frame.
_Avoid_: Z prepass

**Lit pass**:
The color scope of the scene pass. It loads the depth the prepass wrote and
shades the boxes with the direct point lights, the baked indirect term, and the
emissive term.
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
The 2D part of the overlay: crosshair, player state, and the notice. It does not
show the control list.
_Avoid_: UI

**Settings menu**:
The paused overlay opened with `Esc`. It lists the active control set and changes
the window mode, display, resolution, type weight, and three input modes. The harness opens
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
header. Each role fixes an em size, leading, weight, and tracking. A size is the
em in device pixels, so a 15 px role draws a 15 px em. See `docs/ui/type.md`.
_Avoid_: Font sizes, text styles

**Coverage atlas**:
The one texture that holds every glyph as the fraction of each pixel the glyph
covers, rasterized at the device pixel size from the subset Geist and Geist Mono
faces. It holds one layer per face, weight, and pixel size the theme can draw,
and it is repacked when the density or the type weight changes.
_Avoid_: SDF atlas, font texture, bitmap font, glyph sheet

**Type weight**:
The variable-font weight the 2D layer draws at, from 100 to 900. The settings
menu and the `menu` command set it, every type role derives from it, and the
coverage atlas rebuilds on a worker when it changes.
_Avoid_: Font weight, boldness

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

**Notice**:
A one-line message on the top-right margin after an action whose result is not
on screen. It names the scene snapshot path, or says the write failed, and holds
for two seconds of frame time. Unlike the status note, it is not inside a panel.
_Avoid_: Toast, popup, tooltip

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

**Frame targets**:
The depth, lit colour, and velocity images that the depth, scene, and sky
passes render into. They belong to the frame, not to TAA: TAA samples the two
colour images and adds its own history.
_Avoid_: TAA targets, render targets

**Temporal anti-aliasing (TAA)**:
The render path that jitters the camera and averages frames through a history buffer to smooth edges.
_Avoid_: Temporal filtering, accumulation

**Jitter**:
The subpixel camera offset applied each frame for TAA.
_Avoid_: Shake, offset

**History**:
The previous resolved frame, with linear color, view depth, and sample count, that TAA blends into the current frame. The color is 32-bit so small updates survive at the 512-sample cap.
_Avoid_: Accumulation buffer, cache

**History precision**:
The bit width of the resolved history. A 32-bit history holds small running-average updates at 512 samples; a 16-bit history loses more of those updates to rounding.
_Avoid_: Bit depth, accuracy

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

**State schema**:
The `State` struct and its JSON tags. The JSON writer, the field resolver, and
the simulation digest read the same fields.
_Avoid_: Field table, resolver table

**State section**:
The part of `State` that one field namespace needs. `state_build_sections`
builds only that part; `digest` is the only field that needs every section.
_Avoid_: State slice, partial document

**Renderer state**:
The harness state block that describes the last rendered frame: frame count, TAA
state, jitter index, history validity, convergence frames, history read index and
weight, reset count and reason, active point-light count, timestamp period,
bake status and key, lightmap and probe switches, and the debug vertex counts by
source. A capture
carries the same block for the frame that wrote it.
_Avoid_: Render stats, GPU state

**Render digest**:
The FNV-1a hash of the effective render inputs: extent, camera, boxes, box
emissive strengths, point lights, jitter, atlas weight, clip height, shadow
visibility, lightmap and probe switches, bake key, bake status, and view flags.
It is separate from the simulation digest.
_Avoid_: Frame hash, image hash

**History reset reason**:
The cause recorded at each TAA history reset: create, extent, toggle, teleport, scene change, debug override, player reset, or scene reset.
_Avoid_: Reset flag

**Renderer debug override**:
A gated change to a renderer input for diagnosis: TAA, jitter, history weight,
clamp, depth trust, synthetic lights, the plan-view clip height, light shadows,
the lightmap term, or the probe term. Every change resets history. A field set to
`null` restores that field's default without clearing the others.
_Avoid_: Debug flag

**Renderer debug patch**:
The sparse set of renderer debug override fields that one command or scene block
carries. An absent field keeps its live value; a `null` field restores its
default. A scene snapshot writes every effective field, so a repro restores the
exact override.
_Avoid_: Debug struct, override delta

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
objects and lights.
_Avoid_: Edit mode, sandbox

**Free-fly camera**:
The debug mode camera that ignores gravity and collision.
_Avoid_: Noclip, spectator

**Selection**:
The placed object that debug mode acts on.
_Avoid_: Focus, target

**Object inspector**:
The debug HUD block that shows the selected object's prefab and id, the object
count and capacity, and the body, size, position, yaw, and snap state. Every
changing value uses a fixed field and the mono face.
_Avoid_: Edit panel, properties

**Undo history**:
The 64-entry stack of placed-object snapshots that undo and redo restore. Each
snapshot keeps the object ids and the exact transforms; a restore never plays
the spawn pop.
_Avoid_: Journal, transaction log

**Scene reset**:
The `Shift+R` action that restores the starting crates, lamps, and player.
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
A harness run that measures frames instead of simulation state. It reads the
wall clock, so its numbers are not deterministic.
_Avoid_: Benchmark

**Perf report**:
The `perf` object in a harness reply and in `report.json` that holds the
percentiles, per-pass means, variants, paired deltas, clock, and load average of
a perf run.
_Avoid_: Benchmark result, profile

**Perf variant**:
A named renderer-debug patch that a perf round measures beside the baseline. It
can carry any renderer-debug field, including `synthetic_lights`.
_Avoid_: Profile, configuration, preset

**Perf round**:
One pass through the perf schedule: the baseline, then every other variant with
a baseline window after it.
_Avoid_: Iteration, repetition

**Perf baseline**:
The variant a round measures first and after every other variant, so each
variant window is bracketed by two baseline windows.
_Avoid_: Control, reference run

**Perf discard**:
The opening perf rounds left out of the per-variant statistics. At most
`rounds - 1` rounds are dropped, so one round is always kept. The report carries
the requested count and the effective `discarded` count.
_Avoid_: Cooldown, warmup

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

## Harness measurement terms

### Banding
A run of identical 8-bit values along a gradient. **Avoid**: stepping, contouring.

### Dither
A fixed, per-pixel offset applied before an 8-bit quantization. The output
dither on the resolve breaks a band without entering the TAA history. The
visibility dither is a separate offset inside one ray-count step; see
**Visibility dither**. **Avoid**: noise, grain.

### Visibility dither
A per-pixel, per-frame offset inside one visibility step. The offset breaks the
step in one frame; the phase sequence and the 32-bit history average it into a
continuous field. A full or empty count stays exact. **Avoid**: noise, jitter.

### Step
A local jump in the box-filtered luma that a visibility count leaves at a band
edge. `capture.stats.steps` counts the jumps between half a level and a
geometry edge, names the eight largest in `top`, and counts the jumps at or
above the cap in `over_cap`. **Avoid**: edge, contour.

### Region
A rectangle of the source image that limits a capture's statistics or
histogram. A **normalized region** gives the same rectangle as fractions of the
frame with `"unit": "normalized"`, so one scenario works at every capture size.
The report echoes the resolved pixel region. **Avoid**: window, crop (a crop
changes the written image).

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

### Scenario requirement
A gated capability a scenario declares in `requires`, such as the renderer
debug gate. The runner enables it for that run. **Avoid**: precondition, flag.

### Scenario parameter
A named value a scenario declares in `parameters` and uses as `${name}`. The
declared value sets the type. **Avoid**: variable, argument.

### Parameter sweep
One scenario run per value of one or more scenario parameters, with each run in
its own directory. **Avoid**: matrix run, batch.

### Sweep label
The run directory name built from a sweep's parameter values.
**Avoid**: run name, suffix.

### Run tag
A directory name appended to the run path so two runs coexist. **Avoid**:
label, suffix.

### Compare panel
A labeled PNG that puts the same capture from two runs side by side, with each
run's scenario, revision, and dirty flag. It is visual evidence.
**Avoid**: montage, contact sheet.

### Scene snapshot
One `scene` command that carries the exact camera, placed objects (with names),
settings, display list, view flags, and renderer debug overrides of a live view. `F5` writes one, and `record` starts with one.
**Avoid**: state dump, replay file.

### Repro
The `F5` action and its harness twin, the `repro` command: write one scene
snapshot to a file and show the notice. The key writes
`runs/repro/repro-<unix-ms>.json`. A harness `repro` path is relative to the run
directory (or the `session --out` directory), and an absolute path stays
absolute. **Avoid**: replay file, state dump.

### Object name
An optional unique handle on a placed object. `place` and a scene object set it;
`remove`, a `get` path (`objects.<name>.<field>`), and `editor.select_object`
accept it. It uses at most 31 letters, digits, `-`, or `_`, is not all digits,
and is not `count`. It survives undo and a scene snapshot and stays out of the
simulation digest. **Avoid**: label, tag, alias.

### Place command
The harness `place` command creates one object from a prefab at an exact
transform without entering debug mode. It is scene setup, not an edit, so it
has no undo entry and draws no editor lines. **Avoid**: editor place,
spawn (a spawn is the game API).

### Remove command
The harness `remove` command deletes one object by id without entering debug
mode. **Avoid**: delete (the editor action).

### Display list
The harness's scripted set of displays and modes. It replaces the compositor
snapshot for a scenario. **Avoid**: monitor list.
