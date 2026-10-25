# Global illumination for interiors with many lights

Research note. No implementation. This note replaces the sun-and-sky assumptions
in [`global-illumination-options.md`](global-illumination-options.md). It covers
the target the owner actually wants: rooms and buildings, no sun, lots of local
lights.

## The short answer

**Yes, DDGI is the leading real-time candidate for this target — but it is the
second problem, not the first.**

The first problem is the eight-light cap. `MAX_ACTIVE_LIGHTS` is 8
(`src/renderer/lights.odin`), and the game uploads the eight nearest lamps
(`src/game/lights.odin`). In a room with more than eight lights, lamps pop in and
out as the camera moves, and a surface lit by the ninth lamp is black. No GI
system fixes that, because the direct light it would bounce is missing.

So the order is:

1. **Make direct light scale.** Clustered forward+ for pixels, and a world-space
   light grid or light BVH for probe rays.
2. **Add DDGI, scoped per room.** Noise-free, off-screen, many lights, dynamic.
3. **Keep a contact term.** DDGI is low-frequency; contact shadows still need AO
   or a short ray.

If the rooms and the lights never move, skip DDGI and bake. A static interior is
the one case where baking beats every runtime method on quality and cost.

## 1. Why the eight-light cap is the real blocker

The current model is a forward pass with a fixed array:

```odin
MAX_ACTIVE_LIGHTS :: 8
```

The game sorts lights by distance to the camera and uploads the nearest eight.
That is a camera-space decision applied to a world-space problem. Two surfaces in
the same room can see different eight-light subsets, so a lamp can light one wall
and not the one next to it. When the camera moves, the subset changes and the
light pops.

The shader also traces a shadow ray per in-range lamp. At eight lights that is
up to eight shadow rays per pixel. At fifty lights it is impossible without a
selection scheme.

**The fix is clustered forward+.** Divide the view frustum into a 3D grid of
clusters (16×9×24 is a common shape), assign each light to the clusters its
volume overlaps in a compute pass, and shade each pixel from its cluster's light
list. This is the standard answer to "many local lights" and it keeps the
forward renderer's strengths
([Olsson, Billeter, Assarsson, HPG 2012](https://www.cse.chalmers.se/~uffe/clustered_shading_preprint.pdf)).
The same paper reports a scene with about 2,400 lights in 17 ms, including 2.3 ms
for clustering and 1.5 ms for light assignment.

Clustering is not unlimited. Godot's Forward+ renderer clusters lights and still
warns that exceeding the per-view clustered-element limit makes lights "pop in
and out during camera movement"
([Godot docs](https://docs.godotengine.org/en/4.4/tutorials/3d/lights_and_shadows.html)).
Budget for the room the player is in, not the whole building.

**For probe rays, use a world-space structure.** Probe rays are not in view
space, so view clusters do not help. A world-space light grid (a hash grid of
light indices) or a light BVH is the right structure. The light BVH is the
production answer for many-light sampling
([Conty Estevez and Kulla, PACMCGIT 2018](https://doi.org/10.1145/3233305)); a
coarse world grid is simpler and enough when lights have a bounded range.

Without one of these, a DDGI probe update that shades each hit against every
light does `rays × lights` work. That is the cost that kills DDGI in a
many-light scene, not the probe storage.

## 2. The GI options for this target

| Option | Dynamic lights | Dynamic geometry | Quality | Cost | Main failure |
|---|---|---|---|---|---|
| Baked lightmaps + irradiance volumes | No, rebake | No | Highest | One fetch | Invalid when a lamp or wall moves |
| Enlighten-style runtime radiosity | Yes, slowly | No | High | CPU, several frames to propagate | Static geometry, slow response |
| DDGI probes | Yes | Yes | Medium, low frequency | 0.22 ms half-res gather + update | Leak, latency, no contact detail |
| Per-pixel one-bounce + light BVH | Yes | Yes | Medium–high, noisy | Rays + denoiser | Noise, fireflies, G-buffer |
| ReSTIR DI / GI | Yes, millions | Yes | High | 8+ ms, 100s of MB | Memory, denoiser, complexity |
| Screen-space GI | Yes | Yes | Low | 0.2–0.4 ms | Blind off screen |

### Baked lightmaps and irradiance volumes

If the building shell and the lights are static, this is the best answer. Light
transport is solved offline, so runtime is a texture fetch and a probe lookup.
There is no leak, no noise, and no light-count limit. The cost is the bake and
the loss of runtime change.

For this project the test is simple: can a lamp be picked up and moved? If yes,
baking is out for the movable lamps, though it still works for the room shell.

### Enlighten-style runtime radiosity

Enlighten precomputes patch-to-patch visibility, then updates lightmaps at
runtime from the current lights. It handles dynamic lights on static geometry. It
is CPU-side and split across frames, so it takes several frames to propagate a
change. Unity's docs describe the trade directly: it suits lights that "change
slowly and have a significant visual impact", such as a slowly pulsing corridor
light, and it takes several frames to propagate
([Unity Enlighten](https://docs.unity.com/en-us/engine/6000.5/manual/lighting-overview/direct-and-indirect-lighting/lightmapping/realtime-gi-using-enlighten/enlighten.md)).

That is a good match for a building with fixed fixtures and a player who moves.
It is a poor match for a lamp the player carries or places every second.

### DDGI

DDGI stores irradiance and depth moments in a probe grid, updates probes with
rays, and samples the eight surrounding probes per pixel. It works with "point,
line, and area lights, skybox lighting, and emissive objects"
([McGuire](https://morgan3d.github.io/articles/2019-04-01-ddgi)), and it is
noise-free because the probe update is the integration, not the pixel.

For an interior with many lights it has three advantages:

- **Pixel cost is independent of light count.** Probes pay the light cost; pixels
  fetch eight probes.
- **Off-screen light works.** A lamp behind the player or in the next room still
  reaches the probe grid.
- **No per-pixel denoiser.** No G-buffer, no motion-vector contract, no 512-frame
  radiance history.

Its three problems are worse indoors than outdoors:

- **Leak.** Every wall is a leak opportunity. The depth-moment test compares a
  distribution, not a solid occluder. A thin wall or a probe near a doorway
  leaks. DDGI's own follow-up paper adds relocation and classification because
  of this, and still reports leaks when probe density is too low
  ([Majercik et al., JCGT 10(2), 2021](https://arxiv.org/abs/2009.10796)).
- **Low frequency.** Probes cannot resolve contact shadows, small fixtures, or
  the shape of a lampshade. Expect a smooth gradient, not detail.
- **Latency.** Hysteresis gives stability and lag. A flickering light or a lamp
  the player moves will smear. Per-texel hysteresis and probe classification
  shorten it; they do not remove it.

### Per-pixel one-bounce with a light BVH

This is the "correct" dynamic answer, and the most expensive. A GI ray hits a
surface, the hit is shaded with a light sample from a light BVH, and a denoiser
cleans the result. It needs a G-buffer, a denoiser, and a light sampler. At fifty
lights it is feasible; at eight lights it is overkill. It is also noisier than
DDGI at the same budget because the pixel, not a probe, carries the variance.

### ReSTIR DI / GI

The high end. ReSTIR DI samples direct lighting from millions of lights with
reservoir reuse and reports equal-error results 6×–60× faster than prior work
([Bitterli et al., SIGGRAPH 2020](https://research.nvidia.com/publication/2020-07_spatiotemporal-reservoir-resampling-real-time-ray-tracing-dynamic-direct)).
It needs ray-traced shadows and a denoiser. ReSTIR GI adds indirect paths. The
memory and denoiser costs from
[`global-illumination-reconstruction.md`](global-illumination-reconstruction.md)
still apply.

### Screen-space GI

Cheap, local, and blind off screen. In a building, the interesting light is
usually through a doorway or around a corner, which is exactly what screen space
cannot see. Not the first choice.

## 3. What a room-scale DDGI looks like

Do not reuse one arena-wide grid. A building needs a volume per room and
corridor, because a regular grid through walls puts probes inside geometry and
leaks across rooms.

| Item | Value | Note |
|---|---|---|
| Room volume | 10×3×10 m | A small room |
| Spacing | 1 m, 0.5 m in corridors | 2.5 m cannot resolve a door or a turn |
| Probes | 10×3×10 = 300 | About 375 KB at 1.25 KB per probe |
| Rays per probe | 64–128 | 19k–38k rays per full update |
| Update | Round-robin, 1/8 to 1/16 per frame | Full refresh in 8–16 frames |
| Gather | 8 probes per pixel, half resolution | About 0.22 ms at 1440p, scaled from the paper |
| Light sampling | World-space light grid or BVH | One light sample per probe ray, not all lights |

The gather estimate comes from the DDGI paper's 0.5 ms at 1080p on an RTX 2080 Ti
([Table 2](https://jcgt.org/published/0008/02/01/)), scaled by pixel count and
then halved. The update is cheap in ray count; the unknown is the direct-light
cost per hit, which depends on the light structure. Measure that first.

**Leak control.** Use per-room volumes, probe relocation out of geometry (at most
45% of the cell), backface rejection, depth moments, and a probe classification
state so probes inside walls or outside the play space do not update. A doorway
should leak: light through a door is transport, not a bug. A wall should not.

**Emissive lamps.** A probe ray that hits a lamp face should return its emission,
not only the point light. That makes the fixture a real GI source. For direct
light, keep the point light as the cheap approximation; for large fixtures, an
area-light sample is better, and next-event estimation is the standard way to
avoid fireflies.

**Contact detail.** DDGI gives the room's fill, not the dark line where a crate
meets the floor. Keep a short ray-traced AO term for contact, but decide what it
multiplies. If it multiplies direct light only, it is the current ADR 0028
behaviour. If it multiplies indirect too, it double counts. One term, one job.

## 4. The recommendation, by case

**Case A — the building shell is static and the lights are fixed or change
slowly.** Bake lightmaps for the shell and an irradiance volume for dynamic
objects. If the lights must change at runtime, use an Enlighten-style radiosity
update instead of a rebake. DDGI is unnecessary. This gives the best interior
quality per millisecond.

**Case B — the lights move, or the player places them.** Use DDGI per room,
after clustered forward+ and a world-space light structure. This is the case the
current game points at: a lamp prefab, placed by the player, in a room. DDGI
handles it without a denoiser, and the probe grid is small enough to fit.

**Case C — the player carries a lamp and the walls are dynamic.** Neither DDGI
nor a bake is ideal. DDGI lags a carried lamp; a bake is invalid. This is the
per-pixel one-bounce + light BVH case, or ReSTIR GI. Accept the denoiser.

**Case D — the light count is in the hundreds and everything moves.** ReSTIR DI
for direct, ReSTIR GI or a path tracer for indirect. This is a different project
budget.

## 5. A phased path

1. **Measure the current frame** with a room that has more than eight lights.
   The eight-light cap will show before any GI work.
2. **Add clustered forward+** and a per-cluster light list. Keep ray-traced
   shadows for the important lights only; use a shadow atlas or a light budget
   for the rest. This alone fixes the popping.
3. **Add a world-space light grid or light BVH** for probe rays.
4. **Add DDGI per room**, 1 m spacing, 64 rays, relocation, depth moments,
   classification. Gate it with a two-room leak test: light in room A, room B
   dark, wall between them.
5. **Add emissive hits** so a lamp face bounces, with a firefly clamp.
6. **Keep a contact term** and decide its target, direct or total.
7. **Build a path-traced reference** for one room and one corridor. Compare
   luminance and colour, not vibes.
8. **Revisit baking** if the lights settle. Static rooms plus dynamic objects is
   the cheapest high-quality configuration.

## 6. The papers and articles to read

1. **Olsson, Billeter, Assarsson, "Clustered Deferred and Forward Shading", HPG
   2012.** The many-light foundation.
   [PDF](https://www.cse.chalmers.se/~uffe/clustered_shading_preprint.pdf).
2. **Conty Estevez, Kulla, "Importance Sampling of Many Lights with Adaptive Tree
   Splitting", PACMCGIT 2018.** The light BVH.
   [DOI](https://doi.org/10.1145/3233305),
   [PDF](https://fpsunflower.github.io/ckulla/data/many-lights-hpg2018.pdf).
3. **Majercik et al., "Dynamic Diffuse Global Illumination with Ray-Traced
   Irradiance Fields", JCGT 8(2), 2019.** DDGI, cost tables, leak limits.
   [JCGT](https://jcgt.org/published/0008/02/01/).
4. **Majercik et al., JCGT 10(2), 2021.** Relocation and classification, the
   parts a room-scale grid needs. [arXiv](https://arxiv.org/abs/2009.10796).
5. **Majercik et al., "Dynamic Diffuse Global Illumination Resampling", SIGGRAPH
   2021.** DDGI plus ReSTIR, for when probe quality is not enough.
   [PDF](https://cim.mcgill.ca/~derek/files/publication-files/majercik-m-uller-keller-nowrouzezahrai-mcguire-dynamic-diffuse-global-illumination-resampling-siggraph-2021-special-interest-group-on-computer-graphics-an-2021.pdf).
6. **NVIDIA, "An Engineer's Guide to Integrating DDGI".** The practical
   integration notes. [Blog](https://developer.nvidia.com/blog/an-engineers-guide-to-integrating-ddgi).
7. **Bitterli et al., "ReSTIR", SIGGRAPH 2020.** Many-light direct sampling.
   [NVIDIA](https://research.nvidia.com/publication/2020-07_spatiotemporal-reservoir-resampling-real-time-ray-tracing-dynamic-direct).
8. **Unity, "Enlighten Realtime Global Illumination".** Precomputed visibility,
   runtime lightmaps, several frames of lag.
   [Docs](https://docs.unity.com/en-us/engine/6000.5/manual/lighting-overview/direct-and-indirect-lighting/lightmapping/realtime-gi-using-enlighten/enlighten.md).
9. **Epic, Lumen technical details.** The shipping hybrid, including the many-light
   and surface-cache side.
   [Docs](https://dev.epicgames.com/documentation/en-us/unreal-engine/lumen-technical-details-in-unreal-engine).

## 7. What did not check out

- **DDGI does not solve the whole problem.** NVIDIA's own integration guide calls
  it the diffuse irradiance component and says it does not resolve visibility and
  occlusion of dynamic elements on its own. It is a bounce term, not a renderer.
- **A grid over a building is not a room-scale grid.** Probes go inside walls,
  and the leak tests pass in the arena and fail in a corridor. Per-room volumes
  are a design requirement, not a tuning step.
- **Clustered shading does not make the light count free.** It makes the per-pixel
  cost proportional to the lights that overlap the cluster, and it still has a
  per-view element budget. Godot's popping warning is the honest version.
- **Enlighten is not real-time in the frame sense.** It spreads the lightmap
  update over several frames. It fits slow changes, not a carried lamp.
- **No source measures DDGI on an RX 9060 XT in a many-light interior.** The
  gather number is scaled from an RTX 2080 Ti at 1080p. The light-shading cost is
  the unknown; measure it before committing.
