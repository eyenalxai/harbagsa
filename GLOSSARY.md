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
The clear space above the feet that a taller stance needs. The controller tests it before the capsule grows. A floor, a step, a crate, or a wall that only grazes the capsule side does not reduce headroom; a shape that crosses the inset probe does.
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
The fixed test level: a floor, walls, stairs, ramps, tunnels, mantle walls, a dive platform, a slide lane, a closed room with a four-turn light lock, and a few crates.
_Avoid_: Map, level

**Room**:
The closed 11 m square arena structure in the +x/+z corner. It has one
1.6 m by 2.2 m door in its west wall. The door opens into a four-turn light
lock; the chamber behind it has no straight path to the door. It is twelve
static arena boxes, not a placed object, and it exists to test interior
lighting.
_Avoid_: Building, house

**Light lock**:
A bent entry tunnel with enough right-angle turns that no straight sun ray
reaches the space behind it. The room's lock turns four times: east, south,
west, south, and east. The tunnel is 2.0 m wide and 2.4 m high.
_Avoid_: Air lock, light trap

**World palette**:
The scene colours, authored as linear RGBA floats because the renderer shades in
linear space. The 2D layer authors sRGB hex instead; a value does not move
between the two tables.
_Avoid_: Scene colours, 3D palette

**Sun**:
The directional light that lights the arena and casts the sun shadows. Debug mode places it on the sky dome.
_Avoid_: Light source

**Sun direction**:
The unit vector from a point in the world toward the sun. The sky angles describe
it: azimuth from `+z` toward `+x`, and elevation above the horizon.
_Avoid_: Sun vector, light vector

**Light direction**:
The direction the sun's light travels. It is the opposite of the sun direction.
The renderer shades with it.
_Avoid_: Sun direction

**Sun placement**:
The debug mode that aims the sun on the sky dome. `L` toggles it, a click
commits the position, and `Esc` or a right click restores the sun from before
the mode. It is separate from the object palette and object placement.
_Avoid_: Sun drag, sun select

**Sun gizmo**:
The debug lines that mark the sun position: a ring, a cross, and a dashed line
to the arena centre. It draws only while sun placement is active.
_Avoid_: Sun marker, sun ray, sun line

**Sky dome**:
The 50 m sphere around the arena centre that holds the sun position. The aim
point is projected onto it, and the height is clamped to 2.5 m above the arena
floor so the sun never sits below the horizon.
_Avoid_: Skybox, sun orbit

**Point light**:
A light with a position, colour, intensity, and range. The renderer holds every active point light in a growable buffer, and each costs one hard shadow ray per fragment. A lamp prefab owns one.
_Avoid_: Lamp (the prefab), bulb

**Cluster**:
A cell of the camera frustum, 16 by 9 by 24 with logarithmic depth slices. A light belongs to a cluster when its range sphere overlaps the cell. The lit pass shades only the lights of the fragment's cluster.
_Avoid_: Tile, bin

**Clustered forward+**:
The forward lighting path that builds a light index list per cluster in a compute pass, then reads that list in the lit pass. It keeps the per-pixel light loop proportional to the lights that can reach the surface.
_Avoid_: Tiled forward, light grid

**Lamp prefab**:
A prefab with an active point light and an emissive box. The catalog has the Lamp, the Light panel, and the Beacon. A lamp is placed like any other object and can be static or dynamic.
_Avoid_: Light object, bulb

**Light budget**:
The set of active point lights. Every placed lamp with an active light is in the budget; the renderer no longer keeps a nearest subset. The inspector shows the active count against the lamp count.
_Avoid_: Light cap, light count (that is the reported number)

**Lamp shadow**:
The hard point-light shadow. One ray runs from the shaded point to each active lamp per fragment, so the edge is sharp and the cost follows the covered pixels and the active light count. The ray stops one millimetre short of the light, so a surface the lamp sits on cannot shadow it.
_Avoid_: Point shadow map, soft lamp shadow

**Emissive box**:
A box whose colour adds to its shaded colour after the sun and point lights. It carries an emissive strength in the box data. Lamps are emissive so they glow even when their light is inactive.
_Avoid_: Glow shader, unlit material

**Light mask**:
The TLAS instance mask that decides which acceleration-structure ray queries see a box. Normal boxes use `0xFF`, lamps use `0x01`, the point-light shadow ray tests `0x02`, and the sun ray tests `0xFF`.
_Avoid_: Layer mask, collision mask

**Synthetic light**:
A generated test light that the renderer debug override injects, so a perf run can
fill the frame with an arbitrary light count without placing lamps.
_Avoid_: Fake light

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
The cosine-weighted fraction of the hemisphere at a surface point that visible geometry does not block. The scene has no ambient term, so it scales the direct sun and point light. It darkens a lit corner or contact band; it is not global illumination, because it adds no bounce light.
_Avoid_: SSAO (that is one estimator), GI (that adds bounce light)

**Sky**:
The analytic gradient that fills the background: a horizon-to-zenith ramp, a darker ground color below the horizon, and a sun disk with a glow. It draws after the lit pass and shades only the pixels that no box covers. It is a background, not a light.
_Avoid_: Skybox, cubemap, backdrop

**AO radius**:
The maximum distance an ambient occlusion ray travels: 1.5 m. A surface beyond that distance does not count as an occluder.
_Avoid_: AO distance, occlusion range

**AO strength**:
The multiplier on the ambient occlusion term. `0` leaves the direct light
unchanged and `1` applies the full occlusion. The scene uses 0.5.
_Avoid_: AO amount, AO weight

**Degree boundary**:
The scenario, `state.json`, and `report.json` express every angle in degrees.
Every angle key ends in `_deg`. The engine converts to radians at the edge.
_Avoid_: mixed angle units, implicit units

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
mode, an optional base pitch, and an optional point light. The ramp carries a
20 degree base pitch; the Lamp, Light panel, and Beacon carry a light.
_Avoid_: Template, class, prototype

**Body mode**:
Static or dynamic. A static placed object collides and never moves. A dynamic
placed object uses the prefab density and can be pushed.
_Avoid_: Body type

**Object id**:
The stable number that addresses a placed object through the game API and the
harness. The list index stays internal.
_Avoid_: Handle, slot

**Active tool**:
The one debug tool that owns the frame: the Object palette, Sun placement, or
the Placement tool. `active_tool` reads it; `take_tool` cancels the others.
Arming the Placement tool closes the palette.
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
placement, object, light, sun, pointer, or cancel. One apply proc owns its rule.
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
Initial crates and undo or redo restores do not pop.
_Avoid_: Spawn animation, grow effect

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

**Frame input**:
The resolved intent of one frame: the Input snapshot, the Editing actions, the
menu intents, the view intents, and the pause and cursor state. `src/input` turns
one `platform.Events` value into one `Frame_Input`. The resolver holds only the
edge latches.
_Avoid_: Input state, input command

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
One rendered frame written as a PNG, a float or raw image, a statistics summary, or a profile by the harness.
_Avoid_: Shot

**Capture group**:
One rendered frame that writes several capture outputs from the same pixels.
_Avoid_: Batch, multi-shot

**Capture target**:
The image a capture reads: the final color, the velocity target, the history, the depth buffer, or the scene color.
_Avoid_: Render layer

**Capture format**:
The output a capture writes: PNG for color, `float` for RGBA f32 values, `raw` for the stored texel bytes, or `stats` for the numeric summary.
_Avoid_: Export mode

**Capture statistics**:
The per-channel minimum, maximum, mean, standard deviation, and gradient of a capture over an optional region, plus the median screen motion in texels for a velocity capture over covered pixels. The gradient is the mean absolute difference between 4-neighbour pixels; a region with no neighbour pair reports zero.
_Avoid_: Image metrics

**Shader digest**:
The FNV hash of the SPIR-V embedded in the binary, reported at `setup.renderer.shader_digest`. Unlike the render digest, it changes when a shader changes.
_Avoid_: Build hash, shader version

**Harness schema**:
The JSON document from `harbagsa-agent schema` that names the command fields, units, scenario and suite keys, capture targets and formats, check fields, and state field tree.
_Avoid_: Command list

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
depth prepass, the lit pass, and the sky pass. The perf report times the depth
prepass, the lit pass, and the sky pass as separate GPU passes.
_Avoid_: Main pass

**Depth prepass**:
The depth-only scope of the scene pass. It writes the nearest box surface before
the lit pass, so the sun rays run for the surface that reaches the frame.
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
covers, rasterized at the device pixel size from the subset Roboto Condensed and
Roboto Mono faces. It holds one layer per face, weight, and pixel size the theme
can draw, and it is repacked when the density or the type weight changes.
_Avoid_: SDF atlas, font texture, bitmap font, glyph sheet

**Type weight**:
The variable-font weight the 2D layer draws at, from 100 to 900. The settings
menu and the `menu` command set it, every type role derives from it, and the
coverage atlas rebuilds on a worker when it changes. Mono stops at 700.
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

**Temporal anti-aliasing (TAA)**:
The render path that jitters the camera and averages frames through a history buffer to smooth edges.
_Avoid_: Temporal filtering, accumulation

**Jitter**:
The subpixel camera offset applied each frame for TAA.
_Avoid_: Shake, offset

**History**:
The previous resolved frame, with linear color, view depth, and sample count, that TAA blends into the current frame. The color is 32-bit so the 1/513 update at the sample cap survives the round.
_Avoid_: Accumulation buffer, cache

**History precision**:
The bit width of the resolved history. A 32-bit history holds the running average at 512 samples; a 16-bit history rounds the 1/513 update away and keeps the ray-count field.
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
The `State` struct and its JSON tags. The JSON writer, the check resolver, and
the simulation digest read the same fields.
_Avoid_: Field table, resolver table

**State section**:
The part of `State` that one check namespace needs. `state_build_sections`
builds only that part; `digest` is the only check that needs every section.
_Avoid_: State slice, partial document

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
A gated change to a TAA or point-light input for diagnosis: TAA, jitter,
history weight, clamp, depth trust, shadow phase, point-light shadows, or
synthetic lights. Every change resets history. A field set to `null` restores
that field's default without clearing the others.
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
objects and place the sun.
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

### Suite
A JSON manifest of scenario entries that runs in manifest order. Each entry
keeps its scenario's `requires`, and the suite exit code is the highest entry
code. **Avoid**: batch, group, list.

### Suite entry
One scenario in a suite, with an optional label, size, parameter values, and
render mode. The label names the run directory. **Avoid**: job, item.

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
run's scenario, revision, and dirty flag. It is evidence, not a numeric check.
**Avoid**: montage, contact sheet.

### Scene snapshot
One `scene` command that carries the exact camera, sun, placed objects,
settings, display list, view flags, and renderer debug overrides of a live
view. `F5` writes one, and `record` starts with one. **Avoid**: state dump,
replay file.

### Repro
The `F5` action and its harness twin, the `repro` command: write one scene
snapshot to a file and show the notice. The key writes
`runs/repro/repro-<unix-ms>.json`. A harness `repro` path is relative to the run
directory (or the `session --out` directory), and an absolute path stays
absolute. **Avoid**: replay file, state dump.

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
