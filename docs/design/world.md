# The world

One shader over one mesh. `src/renderer/shaders/box.frag` shades a unit cube,
and every object in the scene is that cube, scaled and rotated. There is no
surface or material texture, normal map, fog, bloom, or tone map. Point lights
supply direct light; static fixtures also bake one diffuse bounce into a
lightmap and a static probe field.

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
| High platform set | `0.25 0.75 0.40` | `src/game/arena_props.odin` |
| Slide lane | `0.90 0.80 0.20` | `src/game/arena_props.odin` |
| West wall | `0.60 0.35 0.80` | `src/game/arena_props.odin` |
| Ceiling | `0.20 0.23 0.27` | `src/game/arena.odin` |
| Crate, green | `0.30 0.68 0.38` | `src/game/prefabs.odin` |
| Crate, orange | `0.86 0.56 0.20` | `src/game/prefabs.odin` |
| Crate, blue | `0.26 0.48 0.84` | `src/game/prefabs.odin` |
| Debug selection | `1.00 0.80 0.20` | `src/game/debug_draw_objects.odin` |
| Spider body | `0.30 0.10 0.13` | `src/game/spider.odin` |
| Spider legs | `0.20 0.07 0.09` | `src/game/spider.odin` |
| Spider markings | `0.90 0.42 0.10`, emissive 0.55 | `src/game/spider.odin` |
| Spider eyes | `1.00 0.62 0.16`, emissive 2.4 | `src/game/spider.odin` |

Rules:

- A new arena feature takes a hue that is not already in use. The hue is how a
  player names the feature.
- Crates use their own high-chroma palette, never a wall hue, so a pushed crate
  reads against every surface.
- The debug selection amber is `1.00 0.80 0.20` in linear space. The UI accent is
  `#E6AF3A` in sRGB. They are different colours in different spaces. Keep both
  values. Do not merge them into one token.
- The spider owns the red family. No arena surface uses it, so the player never
  reads as a prop. Its four eyes and two abdomen markings are the only emissive
  surfaces that are not lamp prefabs: the eyes read at the front, and two bars on
  the abdomen carry the silhouette from behind. The spider is dynamic and does
  not enter the static bake. Its markings do not join the lamp budget. Do not add
  a player light; it would break the darkness rule.

## Direct light

Every active lamp contributes from its current transform. The clustered forward+
pass assigns each light to the camera clusters its range overlaps. The lit pass
then shades only the lights that can reach the fragment.

The formula is:

```text
static box:  albedo * (direct_point_lights + lightmap_indirect) + albedo * emissive
dynamic box: albedo * (direct_point_lights + probe_indirect) + albedo * emissive
```

A surface receives no light unless a current point light reaches it, the baked
static indirect carries a bounce from a static fixture, or the surface is
emissive. A lamp-free view is black. There is no ambient floor or fill light; the
baked indirect is transport, not a default term.

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

Static fixtures bake one diffuse bounce. The bake writes one `1024²` lightmap
atlas for static boxes and a static probe field for dynamic boxes. Static boxes
read their face tile from the lightmap. Dynamic boxes sample the four probes of
the containing tetrahedron, with normal bias, a facing weight, and the baked
depth test. There is no per-frame probe pass and no probe update. A ray that
misses returns zero; there is no sky or sun term.

The default probe grid is 1 m over the closed arena; 2 m is the quality fallback.
Each probe stores an 8 x 8 octahedral irradiance block and depth moments. A probe
inside static geometry is invalid and is skipped. The bake dilates an invalid
probe from the nearest valid probe when the virtual offset cannot repair it, so
the copied depth moments keep their origin.

The bake key covers the static boxes, the active static fixtures, the quality,
and the tool version. A static fixture or static geometry edit marks the bake
stale: direct light and shadows update immediately, while the old indirect stays
bound until an explicit bake publishes the new artifact. A dynamic lamp or crate
move does not change the key. `state.bake` reports `missing`, `stale`, `current`,
or `failed`; a missing or failed artifact never falls back to black or to another
bake.

The `lightmap` and `probe` renderer overrides, both default true, exist for paired
captures and performance runs. They are not per-lamp or per-room controls. A
denser grid, more rays, and more than one bounce are new decisions, not hidden
shader options.

A lamp carries a kind. A static fixture uses a static body, and its light
position comes from that body. A dynamic lamp uses a dynamic body and contributes
direct light and hard shadows only. The starting arena places one warm Lamp, one
cool Light panel, and one red Beacon as static fixtures in front of the spawn.
Newly placed lamps default to dynamic; `K` toggles the kind and the body follows
it.

A lamp-free view is black. One lamp restores readable light. Moving a static
fixture moves its direct light and shadow and leaves the bake stale. Moving a
dynamic lamp moves only its direct light and shadow. A sealed wall stops the
baked bounce.

## No texture

There is no surface or material texture. The scene shader has one lightmap
sampler and one probe sampler; both carry baked lighting data, not a material
image. A face is one flat colour with one constant normal. No smooth shading
exists anywhere in the 3D scene, and no material distinguishes one box from
another except its colour and light.

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
- The arena is one closed box. There is no interior room and no path to a
  background.
- The player has no body.
- No fog and no depth cue beyond perspective and lamp range. The near plane is
  0.05 m and the far plane 200 m.

## What a new prop must do

1. Be a box.
2. Take a hue that is not in the palette.
3. Receive the same direct point lights and shadows as everything else, plus the
   baked static bounce: a lightmap tile if it is static, the probe field if it is
   dynamic.
4. Add nothing to the shader.
5. If it moves, add nothing to the camera. [motion.md](motion.md) explains why.
