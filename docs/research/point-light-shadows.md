# Point-light shadows: technique research for harbagsa

Research for [Wayfinder ticket #348](https://github.com/eyenalxai/harbagsa/issues/348).
This note is not a decision record and not an implementation plan. It compares
the credible techniques, records the evidence, and gives one recommendation for
the decision ticket that follows.

Measured on 2026-10-27. The development GPU is an AMD Radeon RX 9060 XT
(RADV GFX1200), Mesa 26.2.5. The prior ray-query build ran on the same machine.

## Long-term target

The design target is interiors with many lights. [ADR 0029](../adr/0029-unbounded-scene-capacity.md)
names that target and tests 96 lights and 300 objects. The three starting lamps
are a test scene, not a scale bound. A shadow design that only fits the starting
arena is a regression, even if it looks correct there.

This note judges every technique against the many-light target. The scale check
below uses 96 synthetic lights, the documented capacity case. It also uses 8, 16,
32, and 64 lights to show the shape of the cost curve.

## Answer in brief

- **Recommendation:** add one hard ray-query shadow ray per shaded fragment, per
  clustered lamp that passes the normal test, inside a measured shadow budget.
  Trace it in the existing lit fragment shader. Build one cube BLAS and one TLAS
  per frame.
- **This is not a small-arena choice.** The prior clustered ray build added a
  median 2.08 ms at 1080p for 96 dense synthetic lights. The documented 96-light
  target remains viable on the development GPU. The same curve does not support
  an unbounded target of 100+ overlapping shadowed lights on weaker hardware.
- **Why:** the renderer has one cube mesh. One BLAS serves every box, and the
  TLAS memory does not grow six faces per light. Clustered forward+ limits the
  fragment loop to lights that can reach the pixel. Ray queries have no depth-map
  bias, no cube seams, and no separate shadow pass.
- **Cost:** the earlier eight-light build added 0.203 ms at 1080p and 0.444 ms at
  1440p for the shadow rays alone. The newer 96-light check added a median
  2.08 ms at 1080p. Re-adding the TLAS adds about 0.17 to 0.28 ms at these sizes.
  Measure the current renderer before the budget is fixed.
- **Do not use virtual shadow maps first.** Unreal's version targets Nanite
  worlds, uses a cube of 16k virtual maps per point light, and invalidates cached
  pages when a light moves. The lamps here move on purpose. The many-light
  research version is a credible alternative, but it is a large subsystem. It is
  not the smallest path to the measured target.
- **Do not build cube shadow maps first.** At 96 lights, six faces per light is
  576 shadow renders per update. They are the correct fallback if ray-query
  hardware is not a product requirement, but they add bias tuning and cube seams.
- **Soft shadows are a separate decision.** The current light is a zero-area
  point. A hard edge is correct for that model. Softness needs a lamp radius,
  several rays, and usually a denoiser.

## What the renderer does today

The current lit pass uses direct clustered point lights:

- `src/renderer/shaders/box.frag` loops over the lights assigned to the
  fragment's cluster.
- The light term is `intensity * N·L * falloff`. There is no visibility term.
- `src/renderer/lights.odin` uploads the current lamps. The starting arena has
  one warm Lamp, one cool Light panel, and one red Beacon.
- Lamps are dynamic-only. A light follows its body on every frame.
- The light upload and cluster list grow with the scene. ADR 0029 tests 96
  lights and 300 objects. `scenarios/capacity.json` covers 32 and 64 lights.
- There is no sun, no baked lighting, no DDGI, no ambient occlusion, no
  reflection, and no texture.
- Every object is the same unit cube, scaled and rotated. The arena is a closed
  40 m box with a solid ceiling.
- TAA resolves the image after the lit pass.

This is deliberate. [ADR 0037](../adr/0037-direct-dynamic-point-lights.md) removed
the old visibility systems. [The world guide](../design/world.md) says not to add
a shadow map, ray, probe, or screen-space visibility pass to repair point-light
leaks. The owner now asks for shadows. If the recommendation is accepted, those
two documents must change in the same implementation. The shadows should not
arrive as a hidden exception to the current rule.

## What production renderers do now

There is no single modern point-light shadow method. The choice follows scene
scale, light count, geometry, and hardware. The current split is clear.

### Ray-traced local shadows are the default on RT hardware

Unreal Engine's current direct-light path makes ray tracing the default and
recommended shadow method for local lights. Its documentation says most projects
use ray tracing for all local lights because virtual shadow maps add per-light
memory, CPU, and GPU cost to build shadow depths. It also says ray-traced shadows
take precedence over virtual shadow maps because they generally give the highest
quality. [8][9]

The Khronos 2025 Vulkan ray-tracing course teaches ray-query shadows as the
normal path for a simple engine. It lists the main shadow-map problems as
resolution, bias, and one depth texture per light. It uses ray queries in the
fragment shader and treats area sampling as the extension from hard to soft
shadows. [1]

Arm's Vulkan ray-tracing path gives the same construction: one shadow ray per
light for hard shadows, several rays for soft shadows, a normal test before the
ray, a small `TMin`, and `gl_RayFlagsTerminateOnFirstHitEXT`. It also says to limit
the number of shadow-casting lights. [4]

The 2025 Unreal MegaLights talk gives the limit of the per-light method. It
targets 100+ shadowed lights on screen. It states that work per light does not
scale, that a per-light shadow system needs a hard limit on the light count, and
that a VSM cache reached 4 GB and still failed to fit all required lights. Its
answer is stochastic direct lighting: select a fixed number of lights per pixel,
trace a fixed number of rays, shade the hits, and denoise one result. [17] That
is the current production answer when the target is 100+ dynamic shadowed lights,
not only a few local lamps.

The raster counterpart is ReSTIR-sampled shadow maps. It computes full-resolution
shadow maps for a subset of lights selected with spatiotemporal reservoir
resampling. It approximates the remaining lights with imperfect shadow maps. The
authors report real-time scenes with hundreds of lights while using an order of
magnitude fewer shadow maps. [18]

This gives the real fork. A per-light ray path is simple and measured through the
documented 96-light target. A fixed-budget stochastic path is the long-term answer
for 100+ overlapping lights. The decision ticket must name the target before it
chooses the system.

### Unreal virtual shadow maps are for Nanite worlds; virtual cube maps are the many-light variant

Unreal's Virtual Shadow Maps target film-quality assets, large open worlds, and
Nanite geometry. The documentation says that without Nanite, virtual shadow maps
are likely not a good fit. A point light uses a cube map of 16k virtual maps,
one for each face. Multiple small local lights are still a performance work in
progress. Any light movement invalidates all cached pages for that light. [8]

That last property matters here. The lamps move. A cache that the main feature
invalidates has no value here.

The research line behind this technique also targets a different scale. Olsson
et al. present virtual cube-map shadows for hundreds of lights with a bounded
memory footprint. They combine cube maps with ray tracing when each method is
stronger. [6][7] That is a credible long-term path for a building with many
lamps. It is a large subsystem, so it needs a scale target that justifies it.

### Hybrid shadows fit an existing shadow-map renderer

AMD FidelityFX Hybrid Shadows combines rasterized shadow maps with ray tracing.
It rejects pixels that are already clearly lit or clearly shadowed, shortens the
ray interval, traces only where a ray can change the result, and uses a shadow
denoiser. [10][11]

This is a good design when a game already has shadow maps and wants better
contact or soft shadows at a controlled ray cost. This renderer has no shadow-map
base. A hybrid would add both systems at once. That is not the smallest correct
step.

### Classic shadow maps remain the portable fallback

A point-light shadow map needs six faces per light, or a layered cube array that
is rendered in one pass. The fragment compares its distance to the stored depth.
PCF filters a fixed kernel. PCSS adds a blocker search and a variable penumbra.
[12][13]

Unreal describes this path as the default method that works on all platforms that
support dynamic shadowing, with the cost of manual shadow-distance setup and
per-light bias. [14] The Khronos and Arm sources list the same problems:
resolution, bias, peter-panning, and memory per light. [1][4]

For the measured target, the ray path needs less code and no per-light shadow
memory. Cube maps are the correct cost only when ray-query hardware is not
acceptable.

## The candidates

### 1. Ray-query hard shadows

**How it works.** Build a BLAS for the cube mesh and a TLAS from the current box
transforms. In the lit fragment shader, after the normal test, trace one ray from
the surface to the light. If the ray hits opaque geometry before the light, the
light is hidden. Otherwise it contributes.

**Strengths.**

- Exact visibility for the triangles in the BLAS. No depth texel grid.
- No shadow-map depth bias or PCF footprint; only a small ray-origin epsilon.
- No extra render pass or shadow target. The ray runs in the pass that already
  shades the light.
- The cost follows the shaded pixels and the active lights, not every object in
  every light volume.
- Moving lamps and moving boxes need only a new TLAS for the frame.
- It uses raster primary visibility and ray secondary visibility. That is the
  normal modern hybrid shape, not a separate ray-tracing renderer.
- A hard edge is physically correct for the current zero-area point light.
- The acceleration memory is fixed for the box mesh. It does not grow six faces
  per light.

**Costs and risks.**

- It requires ray-query hardware and the matching Vulkan extensions and features.
- A small origin offset and `TMin` are still needed to stop self-intersection.
- A lamp that sits on a wall can make the ray end on that wall. The ray must stop
  short of the light. The previous build found this bug and fixed it. [15]
- The lamp housing must not block its own light. The TLAS instance mask can
  exclude lamp instances from the shadow ray.
- The shadow edge is a pixel-scale binary edge. TAA can resolve the edge over
  time, but there is no penumbra.
- The ray count grows with the visible lights per pixel. At 96 dense lights it
  added 2.08 ms at 1080p. That is a budget, not a free path.

**Fit:** best first step for the documented 96-light target, with a measured
budget. It is not proven for 100+ overlapping shadowed lights.

### 2. Ray-query area shadows

**How it works.** Give each lamp a radius. Sample points on the lamp surface,
trace one ray per sample, and average the binary results. Use 4 to 16 samples,
a low-discrepancy pattern, and temporal accumulation. A shadow denoiser removes
the remaining noise.

**Strengths.**

- Correct soft shadow shape and contact hardening as the blocker distance grows.
- The same TLAS and shader path as hard ray shadows.
- Khronos and Arm both describe area sampling as the direct extension. [1][4]
- Unreal's Shadow Map Ray Tracing uses eight rays by default for local lights,
  which shows the expected sample budget in a production renderer. [8]

**Costs and risks.**

- The current light has no radius. The shader, the light buffer, and the editor
  would gain a new light-shape input.
- One ray per light is noise-free. Several rays per light are not. The noise
  grows with penumbra size and light count.
- TAA is not a shadow denoiser. It can average a static image, but camera motion,
  disocclusion, and moving lamps leave noisy pixels. AMD ships a separate shadow
  denoiser for this reason. [11]
- The ray count multiplies. Eight lights times eight rays is 64 rays per shaded
  fragment before any culling.
- The flat box style may read better with a crisp edge. That is an art decision,
  not a performance one.

**Fit:** the next quality step, after the hard path is measured. The decision is
[#350](https://github.com/eyenalxai/harbagsa/issues/350).

### 3. Cube shadow maps with PCF or PCSS

**How it works.** Render the scene depth into six faces for each point light.
In the lit pass, select the cube face, compare the fragment distance to the
stored depth, and filter the result.

**Strengths.**

- Works on GPUs without ray-query support.
- A well-understood path with mature filtering.
- PCSS gives a soft penumbra with contact hardening. [12]
- A layered render can fill all six faces in one pass per light.

**Costs and risks.**

- Six faces per light. Three lamps means eighteen face renders per update.
  Eight lamps means forty-eight.
- Moving lamps or moving geometry can force all faces to update.
- Bias and normal-offset tuning are required. Bad values cause acne or
  peter-panning. [1][14]
- Cube seams and face-filtering artifacts need care.
- Memory grows with faces, resolution, and light count.
- A shadow-map texel grid can show at close range. That is exactly why the old
  sun path moved to ray queries. [15]

**Fit:** fallback if ray-query hardware cannot be a requirement. Not the first
design for the measured target.

### 4. Virtual or clustered shadow maps for many lights

**How it works.** Keep a virtual shadow atlas, allocate pages only for visible
pixels, cache pages between frames, and use a page table in the lit pass. For
point lights, use a cube of virtual maps. Olsson et al. add ray tracing where it
beats the cube map. Unreal's Virtual Shadow Maps are the production version of
this idea for Nanite worlds. [6][7][8]

**Strengths.**

- Hundreds of lights with bounded memory.
- High resolution where the camera needs it.
- Cached pages make static geometry cheap.

**Costs and risks.**

- A page table, page allocation, culling, cache invalidation, and a projection
  pass. This is a large subsystem.
- Point lights need six faces of virtual maps. Unreal uses 16k virtual maps per
  face for local lights. [8]
- Moving lamps invalidate all cached pages for that lamp. [8]
- The technique is designed around Nanite-style dense geometry. This renderer has
  one cube mesh.
- The published many-light work targets hundreds of lights. The documented
  capacity target is 96 lights. The scale check below shows that per-light rays
  are still viable at 96 on the development GPU. [6][7]

**Fit:** credible long-term alternative if the target grows to hundreds of
overlapping shadowed lights or if ray-query hardware is not acceptable. Not the
first step for the measured 96-light target.

### 5. Screen-space contact shadows

**How it works.** March through the depth buffer from the shaded pixel toward the
light. Stop when the depth buffer occludes the path.

**Strengths.**

- Low cost and no acceleration structure.
- Good for fine contact detail when a shadow-map or ray path already exists.

**Costs and risks.**

- It only sees geometry on screen.
- It cannot produce a long shadow from an off-screen occluder.
- It is an additive detail, not a complete visibility solution. Unreal describes
  it as a per-light additive feature that is limited by the camera view. [14]

**Fit:** possible polish later. Not a substitute for the main shadow term.

## Comparison

| Technique | Bias and seams | Passes and memory | Hardware | Softness | Many lights | Fit here |
| --- | --- | --- | --- | --- | --- | --- |
| Ray-query hard | Small origin epsilon only | No shadow pass; one BLAS and per-frame TLAS | Ray query required | Hard edge | Measured 96 dense lights +2.08 ms at 1080p; needs a budget | **Best first step through the documented target** |
| Ray-query area | Small epsilon; noise instead of bias | Same structures, several rays per light | Ray query required | Soft, noisy without denoiser | Multiplies ray count | Next quality step |
| Cube maps, PCF/PCSS | Depth bias, normal offset, seams | Six faces per light; depth memory | Any GPU with the format | PCF fixed; PCSS variable | Atlas and caching help | Portable fallback |
| Virtual/clustered maps | Page and bias issues | Page table, cache, projection pass | Raster plus optional RT | SMRT or PCF | Designed for hundreds | Credible 100+ alternative |
| Stochastic direct lighting | Denoiser and sampling noise | Fixed rays per pixel; one denoised target | Ray tracing or hybrid | Soft area lights | Designed for 100+ dynamic lights | Destination if overlap grows past the measured target |
| Screen-space contact | None | Depth buffer only | Any GPU | Contact only | Cheap but incomplete | Detail only |

## Evidence from this repository

The project already implemented point-light shadows. That work is useful evidence,
not a proposal to restore the old renderer.

- Commit `999df6a` added direct point lights with one hard shadow ray per light
  per fragment. It built one BLAS and a per-frame TLAS. The shader used
  `gl_RayFlagsTerminateOnFirstHitEXT`, a normal offset, and a lamp instance mask
  that kept a lamp from blocking its own light.
- Commit `e10e396` fixed a real regression. A lamp placed on a wall plane made
  the shadow ray end on the wall. Some pixels hit the wall and some missed it.
  The wall then painted a fan of shadows on every surface the lamp lit. The fix
  stops the ray one millimetre short of the light.
- [The performance evidence at `e10e396`](https://github.com/eyenalxai/harbagsa/blob/e10e3961f3fde084ab02e24ff6149095dfc2ec13/docs/evidence/perf-lamps.md)
  measured eight synthetic lights on the RX 9060 XT.
- Commit `814c80a` removed the acceleration structures, sun, and all ray-query
  code when the renderer was simplified. The old code is in Git history.

The paired eight-light measurements are:

| Size | Scene pass, shadows off | Scene pass, shadows on | Difference | Ratio |
| --- | ---: | ---: | ---: | ---: |
| 1920x1080 | 1.003 ms | 1.204 ms | +0.203 ms | 1.20x |
| 2560x1440 | 1.592 ms | 2.037 ms | +0.444 ms | 1.28x |

The same evidence reports GPU total:

| Size | GPU total, shadows off | GPU total, shadows on | Difference |
| --- | ---: | ---: | ---: |
| 1920x1080 | 1.329 ms | 1.536 ms | +0.207 ms |
| 2560x1440 | 2.012 ms | 2.480 ms | +0.468 ms |

Read these numbers carefully:

- The paired test toggled only point-light shadows. The old sun rays and ambient
  occlusion ran on both sides, so the difference belongs to the point shadow
  term.
- The scene pass includes the depth prepass.
- The comparison does **not** include the cost of adding acceleration structures
  to the current renderer. The old renderer already built them for the sun.
  A separate historical baseline measured the TLAS build at 0.18 ms at 1080p and
  0.17 ms at 1440p. [16]
- The old scene had a different pass cost. The current direct-light renderer is
  much faster. Use the ray delta as a guide and measure the new total.
- The measurement is from one GPU and one driver. It is not a cross-vendor
  budget.

### Many-light scale check

The eight-light run does not test the long-term target. The last ray-shadow build
before the simplification (`4d7ad86`) had clustered forward+ lighting and no fixed
light cap. [19] It is a better test of scale. It still had DDGI and ambient
occlusion, but the paired switch toggles only the point shadow rays, so the
difference stays with the shadow term.

Method: 1920x1080, 60 measured frames, 20 warmup frames, three runs per light
count. The synthetic lights form a dense square grid with a 2 m spacing and an
8 m range. This is a worst case for overlap, not a typical room. Values are the
median of the three paired differences.

| Lights | Median paired shadow cost | Median GPU total, shadows on |
| ---: | ---: | ---: |
| 8 | +0.234 ms | 4.251 ms |
| 32 | +0.621 ms | 5.219 ms |
| 64 | +1.257 ms | 6.576 ms |
| 96 | +2.078 ms | 7.447 ms |

The 8-light row is close to the earlier 0.203 ms. The absolute scene differs
because this build had DDGI and AO. The paired difference is the point shadow
term in both cases.

Reproduce:

```sh
git worktree add /tmp/harbagsa-rt64 4d7ad86
cd /tmp/harbagsa-rt64
tools/make.sh agent
jq '.renderer_debug.synthetic_lights = 96 | .commands[2].value = 96 |
    .commands[3].frames = 60 | .commands[3].warmup = 20 |
    .commands[6].frames = 60 | .commands[6].warmup = 20' \
  scenarios/perf-lamps.json > scenarios/perf-lamps-96.json
./bin/harbagsa-agent run scenarios/perf-lamps-96.json --debug-renderer \
  --size 1920x1080 --out runs/rt64/scale-96-1080
```

The TLAS build was about 0.28 ms in these runs. It runs on both sides, so it is not
in the paired difference. The current renderer has no TLAS, so a new shadow build
pays that cost once per frame, in addition to the ray cost.

What the curve says:

- The shadow cost grows with the number of lights that reach a pixel. It is not
  flat. It is also sublinear in this dense grid, because each light covers only
  part of the screen.
- At the documented 96-light target, the shadow term adds about 2.08 ms at 1080p
  on the development GPU. That is about 12% of a 60 Hz frame. It fits, but it is
  a real budget.
- At 720p, a single 64-light run added about 0.88 ms. The cost follows the pixel
  count.
- Absolute pass times in this old build include DDGI and AO. Do not compare them
  with the current renderer. Compare the paired differences.
- This curve supports the 96-light target on this GPU. It does not prove a target
  of 200 or more overlapping shadowed lights, or a weaker GPU. That is the line
  where a hybrid or stochastic path becomes the better long-term choice.

A new implementation must measure the current renderer with the same paired
method. This table is evidence of scaling, not a final budget.

The old implementation also proves the practical details that matter:

- One BLAS for the cube is enough because every object uses the same mesh.
- A small TLAS rebuild per frame is affordable for this box count.
- `N·L` culling before the ray removes back-facing surfaces.
- The shadow ray must exclude the lamp that emits the light.
- The shadow ray must stop short of a light that sits on a surface.
- A regression scenario can prove both behaviours.

## Recommendation

### Primary design for the documented target

Add hard ray-query shadows to the existing direct-light loop. Do not add a
shadow-map pass, a separate ray-tracing pipeline, or a denoiser. This design is
recommended for the 96-light target that ADR 0029 documents. It is not a claim
that per-light rays fit every future scale.

1. **Build acceleration structures.** Build one BLAS from the cube vertex and
   index buffers at startup. Build the TLAS each frame from the current box
   transforms. Use `PREFER_FAST_TRACE`. Reuse the old code if it still fits;
   otherwise reimplement only the slice the shadows need.

2. **Gate the device.** Require `VK_KHR_acceleration_structure` and
   `VK_KHR_ray_query`, plus their feature bits. `VK_KHR_acceleration_structure`
   also depends on `VK_KHR_deferred_host_operations`. The previous renderer
   enabled all three. [2][3] If the product must run without ray-query hardware,
   stop here and choose the cube-map fallback in
   [#349](https://github.com/eyenalxai/harbagsa/issues/349).

3. **Bind the TLAS.** Add one acceleration-structure descriptor to the scene
   set. The pipeline layout and descriptor set layout must include it.

4. **Trace in the light loop.** After `diffuse > 0`, trace from
   `world_position + normal * 0.002` toward the light. Use `TMin = 0.001` and
   `TMax = max(distance - 0.001, 0.0)`. Use
   `gl_RayFlagsTerminateOnFirstHitEXT | gl_RayFlagsOpaqueEXT`. Multiply the light
   term by zero on a hit.

5. **Use an instance mask for lamps.** Give ordinary boxes a mask that includes
   the shadow-ray bit. Give lamp instances a mask that excludes it. The previous
   build used `0xFF` for boxes, `0x01` for lamps, and `0x02` for the point shadow
   ray. A per-lamp bit is possible if lamp-on-lamp shadows become important, but
   it limits the lamp count to the eight mask bits.

6. **Keep the lamp endpoint clamp.** A lamp on a wall must not shadow itself.
   Keep the one-millimetre endpoint bias and its scenario.

7. **No shadow term for `N·L <= 0`.** The surface cannot see the light. Do not
   trace. The current cluster loop already gives the light list for the pixel.

8. **No per-lamp shadow toggle at first.** Use one renderer debug switch for
   paired evidence. A per-lamp editor flag is a separate product decision.

9. **Measure the shadow work, not just the light count.** Report the shadow rays
   per frame and the paired shadow cost. The light count alone does not predict
   the cost. The per-pixel overlap and the screen coverage do.

The core is small:

```glsl
bool occluded(vec3 origin, vec3 direction, float max_distance, uint mask) {
    rayQueryEXT query;
    rayQueryInitializeEXT(
        query,
        scene_tlas,
        gl_RayFlagsTerminateOnFirstHitEXT | gl_RayFlagsOpaqueEXT,
        mask,
        origin,
        0.001,
        direction,
        max_distance
    );
    while (rayQueryProceedEXT(query)) {}
    return rayQueryGetIntersectionTypeEXT(query, true) !=
           gl_RayQueryCommittedIntersectionNoneEXT;
}

// Inside the clustered light loop, after diffuse > 0:
float visibility = 1.0;
if (occluded(
    world_position + normal * 0.002,
    direction,
    distance - 0.001,
    0x02
)) {
    visibility = 0.0;
}
```

This is the same shape as the Khronos and Arm examples, with the endpoint clamp
from the project's own regression. [1][4][15]

### Why not the alternatives first

- **Cube maps:** the first version would need six depth renders per lamp, a
  filtering kernel, bias controls, and a new render pass. The ray path needs one
  descriptor and one loop. The arena is the case where the ray path is simpler.
- **Virtual shadow maps:** the design target is huge Nanite scenes. The lamps
  move, so the page cache is invalidated. The arena has one mesh. The cost is not
  justified.
- **Soft ray shadows:** the current light is a point. Hard is correct. Softness
  needs a radius and a noise budget that the current renderer does not have.
- **Hybrid:** a hybrid needs a shadow-map base to improve. This renderer has no
  such base.
- **Contact shadows:** screen-space data cannot supply a long shadow from an
  off-screen box.

### Conditions that should change this recommendation

Switch to a hybrid, virtual cube-map shadows, or stochastic direct lighting if
any of these become true:

1. The product must run on GPUs without `VK_KHR_ray_query`.
2. The target moves past the documented 96-light case, especially if 100+ lights
   overlap the same pixels. The measured ray cost becomes the main frame cost.
3. The target GPU is much weaker than the RX 9060 XT and cannot afford the
   measured 2.08 ms at 96 lights at 1080p.
4. The geometry becomes dense or heavily deforming, and the TLAS build or
   traversal cost dominates the frame.
5. Soft area shadows are required at a low ray budget and a denoiser cannot make
   them stable.
6. Alpha-tested or transparent shadow casters become common. Ray query can handle
   them with any-hit work, but the simple opaque path no longer applies.

Switch to ray-query area shadows if the art direction wants penumbrae and the
budget can pay for several rays plus a denoiser. That is
[#350](https://github.com/eyenalxai/harbagsa/issues/350).

Switch to stochastic direct lighting if the target is 100+ dynamic shadowed lights
and per-light work is no longer the right shape. That replaces the direct-light
loop, not just the shadow term, so it is a larger decision than this ticket.

## Evidence plan

The current renderer has no shadow scenarios. The implementation should add
these:

- `scenarios/shadows.json`: place a crate between a lamp and a wall. Capture the
  same camera with shadows on and off. The shadowed capture must be darker in the
  expected region and the render digest must change.
- `scenarios/lamp-wall-plane.json`: restore the old regression. Put a lamp
  halfway into a wall. With shadows on and off, the wall and floor must match.
  A fan of shadow lines fails.
- `scenarios/shadow-move.json`: move the crate or the lamp. The shadow must move
  with it, and the lamp's own housing must not block the light.
- `scenarios/perf-shadows.json`: run the paired test at 8, 32, 64, and 96 lights,
  at 1080p and 1440p. Report the scene pass, GPU total, and shadow rays per frame.
  Run several times and use the median paired difference.
- `scenarios/shadow-taa.json`: settle with a static camera and check that the
  shadow edge does not pulse. Hard shadows should produce no noise.
- `docs/evidence/point-light-shadows.md`: record the commands, the machine, the
  before/after captures, the region statistic, and the paired cost. Do not commit
  images.

The budget and the exact gates are
[#351](https://github.com/eyenalxai/harbagsa/issues/351). This note only names
the evidence the decision needs.

## What this leaves open

- **#349:** set the target scale (the documented 96 lights, or 100+ overlapping
  lights), choose the production path, and decide whether ray-query hardware is a
  requirement or a fallback is needed.
- **#350:** hard point shadows or a finite lamp radius with sampled penumbrae.
- **#351:** the shadow budget, the per-lamp toggle, and the performance and image
  gates.

No shadow code should land before those three decisions close.

## Method and limits

The research used primary sources: Khronos extension references, the Khronos
Vulkan tutorial, Arm's Vulkan ray-tracing path, the original papers, engine
documentation, vendor documentation, and the project's own history.

The scale check ran the last pre-simplification ray-shadow build (`4d7ad86`) on
the same GPU. It used 3 runs per light count, 60 measured frames, and 20 warmup
frames. The paired switch isolates the point shadow rays. The build still had
DDGI and AO, so the absolute frame cost is not current.

Limits:

- The scale check is from an old renderer, not the current one. Re-measure before
  a budget is accepted.
- The synthetic 96-light grid is a dense worst case. A real room may have less
  overlap.
- The hardware evidence is one AMD GPU and one driver.
- Engine documentation describes other engines with different content and
  budgets. It is used for direction, not as a direct performance claim.
- The recommendation is for the documented 96-light target, not every renderer.

## Sources

1. Khronos, *Shadows: Ray Query Integration*, Vulkan Tutorial, SIGGRAPH 2025
   course. <https://docs.vulkan.org/tutorial/latest/Building_a_Simple_Engine/Lighting_Materials/07_shadows.html>
2. Khronos, *VK_KHR_ray_query*, Vulkan Reference Pages.
   <https://docs.vulkan.org/refpages/latest/refpages/source/VK_KHR_ray_query.html>
3. Khronos, *VK_KHR_acceleration_structure*, Vulkan Reference Pages.
   <https://docs.vulkan.org/refpages/latest/refpages/source/VK_KHR_acceleration_structure.html>
4. Arm, *Shadows*, Implement ray tracing effects with Vulkan on Android.
   <https://learn.arm.com/learning-paths/mobile-graphics-and-gaming/ray_tracing/rt07_shadows/>
5. Jakub Bokšanský, Michael Wimmer, Jiří Bittner, *Ray Traced Shadows: Maintaining
   Real-Time Frame Rates*, Ray Tracing Gems, chapter 13, pp. 159-182, Apress,
   2019. <https://doi.org/10.1007/978-1-4842-4427-2_13>
6. Ola Olsson, Markus Billeter, Erik Sintorn, Viktor Kämpe, Ulf Assarsson,
   *More Efficient Virtual Shadow Maps for Many Lights*, IEEE Transactions on
   Visualization and Computer Graphics 21(6), pp. 701-713, 2015.
   <https://doi.org/10.1109/TVCG.2015.2418772>
7. Ola Olsson, Erik Sintorn, Viktor Kämpe, Markus Billeter, Ulf Assarsson,
   *Efficient Virtual Shadow Maps for Many Lights*, Proceedings of the ACM
   SIGGRAPH Symposium on Interactive 3D Graphics and Games (I3D), pp. 87-96,
   2014. <https://doi.org/10.1145/2556700.2556701>
8. Epic Games, *Virtual Shadow Maps*, Unreal Engine 5.7 documentation, accessed
   2026-10-27.
   <https://dev.epicgames.com/documentation/en-us/unreal-engine/virtual-shadow-maps-in-unreal-engine?application_version=5.7>
9. Epic Games, *MegaLights*, Unreal Engine documentation, accessed 2026-10-27.
   <https://dev.epicgames.com/documentation/en-us/unreal-engine/megalights-in-unreal-engine>
10. AMD GPUOpen, *AMD FidelityFX Hybrid Shadows*, accessed 2026-10-27.
    <https://gpuopen.com/fidelityfx-hybrid-shadows/>
11. AMD GPUOpen, *AMD FidelityFX Denoiser*, accessed 2026-10-27.
    <https://gpuopen.com/fidelityfx-denoiser/>
12. Randima Fernando, *Percentage-Closer Soft Shadows*, ACM SIGGRAPH 2005
    Sketches, p. 35, 2005. <https://doi.org/10.1145/1187112.1187153>
13. Elmar Eisemann, Michael Schwarz, Ulf Assarsson, Michael Wimmer,
    *Real-Time Shadows*, A K Peters/CRC Press, 2011.
    <https://doi.org/10.1201/b11030>
14. Epic Games, *Shadowing*, Unreal Engine documentation, accessed 2026-10-27.
    <https://dev.epicgames.com/documentation/en-us/unreal-engine/shadowing-in-unreal-engine>
15. `harbagsa` commit
    [`999df6a`](https://github.com/eyenalxai/harbagsa/commit/999df6af41c5b104eceb628043fef109c9e51baa),
    *feat(renderer): add point lights with hard shadows*, and commit
    [`e10e396`](https://github.com/eyenalxai/harbagsa/commit/e10e3961f3fde084ab02e24ff6149095dfc2ec13),
    *fix(renderer): stop a point shadow ray short of its light*. The regression
    scenario is `scenarios/lamp-wall-plane.json` in the second commit.
16. `harbagsa`, *Performance baseline*, historical TLAS measurement at
    1080p and 1440p, 2026-10-24.
    <https://github.com/eyenalxai/harbagsa/blob/e10e3961f3fde084ab02e24ff6149095dfc2ec13/docs/evidence/perf-baseline.md>
17. Krzysztof Narkowicz, Tiago Costa, *MegaLights: Stochastic Direct Lighting in
    Unreal Engine 5*, SIGGRAPH 2025 Advances in Real-Time Rendering in Games
    course.
    <https://advances.realtimerendering.com/s2025/content/MegaLights_Stochastic_Direct_Lighting_2025.pdf>
18. Song Zhang, Daqi Lin, Chris Wyman, Cem Yuksel, *Many-Light Rendering
    Using ReSTIR-Sampled Shadow Maps*, Computer Graphics Forum 44(2), 2025.
    <https://doi.org/10.1111/cgf.70059>
19. `harbagsa` commit
    [`4d7ad86`](https://github.com/eyenalxai/harbagsa/commit/4d7ad867efa69d369fab11752888b9aa4fad60c2),
    *feat(lighting): remove the sun and keep point lights*. This is the last
    pre-simplification build with clustered forward+ lighting and no fixed light
    cap. The scale check uses it.
