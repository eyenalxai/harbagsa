# The world

One shader over one mesh. `src/renderer/shaders/box.frag` shades a unit cube,
and every object in the scene is that cube, scaled and rotated. There is no
texture, normal map, fog, bloom, or tone map. Point lights supply direct light.

## The palette

Colours are authored as linear RGBA floats, because the renderer shades in linear
space. This is the opposite of the 2D layer, which authors sRGB hex
([colour.md](../ui/colour.md)). Do not copy a value between the two tables.

| Surface | Linear RGBA | Source |
| --- | --- | --- |
| Clear colour | `0.012 0.016 0.024` | `src/renderer/renderer.odin` |
| Floor | `0.42 0.43 0.46` | `src/game/arena.odin` |
| Wall | `0.55 0.34 0.26` | `src/game/arena.odin` |
| Stairs, ramps, steps | `0.30 0.55 0.85` | `src/game/arena_props.odin` |
| Tunnel | `0.85 0.50 0.20` | `src/game/arena_props.odin` |
| Dive set | `0.25 0.75 0.40` | `src/game/arena_props.odin` |
| Slide lane | `0.90 0.80 0.20` | `src/game/arena_props.odin` |
| Mantle wall | `0.60 0.35 0.80` | `src/game/arena_props.odin` |
| Ceiling | `0.20 0.23 0.27` | `src/game/arena.odin` |
| Crate, green | `0.30 0.68 0.38` | `src/game/prefabs.odin` |
| Crate, orange | `0.86 0.56 0.20` | `src/game/prefabs.odin` |
| Crate, blue | `0.26 0.48 0.84` | `src/game/prefabs.odin` |
| Debug selection | `1.00 0.80 0.20` | `src/game/debug_draw_objects.odin` |

Rules:

- A new arena feature takes a hue that is not already in use. The hue is how a
  player names the feature.
- Crates use their own high-chroma palette, never a wall hue, so a pushed crate
  reads against every surface.
- The debug selection amber is `1.00 0.80 0.20` in linear space. The UI accent is
  `#E6AF3A` in sRGB. They are different colours in different spaces. Keep both
  values. Do not merge them into one token.

## Direct light

Every active lamp contributes from its current transform. The clustered forward+
pass assigns each light to the camera clusters its range overlaps. The lit pass
then shades only the lights that can reach the fragment.

The formula is:

```text
albedo * (direct_point_lights + probe_indirect) + albedo * emissive
```

A surface receives no light unless a current point light reaches it, a probe
carries a bounce from a current light, or the surface is emissive. A lamp-free
view is black. There is no ambient floor or fill light; the probe field is
transport, not a default term.

A point light uses the surface normal and a squared range falloff. A hard shadow
ray also tests visibility for each lamp that can reach the fragment. A blocked
lamp contributes zero. The lamp has no radius, so the shadow edge is hard. The
lit pass traces against the same cube TLAS as the rest of the scene. The ray
starts just above the surface, stops just short of the lamp, and excludes lamp
boxes. This keeps a wall-mounted lamp from shading the wall it sits on.

There is no shadow map, soft-shadow sampling, or screen-space visibility pass.
The `light_shadows` renderer override exists only for paired captures and
performance runs. It is not a per-lamp editor control. A future lamp radius or
soft shadow is a new decision, not a hidden shader option.

## Indirect light

One probe volume covers the closed arena. Probes sit every 2 m on a 20 x 3 x 20
grid. Each probe traces 64 rays into the same point lights and emissive boxes as
the lit pass and stores an 8 x 8 octahedral irradiance and depth atlas. The lit
pass blends the eight surrounding probes, rejects probes behind the surface, and
adds the result as `probe_indirect`. There is one diffuse bounce. A ray that
misses returns zero; there is no sky or sun term.

A probe inside a box is invalid and is skipped. A probe behind the shaded
surface is rejected by the facing weight; the depth test alone lets a probe on
the far side of a thin wall carry light across it. The field follows a moving
lamp on the next frame. Probe rays use the scene TLAS, so the renderer builds
that structure when either shadows or GI is enabled.

The `gi` renderer override, default true, exists for paired captures and
performance runs. It is not a per-lamp or per-room control. Multi-volume probe
fields, a denser grid, more rays, and more than one bounce are new decisions, not
hidden shader options.

Every lamp prefab uses a dynamic body. Its light position comes from that body
on every frame. A static or baked lamp is not an alternate mode. The starting
arena places one warm Lamp, one cool Light panel, and one red Beacon in front of
the spawn.

`scenarios/lighting.json` checks that a lamp-free view is black and that one
lamp restores readable light. `scenarios/initial-lamps.json` checks the three
starting lamps and a moved light. `scenarios/light-move.json` checks that a
transform change updates the image and render digest.
`scenarios/shadows.json` checks a blocked surface and the paired toggle.
`scenarios/lamp-wall-plane.json` checks the wall-plane regression.
`scenarios/shadow-move.json` checks that a moved lamp moves its shadow.
`scenarios/gi.json` pairs GI on and off around a corner. `scenarios/gi-dark.json`
keeps the lamp-free view black. `scenarios/gi-move.json` moves the lamp and
changes the bounce. `scenarios/gi-sealed.json` proves a sealed wall stops the
bounce.

## No texture

There is no sampler in the scene shader. A face is one flat colour with one
constant normal. No smooth shading exists anywhere in the 3D scene, and no
material distinguishes one box from another except its colour and light.

## Clear colour

The clear colour is constant. It fills only a pixel that no box covers. It is not
a background pass and not a light source. A closed interior should cover it in
normal play. Plan-view and inspection captures can still expose it.

## Geometry

- Every shape is a box. A ramp is a thin box rotated about X.
- No rounded, bevelled, or non-box primitive. A curve in the world would be the
  only curve on screen.
- The arena is 40 m square with 5.5 m walls and a solid ceiling. The floor is 1 m
  thick, the walls and ceiling 0.5 m, and a crate 1 m. The ceiling spans the
  outer wall faces, so the shell has no gap.
- The arena is one closed box. There is no interior test room and no path to a
  background.
- The player has no body.
- No fog and no depth cue beyond perspective and lamp range. The near plane is
  0.05 m and the far plane 200 m.

## What a new prop must do

1. Be a box.
2. Take a hue that is not in the palette.
3. Receive the same direct point lights, shadows, and probe bounce as everything
   else.
4. Add nothing to the shader.
5. If it moves, add nothing to the camera. [motion.md](motion.md) explains why.
