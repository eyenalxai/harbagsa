# The world

One shader over one mesh. `src/renderer/shaders/box.frag` shades a unit cube,
and every object in the scene is that cube, scaled and rotated. There is no
texture, normal map, fog, bloom, or tone map. One directional sun casts
ray-query shadows.

## The palette

Colours are authored as linear RGBA floats, because the renderer shades in linear
space. This is the opposite of the 2D layer, which authors sRGB hex
([colour.md](../ui/colour.md)). Do not copy a value between the two tables.

| Surface | Linear RGBA | Source |
| --- | --- | --- |
| Sky | `0.10 0.45 0.75` | `src/renderer/renderer.odin:18` |
| Floor | `0.42 0.43 0.46` | `src/game/arena.odin:18` |
| Wall | `0.55 0.34 0.26` | `src/game/arena.odin:19` |
| Stairs, ramps, steps | `0.30 0.55 0.85` | `src/game/arena_props.odin:86` |
| Tunnel | `0.85 0.50 0.20` | `src/game/arena_props.odin:87` |
| Dive set | `0.25 0.75 0.40` | `src/game/arena_props.odin:88` |
| Slide lane | `0.90 0.80 0.20` | `src/game/arena_props.odin:89` |
| Mantle wall | `0.60 0.35 0.80` | `src/game/arena_props.odin:90` |
| Room | `0.38 0.60 0.56` | `src/game/arena_room.odin:50` |
| Crate, green | `0.30 0.68 0.38` | `src/game/prefabs.odin:44` |
| Crate, orange | `0.86 0.56 0.20` | `src/game/prefabs.odin:45` |
| Crate, blue | `0.26 0.48 0.84` | `src/game/prefabs.odin:46` |
| Sun light | `1.00 0.98 0.94` | `src/renderer/shaders/box.frag:43` |
| Debug selection | `1.00 0.80 0.20` | `src/game/debug_draw_objects.odin:6` |

Rules:

- A new arena feature takes a hue that is not already in use. The arena carries
  eight, and the hue is how a player names the feature.
- Crates use their own high-chroma palette, never a wall hue, so a pushed crate
  reads against every surface.
- The debug selection amber is `1.00 0.80 0.20` in linear space. The UI accent is
  `#E6AF3A` in sRGB. They are different colours in different spaces. Keep both
  values. Do not merge them into one token.

## One sun

The sun is one directional light. Its angular diameter is a scene input, not a
renderer constant: it defaults to the real 0.53°
(`src/game/debug_mode.odin:12`) and the harness `sun` command can change it. A
wider disk widens every penumbra, so the shadow stops reading as a shadow. The
shader takes 16 samples on a Vogel disk, so a penumbra has 17 levels and softens
with blocker distance.

There is no ambient term. The sun and the point lights are the only light
sources, and the sky is a background. A surface that neither reaches is black.

The ambient-occlusion rays stay; they scale the direct light instead of an
ambient term. The formula is:

```text
albedo * (diffuse * sun * visibility + point_lights) * occlusion
```

The occlusion is a local visibility term. It darkens a lit corner or a contact
band; a surface the light does not reach stays black. It applies to the sun and
the lamps, at strength 0.5. It is not global illumination and it does not bounce.

The occlusion uses 8 rays and the sun 16. A partial count carries a per-pixel,
per-frame offset inside its own step; a full or empty count stays exact. Without
the offset a partial count steps in eighths and a contact band shows a contour.
The TAA history is 32-bit, so the resolve can average the offset over the phase
sequence; a 16-bit history rounds that average away and keeps the count field.
The output dither is a separate, last step for the 8-bit write.

If a surface must look different, change its albedo. Do not add a lighting term.

## No texture

There is no sampler in the scene shader. A face is one flat colour with one
constant normal. No smooth shading exists anywhere in the 3D scene, and no
material distinguishes one box from another except its colour.

## The sky

The sky is an analytic gradient, not a texture. `sky.glsl` gives one ramp for
the sky pass. The sky is a background, not a light. With the sky pass off, `DEFAULT_CLEAR_COLOR` is
`(0.10, 0.45, 0.75)`, written linear into an RGBA16F target.

The gradient is the only large soft field in the frame. Keep the horizon band
narrow so it does not compete with the penumbra, and do not add a skybox or a
cloud.

## Geometry

- Every shape is a box. A ramp is a thin box rotated about X.
- No rounded, bevelled, or non-box primitive. A curve in the world would be the
  only curve on screen.
- The arena is 40 m square with 4 m walls: 63 static boxes and 3 crates at
  spawn. The floor is 1 m thick, the arena walls 0.5 m, and a crate 1 m. The
  closed room in the +x/+z corner is 11 m square with 3 m walls, a 0.3 m
  ceiling, and one 1.6 m by 2.2 m door in the west wall.
- The door opens into a four-turn light lock: east, south, west, south, and east
  into the chamber. The tunnel is 2.0 m wide and 2.4 m high. No straight sun ray
  reaches the chamber. The base is total darkness, so the chamber is black until
  a lamp is placed. There is no bounce.
- The player has no body and casts no shadow.
- No fog and no depth cue beyond perspective. The near plane is 0.05 m and the
  far plane 200 m.

## What a new prop must do

1. Be a box.
2. Take a hue that is not in the palette.
3. Cast and receive the same sun shadow as everything else.
4. Add nothing to the shader.
5. If it moves, add nothing to the camera. [motion.md](motion.md) explains why.
