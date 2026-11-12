# Production lighting case studies: how shipped games light without noisy ray tracing

**Question.** How do shipped games and engines architect lighting when they cannot afford noisy ray tracing, and what lessons apply to a small flat-box arena?

**Date.** 2026-11-10

**Status.** Complete. Research snapshot: no code or build changes. The comparison is limited to noise-free architectures: deterministic sampling, baked transport, probe fields, and coarse volumetric approximations. The existing offline bake and hard ray-query shadows are the baseline, not a recommendation. Some cited bakers (Frostbite Flux, Unity's Progressive Lightmapper) are stochastic internally; they are evidence of shipped baked architecture, not a recommendation to add path tracing. The shipped frame is what this document compares: no stochastic noise and no temporal denoise.

**Citation convention.** `[R#]` points to **References**. Section and slide names are quoted from the source. Items marked **secondary** are press, community, or third-party summaries, not the studio or engine vendor. Items marked **inference** are my reasoning from the cited facts, not a claim the source makes.

**Method.** Primary engine docs, GDC/SIGGRAPH talks, papers, and studio interviews were read directly. Press and community sources are used only where labelled, and only for facts the primary source does not publish. Numbers are quoted from the source's own slides or docs, not inferred from screenshots.

---

## Answer

Shipped games do not pick one global-illumination algorithm. They pick a **mutability boundary** and put the expensive transport on the static side of it. Three durable patterns account for nearly everything in the public record:

1. **Fully baked transport.** Quake bakes a per-polygon lightmap on a 16-texel grid and filters it [R1]. Source's VRAD solves radiosity into lightmaps at a typical 4-inch luxel, with Radiosity Normal Mapping tripling lightmap memory [R2]. Unity Baked GI and Unreal Lightmass are the modern general-purpose versions [R6][R10]. Frostbite's Flux is the high-end production version: path-traced spherical-harmonic lightmaps at 25 cm per texel for *Star Wars Battlefront II* [R14].
2. **Baked indirect + real-time direct + probe lookup for dynamic objects.** Unity's Baked Indirect mode renders direct in real time and bakes indirect [R5]. Unreal's Stationary mobility does the same, with Volumetric Lightmaps for dynamic objects [R11][R12]. Frostbite's *Battlefield 3* split geometry into "lightmap lit" (receives and bounces) and "lightprobe lit" (receives only, cannot bounce) [R15]. Guerrilla's Decima uses irradiance volumes for both static and dynamic objects, with four time-of-day bakes [R19]. *The Division* uses precomputed radiance-transfer probes with fully dynamic lights [R16]. Treyarch's baked irradiance-volume system is a volume-based member of the same family [R23].
3. **Real-time, no-ray-tracing approximations.** CryEngine's Light Propagation Volumes [R24][R25], Enlighten Realtime GI [R6][R7], and Godot's VoxelGI and SDFGI [R28][R29]. These ship, but they are coarse, leak-prone, and often get disabled or coarsened on weaker targets. Crysis 2 is the clearest case: the PC version used dynamic GI, but the console versions shipped with it disabled because it still had visible artifacts [R26].

harbagsa is a strict, small instance of pattern 2. Its 25 cm lightmap density matches Frostbite's shipped *Battlefront II* density [R14]. Its 1 m probe grid is denser than *The Division*'s 4 m grid [R16] and matches one of Unity APV's default spacings (1, 3, 9, 27 m) [R30]. Its 5 s bake, 14 MiB artifact, and 0.03 ms indirect term are far below AAA budgets; direct light and shadows remain the dominant cost (1.5–1.9 ms at 96 lights), not the indirect term [in-repo ADR 0045; `docs/evidence/perf-baseline.md`]. The architecture is not the risk. The risks are the known production failure modes of pattern 2: probe leaks at thin geometry, stale indirect being mistaken for current, and "looks right" being judged without a corner/leak/contact test.

The most important lesson is negative: **do not add a dynamic GI system to solve a static-arena problem.** The public record says dynamic no-RT GI buys responsiveness at the cost of coarser transport, new failure modes, and a per-frame budget that baked systems do not pay. It also fails in exactly the thin-wall and small-detail cases a box arena stresses. The evidence-backed lessons are about the split, the bake budget, probe validity, and evaluation. The rest — one bounce, one probe volume, 25 cm texels, no ambient floor — is a defensible scope decision, not a gap to close.

No recommendation below adds stochastic sampling, temporal denoising, a new ray-traced GI pass, or a second GI system. The existing deterministic bake and hard ray-query shadows are the baseline.

---

## Evidence

### 1. Fully baked

#### 1.1 Quake and id Tech's lightmap model

Quake's surface-based lighting preprocesses a lightmap per world polygon, with "a lighting value every 16 texels horizontally and vertically." Abrash puts that grid at "a resolution of two feet in the Quake frame of reference" and notes the preprocessor filters the values so shadow edges do not stair-step. At runtime the polygon texture is lit by the weighted average of the four nearest lightmap points; dynamic lights modify the lightmap before the surface is built [R1].

This is the origin of the pattern: light transport is baked in world space, direct dynamic effects are allowed to perturb the baked result, and the runtime cost is a texture fetch. The cost is baked into level compile time and lightmap memory, and dynamic relighting rebuilds surfaces [R1].

**Scope note.** This covers id Tech 2/Quake only. I did not find a primary id Tech 6/7 lighting architecture talk with GI details; the SIGGRAPH 2016 "idTech 666" slides I checked contain no lightmap/GI content. Do not extend the Quake claim to later id Tech.

#### 1.2 Source, Half-Life 2, Team Fortress 2, VRAD

Valve's SIGGRAPH 2006 course is the primary description of the Source path used by *Half-Life 2*:

- "For Half-Life 2, we leveraged the power of light maps generated by our in-house radiosity solver, vrad" [R2, §8.3].
- A luxel is "typically 4″ by 4″ in our game worlds"; Radiosity Normal Mapping stores three directional lightmap bases and costs "tripling the memory footprint of our light maps" [R2, §8.3.1].
- Characters and other animated models use an **Ambient Cube**: six directional colours per sample, stored in an irradiance volume at a "fairly coarse (4' x 4' x 8') granularity." The nearest sample is selected "without any spatial filtering," and the engine time-averages the ambient/local lighting "to limit the effect of lighting discontinuities" [R2, §8.4.1–8.4.2].
- The ambient cube contains "only bounced or indirect lighting"; direct local lights are added separately [R2, §8.4.3].

The Source SDK's VRAD implementation builds per-face sample and luxel grids and computes a `worldAreaPerLuxel` ratio in `src/utils/vrad/lightmap.cpp` [R3]. That is implementation evidence for the same pipeline, not a second architecture.

**Team Fortress 2.** TF2 is a Source-engine title and inherits the VRAD/lightmap path. I found no TF2-specific lighting technology talk or per-map bake numbers. Treat any TF2 claim here as engine-family inference, not a measured TF2 case study. See **Not found**.

**Source 2.** Valve does not publish a public Source 2 lighting paper that I could verify. The community Source 2 Wiki states that the lightmap is "a single big texture which contains pre-calculated lighting for all the static surfaces," and that *Counter-Strike 2* and *Half-Life: Alyx* rely on lightmapping for level lighting. It also documents **lightmap player space volumes**: the lightmapper assigns the highest resolution to surfaces the player sees up close, with a rule of thumb that close-viewed surfaces should be within 16 units of a volume [R4]. This is **secondary** (community wiki, not Valve), but it is consistent with the Source family's baked model and adds a production lesson: texel density is spatial policy, not a single global number.

#### 1.3 Unity Baked GI, Enlighten, Progressive Lightmapper

Unity separates **Baked Global Illumination** from **Enlighten Realtime Global Illumination**:

- Baked GI stores lighting in lightmaps, Light Probes, and Reflection Probes. It can use the Unity Compute Light Baker or the Progressive Light Baker (Progressive GPU or CPU) [R6].
- The Progressive Lightmapper is "path-tracing-based" and bakes GI "at the lightmap resolution for each texel individually, without upsampling schemes or relying on any irradiance caches." The docs say 100 samples is often enough for outdoor scenes, and bounces are configurable [R9]. The bake is stochastic, but the shipped frame is noise-free; the comparison target is the architecture, not the sampler.
- **Lightmap Resolution** is "the number of texels per unit." Doubling it quadruples texel count. **Directional** mode stores a second dominant-light-direction texture and requires "about twice as much video memory" [R8]. The default maximum lightmap size is 1024 [R8].
- Enlighten Realtime GI splits the scene into surface patches (clusters), precomputes visibility between them, and updates lightmaps at runtime over several frames. It is intended for lights that change slowly, "not ... special effects or Lights that change quickly," and Unity says baked lighting quality "is usually better" [R6][R7]. It also does not support GI from realtime shadows [R6]. The older Enlighten **baked**-GI backend is deprecated; the realtime backend is the one still documented for slow changes [R9].
- Enabling Enlighten Realtime GI and baked GI at the same time "greatly increases baking time and memory usage at runtime, because they do not use the same data sets," and produces visual differences because the two systems operate at different resolutions and use different techniques. Unity says "using both systems is rarely recommended" [R6].

That last point is the clearest vendor statement of the **two-GI-system mismatch problem**: two correct systems do not compose into one correct image if their transport, resolution, and update cadence differ.

#### 1.4 Unreal Lightmass

Unreal's CPU Lightmass "creates lightmaps with complex light interactions like area shadowing and diffuse interreflection" and precomputes the contribution of Static and Stationary lights [R10].

- A **Lightmass Importance Volume** concentrates photons on the playable area. Areas outside it "get only one bounce of indirect lighting at a lower quality" [R10].
- Build time depends on light count, quality mode, level size, and Swarm distribution; the docs say "a few minutes or possibly substantially longer" [R10].
- The quality presets are explicitly time-versus-quality: Production "takes a while," Preview is fast [R10].
- Lightmap UVs are per static mesh, with unique non-overlapping charts and at least four texels of padding to avoid bleed; the **Lightmap Resolution** is per mesh and can be overridden per instance. The **Lightmap Density** view mode visualizes texel density across the level, and packed lightmap atlases are 512–4096 [R38].
- GPU Lightmass is a separate path-traced baker with CPU denoising (Intel Open Image Denoise) [R13]. It is outside the noise-free comparison; CPU Lightmass and the lightmap/VLM architecture are the relevant shipped path here.

#### 1.5 Frostbite's Flux: the modern high-end baked target

Frostbite's GDC 2018 talk describes **Flux**, its in-house lightmap baker, used for *FIFA*, *Madden*, and *Star Wars Battlefront II* [R14].

- Flux is a brute-force unidirectional path tracer with next-event estimation, CPU/Embree, distributed with IncrediBuild XGE, plus a GPU implementation for interactive artist workflows [R14, "Flux method"].
- *Battlefront* targeted ~50 cm per texel; *Battlefront II* targeted 25 cm per texel, "~4x more data" [R14, "Lightmap density"].
- Lightmaps in *Battlefront II* contain **only indirect lighting**; "all direct contributions (except sky) are computed dynamically" [R14, "Lightmap density"].
- The cost is explicit: an 8-megapixel lightmap at 100k rays per pixel is 800 billion rays, ">200 CPU core-hours to bake" [R14, "Why not path tracing?"].
- Storage is explicit: a 4096 x 4096 RGB SH lightmap is 64 MB at 32 bits per texel, 40 MB at 20 bits per texel [R14, "Irradiance SH lightmap encoding"].
- The data is RGB L1 spherical harmonics, 12 coefficients per texel, chosen as "the best compromise of storage footprint, evaluation cost and quality" for 60 Hz 1080p action games [R14, "Why spherical harmonics?"].
- Low-poly proxy geometry is used for baking, and lightmap UVs are projected to all LODs via the Enlighten SDK [R14, "Lightmap density"].

This is the strongest evidence that 25 cm per texel is a shipped AAA density, not an extravagant one. It also shows the real cost of high-quality baked GI: hundreds of core-hours and tens of megabytes per 4K lightmap.

#### 1.6 The bake workflow in practice

The engines differ in tooling, but the stages are the same:

1. **Author static geometry and lightmap UVs.** Quake assigns a lightmap grid per polygon [R1]. Source builds per-face samples and luxels [R2][R3]. Unity generates per-mesh UV charts and packs them into atlases; realtime and baked GI use separate UV sets [R36]. Unreal requires unique lightmap UVs per static mesh with at least four texels of padding [R38]. Frostbite bakes low-poly proxies and projects the UVs to all LODs [R14].
2. **Set density per surface.** Quake uses a 16-texel grid (~2 ft) [R1]; Source uses a typical 4-inch luxel [R2]; Frostbite uses 25 cm/texel for *Battlefront II* [R14]; Unity exposes texels per unit [R8]; Unreal sets **Lightmap Resolution** per mesh and visualizes density across the level [R38]. Source 2 adds player-space volumes so close surfaces get more texels [R4].
3. **Bake and store.** Source's VRAD computes radiosity into lightmaps [R2][R3]. Unity stores the result in a Lighting Data Asset containing lightmaps, probes, and the relationships between them [R37]. Unreal builds lightmaps and places Volumetric Lightmaps over the Lightmass Importance Volume [R10][R12]. Frostbite writes SH lightmaps and probes [R14].
4. **Sample at runtime.** Static surfaces sample the lightmap; dynamic objects sample probes or a VLM [R2][R12][R30]. Direct light and shadows can remain real-time [R5][R11].
5. **Rebake on static change.** Unity's Lighting Data Asset goes out of date when the scene changes [R37]. Unreal previews unbuilt static objects from the VLM until the next build [R12]. Frostbite's *Battlefield 3* precompute is only redone when static geometry changes [R15]. Large productions add distributed, incremental, or bake-what-you-see workflows [R14][R18][R23].

The workflow lesson is that **most of the engineering is authoring and invalidation, not sampling.** The runtime is usually cheap compared with the bake or with a full dynamic GI pass; the differences are in how long the bake takes, how the data is stored, and how the engine tells the team that the data is stale.

#### 1.7 What the fully baked family buys and costs

| Property | Evidence |
| -- | -- |
| Runtime cost | A texture fetch plus interpolation; direct lighting and shadows can stay separate [R1][R2][R5]. |
| Quality | Best diffuse quality and fewest leaks when the bake is dense enough [R6][R27]. |
| Static-only | Geometry and lights must not move, or the bake goes stale [R5][R11][R15]. |
| Authoring cost | Lightmap UVs, chart packing, proxy geometry, bake farms, long iteration [R14][R18][R2]. |
| Memory | 1024² to 4096² atlases; 40–64 MB per 4096² SH lightmap in Frostbite [R14]; Unity warns directional mode roughly doubles memory [R8]. |
| Failure mode | Stale lighting after a static edit; UV/proxy artifacts and self-shadowing; over-coarse indirect [R14][R18][R31]. |

### 2. Mixed: baked indirect + real-time direct

#### 2.1 Unity Mixed lighting modes

Unity's **Lighting Mode** is the clearest published taxonomy of the mixed family. The table is the source for the rows below [R5, "How Unity calculates lighting"].

| Mode | Direct | Indirect | Static shadows | Dynamic objects |
| -- | -- | -- | -- | -- |
| **Baked Indirect** | Real-time | Baked | Real-time up to shadow distance | Light Probes / APV for indirect |
| **Shadowmask** | Real-time | Baked | Baked for static objects, max 4 lights per GameObject | Real-time shadows; probes for indirect |
| **Distance Shadowmask** | Real-time | Baked | Real-time near, baked far | Real-time near; probes for indirect |
| **Subtractive** | Real-time for dynamic, baked for static | Baked | Baked | Real-time, limited to the single strongest directional light for shadows |

Two documented limits matter for architecture:

- Shadowmask stores up to four lights per texel, one per RGBA channel. If more than four lights overlap, "Unity bakes the remaining lights" [R5, "Shadow mask textures"]. This is a hard capacity limit of the mixed-shadow representation.
- Subtractive mode can show a mismatch: "real-time and baked shadows might not blend correctly, because lightmaps don't contain enough data to calculate blending accurately" [R5, "How Unity calculates lighting"].

Unity's Baked Indirect is the closest general-purpose analogue to harbagsa: direct is live, indirect is baked, and static shadows are real-time. The difference is that harbagsa uses ray-query hard shadows instead of shadow maps, and a single lightmap/probe field instead of per-mesh lightmap UVs.

#### 2.2 Unreal Static, Stationary, Movable

Unreal's mobility model is the other canonical mixed design:

- **Static** lights cannot change at runtime; Lightmass bakes direct and indirect into lightmaps [R10][R11].
- **Stationary** lights use "both dynamic direct lighting and static indirect lighting." Direct shadows are shadow maps; indirect lighting and shadowing are baked. The brightness and colour can change at runtime, but "Indirect Lighting cannot be modified without invalidating lighting and needing to be rebuilt," with the exception of intensity and light colour [R11, "Stationary Indirect Lighting on Opaque Materials"].
- Up to four Stationary lights can overlap a single piece of geometry; beyond that, dynamic shadows must take over, with a substantial cost [R11, "Stationary Light Shadowing"].
- Each Movable object creates **two** dynamic shadows from a Stationary light: one for the static world onto the object, and one for the object onto the world. With enough movable objects, a Movable light is cheaper [R11, "Stationary Light Dynamic Shadowing"].
- **Volumetric Lightmaps** provide precomputed indirect lighting to dynamic objects. Lightmass places samples in 4x4x4 bricks over the Lightmass Importance Volume, denser around static geometry, and stores third-order spherical harmonics. Runtime interpolation is per pixel on the GPU [R12, "How It Works"].

The important architectural point: Unreal separates *what can change* (direct light and dynamic shadows) from *what cannot* (indirect transport and static shadowing), and then gives dynamic objects a separate lookup path. That is exactly harbagsa's split.

#### 2.3 Source 2

The public/community Source 2 material only documents the baked side: CS2 and HL:A use lightmapped static level lighting, with player-space volumes controlling luxel density [R4]. I found no verified public description of Source 2's dynamic-object lighting or mixed-light mode. Do not claim one.

#### 2.4 Frostbite Battlefield 3: the split stated explicitly

DICE's GDC 2011 talk is unusually direct about the mixed architecture:

- Geometry is split into **lightmap lit** and **lightprobe lit**. Lightmap-lit geometry is "large and inanimate," "receive[s] and bounce[s] light." Lightprobe-lit geometry is "the character or a dynamic object" and "can only receive light, not bounce or generate additional light" [R15, "Lightmap lit geometry" / "Lightprobe lit geometry"].
- Probes are stored in a grid and use spherical harmonics to store incoming lighting from all directions; dynamic objects pick up the correct lighting as they move through the grid [R15, "Lightprobe volumes"].
- The static geometry precompute for the shown scene "takes about 20 minutes," and only has to be redone when static geometry changes, not when lighting or surface colours change [R15, "Precompute"].
- The runtime pipeline updates lightmaps and probes on the CPU, stores indirect lighting in a separate G-buffer during the geometry pass, then adds deferred direct lights and indirect in the light pass [R15, "Runtime lighting pipeline"].

The last point is the direct analogue of harbagsa's `albedo * (direct + indirect) + albedo * emissive`: indirect is a separate term, direct is live, and dynamic objects only receive the indirect term.

#### 2.5 Double-counting and mismatch: what the sources actually document

There are two separate problems, often conflated:

1. **Double-counting the same light.** If a bake stores direct lighting *and* the runtime also evaluates that light directly, the result is too bright. The safe rule in every mixed system above is: bake only the term you do not also add at runtime. Unity Baked Indirect bakes indirect only [R5]. Unreal Stationary bakes indirect and static shadows, while direct is real-time [R11]. Frostbite *Battlefront II* lightmaps contain only indirect except sky [R14]. harbagsa's ADR 0045 follows the same rule: the lightmap contains static indirect only [in-repo ADR 0045].
2. **Mismatch between two valid representations.** Even without double-counting, a baked indirect term and a live direct term can disagree when the light changes, when a dynamic object crosses a probe boundary, or when two GI systems with different resolutions are combined. Documented examples:
   - Unity Subtractive: real-time and baked shadows may not blend because the lightmap lacks enough data [R5].
   - Unity Enlighten + baked GI: visual differences are expected because the systems use different resolutions and techniques; using both is "rarely recommended" [R6].
   - Unreal Stationary: indirect cannot change without a rebuild; changing intensity or colour does not change the baked indirect shadows [R11].
   - Source: nearest-probe lookup with no spatial filtering causes hard transitions; Valve time-averages to hide the popping [R2, §8.4.2].
   - Frostbite *Battlefield 3*: dynamic objects receive indirect but do not bounce, so they cannot feed the static probe field [R15]. **Inference:** a character therefore never tints the wall next to it.
   - *The Division*: probe bleeding through interior walls required a stencil-selected interior volume [R16, "Interior volume"].

**Inference.** harbagsa's explicit `stale` status is a stronger version of the Unreal/Unity behaviour: the mismatch is not hidden, it is reported. That is a production improvement, not an architectural deviation.

#### 2.6 How the mixed systems handle moving objects and dynamic lights

| System | Static direct | Static indirect | Static shadows | Dynamic objects | Dynamic lights |
| -- | -- | -- | -- | -- | -- |
| **Unity Baked Indirect** [R5] | Real-time | Baked | Real-time | Probes/APV | Real-time direct; no baked indirect update |
| **Unity Shadowmask** [R5] | Real-time | Baked | Baked, max 4 lights | Probes/APV | Real-time direct |
| **Unity Subtractive** [R5] | Baked for static | Baked | Baked | Real-time direct, limited shadows | Real-time direct |
| **Unreal Stationary** [R11] | Real-time | Baked | Baked + per-object dynamic shadows | Volumetric Lightmap | Direct updates; indirect does not |
| **Unreal Movable** [R10][R11] | Real-time | None (Lightmass precomputes only Static/Stationary) | Dynamic | Volumetric Lightmap | Fully dynamic |
| **Frostbite BF3** [R15] | Dynamic | Enlighten radiosity | Dynamic | Probe grid, receive-only | Fully dynamic |
| **harbagsa** [in-repo ADR 0045] | Real-time | Baked one bounce | Ray-query hard shadows | Static probe field, receive-only | Direct only, no indirect |

### 3. Real-time GI without ray tracing in shipped games

#### 3.1 CryEngine Light Propagation Volumes and Crysis 2

The LPV paper describes a fully dynamic, precomputation-free approximation: reflective shadow maps inject virtual point lights into a lattice, low-order spherical harmonics represent the radiance distribution, and an iterative propagation pass moves radiance between cells. It is integrated into CryENGINE 3 and handles nested cascades [R24, §3–6].

The published numbers are impressive and should be read carefully:

- The paper's Sponza figure runs at 58 fps on a GTX 285 at 1280x720 with three cascades of 50/25/12.5 m; "the time required for the computation of the indirect illumination is about 10 milliseconds only" [R24, Figure 1].
- The implementation uses two SH bands (four coefficients per colour channel), 32³ grids, and 3.75 MB for the LPV plus 0.75 MB for the geometry volume [R24, §6].
- Crytek's course slides claim "~1 ms/frame on PlayStation 3" and "stable, flicker-free" [R25, "Conclusion"].

The paper is also honest about the failure modes: grid methods suffer from the "ray effect" (discretized directions produce distracting beams) and from light smearing during repeated propagation; the method is only suitable for low-frequency indirect light [R24, §3]. The slides list multiple bounces as an "unstable solution" [R25, "Comparison"].

The shipped reality is the important correction. *Crysis 2* did not ship the full system on consoles. Digital Foundry quotes Tiago Sousa: "Our innovative real-time GI solution was not fully complete/robust on consoles yet, it still had visible issues/artefacts which we ran out of time to address." The team disabled it on consoles and kept "a very simple and coarse GI approximation ... where our art department fully controls the look" [R26] (**secondary**, direct developer quote). This is the single best evidence that a research-grade dynamic GI technique can be too fragile for a shipping target even when its measured cost is low.

#### 3.2 Frostbite and Enlighten

*Battlefield 3* used Geomerics Enlighten for real-time radiosity on PC and for baking static indirect on consoles. The PC version updated indirect lighting in response to destroyed walls; the console versions baked it. Dynamic objects did not contribute to indirect on either platform and received it by interpolating between regularly spaced light probes using spherical harmonics [R15][R35]; R35 is a **secondary** session summary. DICE's own talk frames the motivation as destructibility: precomputed lightmaps "severely limit the dynamic aspects of game lighting," and the team wanted real-time artist iteration [R15, "HOW: Pre-baked lightmaps"].

Other Frostbite titles use the opposite trade-off for static content: Flux path-traced SH lightmaps at 25 cm per texel, with dynamic direct light layered on top [R14]. This is a useful pattern: the same studio uses dynamic radiosity where destruction demands it, and high-quality baked transport where it does not.

#### 3.3 Guerrilla / Decima

Guerrilla's lead lighting artist describes *Horizon Zero Dawn*'s solution as **irradiance volumes**: "multilayered lightmaps, where each pixel of each layer has a 3D location in space, and multiple directions based on probe positions." They were used "for both our static and dynamic objects, giving us a fully unified way of doing indirect lighting for all objects." The team baked the sun's indirect lighting at four times of day into four sets of irradiance volume textures and blended between them; a separate static indirect volume held non-moving lights; a third bake stored sky visibility as a volumetric AO map [R19].

The stated reason for baking rather than going fully real-time is directly relevant: "the quality is higher, and the memory cost and runtime performance cost is really low compared to a fully real-time solution." The team also valued the ability to add bake-only lights for art direction, and noted that the volume approach removed lightmap UVs and the associated content failures. The cost is tooling: "in challenging situations it needs help placing the probe positions in the right spots. We have hint planes and exclusion zones" [R19].

This is the strongest primary argument that a well-built baked/probe system is a quality choice, not a compromise.

#### 3.4 Naughty Dog

The public record is thinner. Digital Foundry's *Uncharted 4* analysis says the game features "pre-computed global illumination" [R21] (**secondary**). Naughty Dog's SIGGRAPH 2016 technical-art talk distinguishes surfaces with "baked lighting" from "objects with probe lighting (like characters)" when describing AO behaviour [R20]. That confirms both baked lighting and probe lighting are in use, with characters as a probe-lit example, but it does not document the GI algorithm, bake times, or probe layout. Do not overclaim: the exact Naughty Dog GI technique is not in the sources I could verify.

#### 3.5 Ubisoft: AC4, AC Unity, The Division

**Assassin's Creed 4** is the best-documented Ubisoft probe pipeline. Bart Wronski's GDC 2014 notes describe **Deferred Normalized Irradiance Probes**:

- Probes are placed every 2 m, automatically using the navmesh; brute-force placement produced ~110,000 probes per world, navmesh placement ~30,000 [R17, "Number of probes"].
- The bake stores irradiance in four basis vectors per probe, for eight times of day. A full-world bake on a single GTX 680 took "around 8 minutes" [R17, "Full baking time"].
- Runtime cost was ~1.2 ms fullscreen on PS3/X360, ~1.8 ms when combined with the shadow mask; on next-gen/PC the bounce cost was negligible compared with the shadow mask. The CPU update cost ~0.6 ms. Memory for 25 loaded sectors was ~600 KB of VRAM [R17, "Performance cost"].
- The four-vector basis was a known weakness: it lacked a pronounced side bounce, "ground color was leaking a lot to the sides, giving incorrect hue of surrounding objects," and the basis was not orthonormal, so energy was lost or gained by direction. Wronski recommends a cubemap basis or third-order SH for future projects [R17, "Technique worked very well..."].

**Assassin's Creed Unity** used uniform lighting probes at 50 cm spacing across a roughly 4 km² city, with four times of day [R34] (**secondary**, reporting a GDC 2025 talk by Nicolas Lopez). A SIGGRAPH 2017 survey by Colin Barré-Brisebois (EA SEED) puts the data cost at "up to 21+ GB of GI" for ACU and describes the production failure: "move a pillar, have to relight the whole level instead of proximity" [R18, "The Open World Beast" / "When Iteration Fails"]. The same survey lists the common workarounds: GI-only lights, per-object GI parameters, override volumes and planes for leaks, and negative lights [R18, "When Authoring Fails"].

**The Division** is the best-documented shipped PRT system:

- Radiance-transfer probes with surfels, designed for fully dynamic lights (sun, sky, point, spot, area) and a day-night cycle, with no rebake when lights change [R16, "Introduction"].
- Automatic probe placement on a 4 m raycast grid, plus probes spawned on ray hits along building walls "in order to avoid flat-looking surfaces" [R16, "Probe placement"].
- Probes are grouped into 64 m × 64 m sectors, max 1000 probes, typically 200–300; sectors stream in and out with the player [R16, "Sector layout"]. The slide text renders "64m^2"; the stated 200–300 probes at 4 m spacing is only consistent with a 64 m × 64 m cell, not 64 m².
- Baking processes all probes in a sector at once: G-buffer cube maps, CPU surfel clustering, "5-6s per sector." The Manhattan dataset is 1.07 GB, 3,932 sectors, 1,156,021 probes, 56,442,867 surfels [R16, "Baking process"].
- Runtime relights two sectors per frame (600–800 probes): 0.95 ms on Xbox One (non-async) and 0.47 ms on a GTX 760 [R16, "Performance"].
- A stencil-selected interior volume prevents light bleeding through walls; coordinates are clamped for interior rooms [R16, "Interior volume"].
- Postmortem: multiple bounces are "coarsely approximated," causing dark spots; probe placement gaps cause dark spots; the interior/outdoor transition is sharp; the toolset had too many obscure parameters [R16, "Post mortem"].

This is the most direct evidence for harbagsa's probe role: dynamic lights, static transport, streaming sectors, and a hard leak fix. harbagsa is a single-sector, much smaller version.

#### 3.6 Destiny

Bungie's SIGGRAPH 2013 talk documents two relevant pieces:

- A precomputed ambient-occlusion pipeline for global illumination, developed with NVIDIA Research and Peter-Pike Sloan; the AO factor is packed into the G-buffer and applied to lighting [R22, slides 68–69 and the AO section].
- Transparent objects are lit by per-frame light probes: the CPU builds up to 1024 probe points, the GPU builds a low-order SH environment from the sun and all visible transparent-affecting lights, samples shadow cascades, and applies it per pixel. On Xbox 360, with 1024 probes and 50 lights, the cost was "~0.15 ms" [R22, slides 104–113].

The talk does not document the static lightmap/probe bake in the detail needed for a budget comparison. The useful lesson is the probe cost: a per-frame SH probe update for a thousand points can be cheap, but it is a different thing from a baked static probe field. See **Not found**.

#### 3.7 Godot VoxelGI and SDFGI

Godot's own documentation is unusually candid about the trade-offs, and it is a primary engine source:

- **VoxelGI** is "fully real-time" and intended for small/medium scenes. Baking "will take at least a few seconds," usually below 10 seconds for a medium-complexity scene. Dynamic meshes can receive *and* contribute GI, but the Dynamic mode is "much slower." Static meshes must be re-baked after any change. Thin walls leak; the docs recommend making solid surfaces at least one voxel thick, and bias/normal-bias tweaks trade leaks against flatter lighting. Godot renders at most 8 VoxelGI nodes and blends at most 2 per pixel [R27][R28].
- **SDFGI** is "semi-real-time": it supports dynamic lights but **not** dynamic occluders or dynamic emissive surfaces. It converges over ~25 frames by default, can show "splotches" when ray counts are low, shows cascade shifts when the camera moves, and its performance suffers when the camera moves fast. Static geometry changes require the camera to move away and back before the SDF is regenerated [R29].
- **LightmapGI** bakes up to 16 bounces, usually completes in under a minute for a medium scene, and gives "excellent indirect lighting" but is not real-time; dynamic objects receive GI via probes [R27].

Godot's comparison ranks baked LightmapGI's visuals as "good" and explicitly says that if maximizing quality is the goal, baked techniques "will often look better and will result in fewer light leaks" than real-time techniques [R27]. That is a vendor saying the quiet part out loud.

#### 3.8 Treyarch's volumetric GI (a useful non-listed case)

Treyarch's shipped volumetric GI system is a no-ray-tracing alternative worth including because it is a direct competitor to lightmaps:

- GI is stored in a volume texture; reflection probes provide the source radiance, and the system reprojects from existing probes rather than rendering a cube map per voxel. "Render a reflection probe per voxel?" would have been 138 volumes x 40³ voxels x 6 faces = 14,720 minutes (~10 days) [R23, slides "Render a Reflection Probe Per Voxel?" and "In Practice"].
- In practice: 4096 rays per voxel, 15 neighbours considered, missed rays inpainted [R23, "In Practice"].
- Runtime: "Less than 2ms for reflections and GI" [R23, "Pros"].
- Costs: setup time, hard training, lower resolution or more memory, and "beefy dev machines (48Gb RAM and 12Gb VRAM)" [R23, "Cons"].

This is the strongest counterexample to "lightmaps are the only shipped baked option": a volume-based system can work, but it demands heavy tooling and content discipline.

#### 3.9 Summary: what shipped, what broke, what it cost

| Technique | Shipped example | Documented artifacts | Documented cost |
| -- | -- | -- | -- |
| Per-polygon lightmap | Quake [R1] | Static; lightmap resolution/filtering limits | Baked at level compile; runtime texture fetch |
| Radiosity lightmap + ambient cube | Half-Life 2/Source [R2] | Coarse probe transitions; time-averaging to hide popping | 4-inch luxels; 3x memory for RNM; 4'x4'x8' probe grid |
| Baked GI + lightmaps | Unity Baked GI [R6], Unreal Lightmass [R10] | UV/proxy artifacts, stale data, long bakes [R14][R18] | Minutes to hours; 40–64 MB per 4K SH lightmap [R14] |
| Baked indirect + realtime direct + probes | Unity Mixed [R5], Unreal Stationary [R11], BF3 [R15] | Stale indirect, probe leaks, receive-only dynamics | Probe update 0.02–0.95 ms [R12][R16]; data 600 KB–1 GB [R17][R16] |
| Enlighten realtime radiosity | BF3 PC [R15] | Coarse radiosity; dynamic objects receive only [R15] | CPU cluster updates; console versions baked instead [R35] |
| LPV | CryEngine 3 / Crysis 2 PC [R24][R25] | Ray effect, smearing, coarse; unstable multi-bounce | ~1 ms PS3 claim; ~10 ms GTX 285 Sponza; 3.75 MB |
| PRT probes | The Division [R16] | Probe bleeding, dark spots, coarse multi-bounce | 0.47–0.95 ms; 1.07 GB for Manhattan |
| Irradiance volumes | Horizon Zero Dawn [R19] | Probe placement needs hint planes/exclusion zones | Bake farm; low runtime/memory |
| Probe-derived volume GI | Treyarch's shipped GI [R23] | Setup/training/memory; resolution vs memory | <2 ms runtime; 48 GB RAM/12 GB VRAM dev machines |
| Voxel GI | Godot VoxelGI [R28] | Thin-wall leaks, streaks, 8-node limit | Bake <10 s; GPU-heavy |
| SDF GI | Godot SDFGI [R29] | Splotches, cascade shifts, 25-frame convergence | GPU-heavy; fast camera hurts |
| Baked AO + per-frame SH probes | Destiny [R22] | Limited public detail | ~0.15 ms for 1024 probes/50 lights on Xbox 360 |

### 4. Probe workflows

#### 4.1 Unity Adaptive Probe Volumes

Unity's APV is the most complete public description of a modern automatic probe workflow:

- Probes are placed automatically based on geometry density, in **bricks** of 64 probes arranged 4x4x4. Default probe spacing is 1, 3, 9, or 27 m. Each pixel samples the eight closest probes [R30, "How Adaptive Probe Volumes work"].
- Sampling is **per pixel**, not per object, which reduces seams between adjacent GameObjects [R30, "Advantages and limitations"].
- You **cannot** move individual probes inside a volume; the docs say the system may not follow walls or exact lighting boundaries, and recommend settings/overrides to fix artifacts [R30, "Advantages and limitations"].
- Baking is organized into **Baking Sets**; only one Baking Set can be active at a time [R30, "Baking Sets"]. Runtime **streaming** loads cells within the camera frustum; the smallest loaded unit is a cell the size of the largest brick, and disk streaming requires GPU streaming [R33].
- Leak fixes are explicit: thicker walls, a Volume with **Normal Bias** and **View Bias**, **Leak Reduction Mode**, **Rendering Layer Masks** (up to 4), and **Probe Adjustment Volumes** to invalidate or override probes. The docs conclude that Probe Adjustment Volumes solve "most light leak issues, but often not all," and that many of them slow the bake and make the scene harder to maintain [R31].
- Invalid probes (inside geometry) are handled by **Virtual Offset** (move the capture point out of geometry) and **Dilation** (copy data from valid nearby probes) [R31][R32].

**Inference:** automatic placement is not a substitute for leak tooling. Unity ships both, and still tells users to thicken walls.

#### 4.2 Unreal Volumetric Lightmaps

Unreal's VLM is the closest shipped analogue to harbagsa's probe field:

- Lightmass places samples throughout the Lightmass Importance Volume and computes indirect lighting for them. Bricks are 4x4x4 cells, denser around static geometry, and each sample stores third-order SH [R12, "How It Works"].
- Dynamic objects interpolate the VLM **per pixel** on the GPU, instead of the older per-object Indirect Lighting Cache [R12, "Precomputed Lighting on Movable Objects"].
- Cost: "Volumetric Lightmaps on a third person character cost .02ms of GPU time on the PlayStation 4." Memory in Epic's *Paragon* map Monolith rose from 5 MB with the Indirect Lighting Cache to 30 MB with VLM at default detail cell size [R12, "Performance"].
- Failure modes: light leaking through a wall on characters but not static meshes is fixed by decreasing **Detail Cell Size** or increasing wall thickness. Low **Maximum Brick Memory** culls detail bricks, making dynamic indirect less accurate. Level streaming requires all levels, including streamed ones, to be built at the same time [R12, "Troubleshooting" / "Additional Notes"].

#### 4.3 Manual placement, automatic placement, and streaming

| System | Placement | Representation | Runtime | Streaming | Known limits |
| -- | -- | -- | -- | -- | -- |
| **Unity APV** [R30][R31][R33] | Automatic bricks, 1/3/9/27 m | SH, 8 probes/pixel | Per-pixel | Cells, disk/GPU | No manual probe moves; one Baking Set; leaks at walls |
| **Unreal VLM** [R12] | Automatic, denser near geometry | SH3, 4x4x4 bricks | Per-pixel | Levels built together | Memory cap; thin-wall leaks |
| **Source ambient cube** [R2] | Precomputed volume, 4'x4'x8' | 6 directional colours | Nearest sample, time-averaged | None described | Hard transitions; no spatial filter |
| **The Division** [R16] | Automatic 4 m grid + wall hits | PRT surfels / SH | 2 sectors/frame | 64 m × 64 m sectors | Bleeding, dark spots, coarse bounces |
| **AC4** [R17] | Automatic navmesh, 2 m | 4-vector irradiance | Blended, time-of-day | 25 sectors | Basis leaks, energy errors |
| **Guerrilla** [R19] | Baked volumes + hint planes/exclusion zones | Irradiance volumes | Low | Bake farm | Placement help needed |
| **harbagsa** [in-repo ADR 0045] | Fixed 1 m grid | 8x8 octahedral + depth moments, 4-probe tetrahedral | Per-pixel | None | One volume; thin-wall leak risk |

#### 4.4 Common production failure modes and fixes

| Failure | Evidence | Fixes used in production |
| -- | -- | -- |
| **Light leak through thin walls** | Unity APV [R31], Unreal VLM [R12], Godot VoxelGI [R28], The Division [R16] | Thicker walls; normal/view bias; rendering layers; invalidate probes; stencil-separated interior volume; depth moments/facing weight |
| **Probes cannot follow walls** | Unity APV limitation [R30]; The Division spawns probes on wall hits [R16]; Guerrilla uses hint planes/exclusion zones [R19] | Wall-aware placement, denser local grids, manual adjustment volumes |
| **Dark spots where probes are missing** | The Division postmortem [R16] | Auto placement on ray hits, probes on walls, dilation, higher density |
| **Sharp indoor/outdoor transition** | The Division [R16]; Unity APV rendering layers [R31] | Separate interior volume, stencil, rendering layer masks, local overrides |
| **Popping / hard transitions** | Source nearest-sample + time-average [R2]; Godot SDFGI cascade shifts [R29] | Spatial interpolation, time-averaging, denser probes, stable volume bounds |
| **Basis distortion / colour bleed** | AC4 four-vector basis [R17] | Cubemap or SH basis; higher-order SH; octahedral irradiance |
| **Bake iteration pain** | Frostbite >200 core-hours [R14]; BF3 20 min [R15]; SIGGRAPH survey 8+ hour nightly builds [R18] | Distributed bake, incremental bake, bake-what-you-see, short bakes |
| **Stale lighting after a static edit** | Unity Lighting Data Asset [R6]; Unreal VLM preview [R12]; harbagsa ADR 0045 | Versioned artifacts, explicit status, rebuild prompts |
| **Memory blow-up** | The Division 1.07 GB [R16]; ACU 21+ GB [R18]; Frostbite 64 MB per 4K SH map [R14] | Compression, streaming, density by importance, lower resolution away from player |

#### 4.5 Artist tools

The sources converge on a small set of tools that matter more than the probe math:

- **Density control by importance.** Source 2 player-space volumes [R4], Unity APV local volumes [R30], Unreal VLM detail-cell size and density volumes [R12], later Assassin's Creed titles' artist-painted GI density map [R34] (**secondary**), and Guerrilla's hint planes/exclusion zones [R19].
- **Leak overrides.** Unity Probe Adjustment Volumes and rendering layer masks [R31]; The Division's interior stencil volume [R16]; the SIGGRAPH survey's "override volumes and planes" [R18].
- **Debug views.** Unity's Rendering Debugger for APV cells [R33]; Unreal's Volumetric Lightmap visualization [R12] and Lightmap Density view mode [R38]; Source 2's `mat_luxels` [R4]; harbagsa's diagnostic views and renderer state.
- **Bake status.** Unity's Lighting Data Asset can go out of date [R6]; Unreal previews unbuilt lighting from the VLM until rebuild [R12]; harbagsa's `.hbake` key/status is the most explicit of the three.

The postmortems also warn about tool complexity: *The Division* team said multiple lighting and weather parameters had "obscure effects" and the interface needed to be as simple as possible [R16, "Ease of use"]. Treyarch lists "training is hard" as a con [R23, "Cons"]. **Opinion:** a small team should copy the debug views and status, not the parameter surface.

### 5. Small-scope lessons

#### 5.1 Decision tree

1. **If the geometry is static and the bake is short, bake the transport.** This is the dominant shipped choice for static worlds: Quake, Source, Unity Baked GI, Unreal Lightmass, Frostbite Flux, Guerrilla [R1][R2][R6][R10][R14][R19]. Evidence-backed.
2. **If direct light must stay live, bake indirect only.** Unity Baked Indirect and Unreal Stationary both do this; Frostbite *Battlefront II* lightmaps contain only indirect [R5][R11][R14]. Evidence-backed.
3. **If dynamic objects must match, add a probe lookup.** Frostbite BF3, Unity APV, Unreal VLM, The Division, Source ambient cube [R15][R30][R12][R16][R2]. Evidence-backed.
4. **If lights move but geometry does not, either exclude those lights from indirect or precompute transfer.** Excluding them is what Unreal Movable and harbagsa do; precomputed transfer is what Enlighten and The Division do, at the cost of runtime relight and tooling [R11][R16][R7]. Evidence-backed.
5. **If geometry moves or destructs, you need rebake or dynamic GI.** For a small arena, rebake is cheaper; for a city, dynamic/streamed probes are the only practical option [R16][R18]. Evidence-backed, with a scale caveat.
6. **If the bake exceeds the iteration budget, reduce rays/resolution or add importance density before adding dynamic GI.** Long bakes damage production: a SIGGRAPH industry survey describes 8+ hour nightly GI builds and "move a pillar, relight the whole level" [R18]. Evidence-backed.
7. **If the scene is a flat-box arena, one bounce and no ambient floor are legitimate.** The first is a look decision; the second is a closed-arena scope decision. Neither is found as a standard shipped configuration, so treat them as **opinion**, supported by the in-repo evidence, not by the external case studies.

#### 5.2 Budgets that the evidence supports

| Budget | harbagsa | Shipped reference | Reading |
| -- | -- | -- | -- |
| Bake time | ~5 s | BF3 20 min precompute [R15]; Frostbite >200 core-hours for an 8 MP/100k-ray map [R14]; Division 5–6 s per sector [R16]; AC4 8 min for a world/8 TOD [R17]; Godot VoxelGI <10 s, LightmapGI <1 min [R27] | harbagsa is at the fast end. 5 s is a good iteration budget; the 2 s target is not worth a quality regression. |
| Artifact memory | ~14 MiB | Frostbite 64 MB per 4096² SH map [R14]; Unreal VLM 30 MB for Paragon [R12]; Division 1.07 GB [R16]; AC4 600 KB for 25 sectors [R17]; ACU up to 21+ GB [R18] | harbagsa is small. 32 MiB is a sane ceiling for one arena. |
| Runtime indirect | ~0.03 ms | Unreal VLM 0.02 ms per character [R12]; Division 0.47–0.95 ms [R16]; Treyarch <2 ms [R23]; LPV ~1 ms PS3 [R25]; AC4 1.2 ms last-gen [R17] | harbagsa is at the low end. The 8 ms frame budget is not threatened by indirect. |
| Lightmap density | 4 texels/m = 25 cm | Frostbite 25 cm [R14]; Source ~10 cm [R2]; Quake ~61 cm [R1] | harbagsa matches a shipped AAA density and is coarser than Source. Do not increase without a specific artifact. |
| Probe spacing | 1 m | AC Unity 0.5 m [R34] (**secondary**); Unity APV 1/3/9/27 m [R30]; The Division 4 m [R16] | harbagsa is denser than The Division, within APV's range. 1 m is defensible for a 40 m arena. |
| Bounces | 1 | Godot LightmapGI up to 16 [R27]; Frostbite path traced [R14]; Guerrilla primary + secondary [R19] | One bounce is low, but the flat-box look hides the difference. Opinion: keep one bounce unless a specific corner reads wrong. |
| Probe data | 8x8 octahedral + depth | Unreal SH3 [R12]; Unity APV SH [R30]; AC4 4-vector [R17]; Division PRT/SH [R16] | harbagsa's octahedral+depth is closer to DDGI than to shipped SH probes, but the role is the same. The depth test is a leak fix that shipped engines also need. |

**Important caveat.** These numbers are not apples-to-apples. Frostbite's 200 core-hours is an 8 MP lightmap at 100k rays per texel; harbagsa's 5 s is a 1024² atlas at 128 rays per texel. Godot's <1 minute is a medium-complexity scene at unknown resolution. Use the numbers to locate harbagsa's order of magnitude, not to declare a winner.

#### 5.3 How to decide between baked, mixed, and dynamic GI

A practical rule set, with the evidence separated from the judgement:

- **Baked** when the world and lights are static and the look depends on bounce light. Evidence: Quake/Source/Unity/Unreal/Frostbite/Guerrilla [R1][R2][R6][R10][R14][R19].
- **Mixed** when direct light or shadows must respond to gameplay but the environment does not move. Evidence: Unity Baked Indirect, Unreal Stationary, BF3 [R5][R11][R15].
- **Dynamic** when the world or lights change enough that a rebake is impractical, and you can tolerate coarse, leak-prone indirect. Evidence: Crysis 2 PC, The Division, Enlighten, VoxelGI/SDFGI [R26][R16][R7][R28][R29].
- **Do not choose dynamic GI for a static arena just to avoid a 5 s bake.** This is **opinion**, but it follows from the cost/quality evidence: dynamic systems are coarser, leak more, and are the first thing cut on weaker targets [R26][R27][R29].

#### 5.4 Does it look right? Tests worth running

harbagsa already has the harness for this; the external case studies say what to look for. The existing `lighting-quality`, `lighting-wall`, `lighting-seam`, `lighting-missing`, and `bake-lifecycle` scenarios cover most of the list below [in-repo `docs/evidence/mixed-lighting.md`]. **Opinion:** add only the thin-wall and colour-bleed cases; do not build a new test framework.

1. **Corner darkening / contact grounding.** Compare the indirect term on and off. harbagsa's own evidence: frame mean 80.92 with the bake versus 73.07 direct-only; the fraction of exactly-black pixels falls from 23.06% to 1.17% [in-repo `docs/evidence/mixed-lighting.md`]. External analogue: Unity's APV leak docs call out corners of walls and ceilings as the place leaks show [R31]; Unreal's VLM troubleshooting calls out leaks through a wall on characters [R12]; Godot ranks LightmapGI's indirect as "excellent" [R27].
2. **Hard contact shadows.** harbagsa's shadow test: floor region inside the crate shadow is mean 54.62 with shadows versus 93.41 without [in-repo `docs/evidence/mixed-lighting.md`]. This is the direct-light baseline that the bake must not smear.
3. **Colour bleed.** Put a saturated albedo box near a white wall and check the hue in the corner. AC4's four-vector basis leaked ground colour to the sides and distorted hue [R17]; that is the failure to test for. Frostbite uses RGB L1 SH precisely to keep chroma-separated directional lighting [R14].
4. **Leak through a sealed wall.** harbagsa's ADR 0042 records a sealed-wall test where no light crossed the wall [in-repo ADR 0042, "Measurement"]. External practice: Unity says thicken walls and use normal/view bias/rendering layers [R31]; Unreal says decrease detail cell size or thicken the wall [R12]; Godot says make surfaces at least one voxel thick [R28]; The Division uses a stencil interior volume [R16].
5. **Dynamic object match.** Move a crate from a lit spot to a shadowed spot and compare the probe-lit crate against the static floor. harbagsa's `crate-moved` capture shows the shadow moves while the bake stays `current` [in-repo `docs/evidence/mixed-lighting.md`]. External: BF3's probe-lit dynamic objects receive but do not bounce [R15]; Unity APV's per-pixel sampling reduces GameObject seams [R30].
6. **Stale bake visibility.** Move or remove a static fixture; direct light should change immediately, and the bake should report `stale` while the old indirect remains bound. harbagsa's `lamp-removed` capture does exactly this [in-repo `docs/evidence/mixed-lighting.md`]. Unreal's closest behaviour is previewing unbuilt lighting from the VLM until rebuild [R12]; Unity's Lighting Data Asset can go out of date [R6]. harbagsa is stricter because it reports the key.
7. **Determinism.** Same static input, same artifact. harbagsa's ADR 0045 hashes the canonical static input and tool version and reports `current`/`stale`/`missing`/`failed` [in-repo ADR 0045]. Many external bakers are stochastic or denoised and do not contract for bit-identical output across runs, so this is a harbagsa-specific strength.
8. **Budget.** Measure the indirect term in isolation at 1080p and 96 lights. harbagsa's evidence says ~0.03 ms; the 8 ms budget is dominated by direct light and shadows, not GI [in-repo ADR 0045 and `docs/evidence/perf-baseline.md`].

#### 5.5 What to copy, what is overkill

**Copy (evidence-backed):**

- The static/dynamic split: bake what cannot move, keep direct and shadows live [R5][R11][R15][R19].
- A probe path for dynamic objects if they must match the room [R12][R15][R30].
- A visible bake status/version, because stale indirect is the normal failure [R6][R12] and harbagsa already has a stronger version [in-repo ADR 0045].
- Leak/corner/contact tests in the capture harness [R31][R12][R28].
- Density by importance only if a specific surface reads flat [R4][R30][R12][R19].
- A bake budget tied to iteration, not to a headline benchmark [R18][R15][R16].

**Overkill for a single 40 m arena (opinion, with evidence of cost):**

- APV-style streaming and Baking Sets: useful for open worlds [R33], pointless for one volume.
- Unreal VLM's brick memory caps and adaptive density: useful for large levels [R12], unnecessary at 40x5x40.
- Enlighten/LPV/SDFGI/VoxelGI: they solve dynamic geometry/lighting that harbagsa deliberately excludes; they bring leaks, convergence, and cascade artifacts [R26][R28][R29].
- 0.5 m uniform probes over a city [R34]: harbagsa's 1 m grid is already denser than The Division's 4 m.
- Multi-bounce, weather, time-of-day, specular lightmaps, SH specular: all are visible in AAA pipelines [R14][R19], but they serve looks and scale harbagsa does not have.
- Distributed/incremental baking: harbagsa's 5 s bake does not justify the machinery that Frostbite, Ubisoft Massive, and Epic need [R14][R16][R10].

### 6. Comparison to harbagsa

#### 6.1 Where harbagsa is conventional

| harbagsa choice | Concrete shipped analogue | Evidence | Assessment |
| -- | -- | -- | -- |
| Static lightmap indirect + realtime direct + hard shadows | Unity Baked Indirect [R5]; Unreal Stationary [R11]; Frostbite BF3 [R15] | Same split; shadows differ (ray query vs shadow maps) | The majority architecture for static worlds. |
| Dynamic objects sample a static probe field | Frostbite BF3 probe-lit geometry [R15]; Unreal VLM [R12]; Unity APV [R30]; Source ambient cube [R2] | Dynamic objects receive, do not bounce | Conventional. The receive-only limitation is shared. |
| Static fixtures contribute direct + baked indirect | Unity Mixed / Unreal Stationary [R5][R11] | Direct live, indirect baked | Conventional. |
| Dynamic lamps contribute no indirect | Unreal Movable [R11]; BF3 dynamic objects [R15] | Direct only; no baked transport | Conventional for dynamic lights. |
| Static emissive boxes feed the bake but are not direct lights | Godot treats emissive materials as a form of area lighting in GI [R27] | Baked emitter, not a punctual light | Conventional; emissive geometry is a GI input, not a light source. |
| One probe volume for one arena | Unity APV one Baking Set [R30]; Unreal one VLM [R12]; harbagsa one volume | No streaming/cross-volume blending | Appropriate at this scale. |
| 25 cm lightmap density | Frostbite *Battlefront II* 25 cm/texel [R14] | Same order of magnitude | Shipped AAA density. |
| 1 m probe spacing | Unity APV 1/3/9/27 m [R30]; The Division 4 m [R16]; AC Unity 0.5 m [R34] (**secondary**) | Between APV and Division | Defensible; denser than Division. |

The hard-shadow path is one ray query per light per fragment against a per-frame TLAS. It is not a GI technique and does not change the comparison; it is the direct-light/shadow baseline that the bake must not duplicate or smear.

#### 6.2 Where harbagsa is unusual

| harbagsa choice | Closest shipped practice | Evidence | Reading |
| -- | -- | -- | -- |
| **One bounce** | Frostbite path traced multi-bounce [R14]; Guerrilla primary + secondary [R19]; Godot LightmapGI up to 16 [R27] | Shipped bakes usually do more | Deliberate low end. Fine for flat boxes; the risk is a corner that needs a second bounce to read. |
| **No ambient floor** | Most shipped engines have a sky/ambient term; Unity has environment lighting [R6], and Guerrilla's dynamic skylight plus baked sky visibility is one shipped example [R19] | Guerrilla bakes sky visibility; Unity has environment lighting | Scope difference: the arena is closed and the owner rejects a constant fill. Not evidence of a flaw, but it makes shipped "look right" references less transferable. |
| **Explicit stale status with old artifact bound** | Unreal previews unbuilt lighting from VLM [R12]; Unity Lighting Data Asset can be out of date [R6] | No shipped engine in this set exposes a key/status exactly like harbagsa | Stronger than shipped practice; keep it. |
| **One 1024² atlas, one chart per box face** | Source uses per-face lightmaps and UV charts [R2]; Frostbite uses proxy UVs and atlases [R14] | harbagsa avoids UV unwrapping by deriving face UVs | A scope simplification; it also avoids the UV-seam failure mode that Unity/Frostbite spend tooling on. |
| **Static probe field with octahedral irradiance + depth moments** | Unreal VLM SH3 [R12]; Unity APV SH [R30]; AC4 4-vector [R17]; Division PRT [R16] | harbagsa's representation is closer to DDGI than to shipped SH probes | Unusual but not exotic; the depth test is a leak fix, not a quality feature. |
| **No streaming** | Division streams 64 m × 64 m sectors [R16]; Unity APV streams cells [R33]; Unreal builds all levels together [R12] | One arena fits in memory | Correct omission. |
| **5 s full rebake, no incremental** | Frostbite distributed XGE [R14]; industry survey nightly builds [R18]; Treyarch incremental [R23] | AAA bakes are much longer | 5 s is fast enough that incremental machinery would cost more than it saves. |

#### 6.3 Concrete shipped analogues, ranked by closeness

1. **Frostbite *Battlefield 3*.** The closest architectural match: lightmap-lit static geometry that receives and bounces, lightprobe-lit dynamic geometry that only receives, dynamic direct lights, and a static precompute that only changes when geometry changes [R15]. harbagsa differs in transport (deterministic one-bounce bake vs Enlighten radiosity) and shadows (ray query vs shadow maps).
2. **Unity Baked Indirect + APV.** The closest general-purpose engine match: direct real-time, indirect baked, probes/APV for dynamic objects, explicit mixed-light modes [R5][R30]. harbagsa differs by using one probe volume and a face-local lightmap atlas rather than per-mesh UVs.
3. **Unreal Stationary + Volumetric Lightmaps.** The closest probe-role match: baked indirect for static surfaces, per-pixel SH probe interpolation for dynamic objects, dynamic direct light and shadows [R11][R12]. harbagsa's 1 m grid and depth-moment test are a smaller, hand-rolled version of the same idea.
4. **Guerrilla / Decima.** The closest quality argument: irradiance volumes for static and dynamic objects, four time-of-day bakes, static indirect plus sky visibility, and a stated preference for baked quality over real-time cost [R19]. harbagsa is a single-volume, single-time-of-day, closed-arena reduction of that.
5. **The Division.** The closest dynamic-light probe system: PRT probes, 4 m auto placement, sector streaming, stencil leak fix, 0.47–0.95 ms [R16]. harbagsa is the static-light, single-sector, much smaller cousin.
6. **Source / Half-Life 2.** The closest cheap-probe ancestor: 4-inch lightmaps, RNM, and a 4'x4'x8' ambient cube with nearest-sample lookup and time-averaging [R2]. harbagsa replaces the ambient cube with octahedral irradiance and tetrahedral interpolation, but the role is the same.

#### 6.4 Gaps worth closing (opinion)

These are the only places where the external evidence suggests a concrete improvement that fits the existing architecture:

- **Leak regression tests at thin geometry.** harbagsa already has a sealed-wall test [in-repo ADR 0042], but the probe field's 1 m grid and depth test are exactly the configuration Unity/Unreal/Godot warn about. Add captures with a 0.1–0.2 m wall and a probe on each side; measure the backside. This is evidence-backed by the failure modes in [R31][R12][R28].
- **A corner/contact/colour-bleed capture set.** The current evidence covers shadow on/off, indirect on/off, dynamic lamp, stale bake, and missing bake. A dedicated capture that puts a saturated box beside a white wall would catch basis/hue problems like AC4's [R17]. This is evidence-backed by AC4 and Frostbite's SH choice [R14].
- **Density-by-importance only if a specific surface reads flat.** Source 2's player-space volumes [R4] and Unity APV's local volumes [R30] are the shipped pattern. For one arena, a single global density is probably enough; add a local override only when a capture shows a flat wall, not preemptively.
- **Keep the bake status in the capture/render digest.** harbagsa already does this; the external lesson is that stale lighting is normal and must be visible [R6][R12]. Do not weaken it for convenience.
- **Budget the bake at 5 s, not 2 s.** The 2 s target in ADR 0045 is below the measured 5 s. The external evidence says iteration speed matters [R18], but 5 s is already faster than every AAA reference here except Godot's VoxelGI. Do not trade quality for 3 s.

#### 6.5 Gaps not worth closing (opinion)

- **Do not add LPV/SDFGI/VoxelGI/Enlighten.** They solve dynamic geometry/lighting; harbagsa's static arena does not need them, and the evidence shows they are coarser and leak more [R26][R28][R29].
- **Do not add streaming or Baking Sets.** One arena fits in memory; streaming is an open-world solution [R33].
- **Do not add a second GI system.** Unity explicitly warns that mixing Enlighten and baked GI produces visual differences and is rarely recommended [R6]. harbagsa has one system; keep it.
- **Do not add multi-bounce or specular lightmaps.** The flat-box look does not need them; the shipped cases that use them serve outdoor/open-world looks [R14][R19].
- **Do not chase 50 cm probes or 10 cm texels.** harbagsa is already at Frostbite's 25 cm and denser than The Division's 4 m probes; the next quality gain is more likely in leak/corner handling than in raw density.

---

## Conflicts

1. **Crytek's LPV claims vs Crysis 2's shipped console build.** The slides claim "~1 ms/frame on PlayStation 3" and "stable, flicker-free" [R25], while the paper reports about 10 ms for the Sponza scene on a GTX 285 [R24, Figure 1]. *Crysis 2* then disabled the full GI on consoles because it "still had visible issues/artefacts" and shipped a "very simple and coarse GI approximation" instead [R26] (**secondary**). The conflict is between a research demo's best case and a shipping game's robustness bar. For harbagsa, the lesson is to trust the shipped outcome, not the technique's best-case cost.
2. **Baked quality vs dynamic flexibility.** Guerrilla says baked irradiance volumes have higher quality and much lower runtime/memory than a fully real-time solution [R19]. Unity says baked GI quality is "usually better" than Enlighten Realtime GI [R6]. Godot says baked techniques often look better and leak less [R27]. Against that, Enlighten/LPV/SDFGI exist because dynamic worlds cannot rebake [R7][R24][R29]. There is no factual contradiction: the systems optimize different constraints. The conflict is one of emphasis: each source presents its preferred trade-off as the default.
3. **Basis choice.** AC4's four-vector basis leaked ground colour and lost/gained energy; Wronski recommends cubemap or third-order SH [R17]. Frostbite chose RGB L1 SH (12 coefficients) as the best compromise [R14]. Source chose a six-colour ambient cube as more concise than nine-colour SH and cheaper to evaluate [R2]. These are different points on the storage/quality/evaluation curve, not a single correct answer.
4. **Probe density.** AC Unity used 50 cm uniform probes [R34] (**secondary**); The Division uses 4 m probes with wall hits [R16]; Unity APV defaults to 1/3/9/27 m [R30]; Unreal VLM uses adaptive bricks around geometry [R12]. There is no standard because scene scale, memory, and leak tolerance differ. harbagsa's 1 m is not "wrong" by any of these standards.
5. **Bake time headlines.** Frostbite's ">200 CPU core-hours" is an 8 MP lightmap at 100k rays per texel [R14]; Godot's "<1 minute" is a medium-complexity scene at unknown resolution [R27]; harbagsa's 5 s is a 1024² atlas at 128 rays per texel. Comparing these numbers without resolution/ray counts is meaningless. The honest comparison is order of magnitude and iteration feel.
6. **What "baked" means.** In Unity, baked GI stores radiance in lightmaps, while Enlighten Realtime GI bakes visibility/clusters and relights at runtime [R6][R7]. Unreal bakes radiance into lightmaps and irradiance into the VLM [R10][R12]. *The Division* stores radiance-transfer probes and relights them every frame [R16]. In harbagsa, the bake stores final indirect radiance, so a static fixture change requires a rebake. All are called "baked," but only the transfer variant supports changing lights without a rebake. Do not assume harbagsa can relight like *The Division* without changing the data contract.
7. **Ambient floor.** Most shipped engines have a sky/ambient term or a constant environment [R6][R19]. harbagsa explicitly has none. This is a scope difference, not a conflict: the arena is closed and the owner rejected a constant fill. It does mean that shipped "look right" references, which assume ambient fill, do not transfer directly.
8. **Naughty Dog's public detail.** Digital Foundry says *Uncharted 4* uses "pre-computed global illumination" [R21] (**secondary**), but Naughty Dog's SIGGRAPH technical-art talk only distinguishes baked surfaces from probe-lit characters [R20] and does not document the GI algorithm. Do not infer a specific technique from the press description.

---

## Not found

- **Team Fortress 2-specific lighting talk, bake numbers, or texel density.** TF2 is Source-engine, but I found no public TF2 lighting technology presentation. The Source claims in this document are engine-family claims, not TF2 measurements.
- **Valve Developer Community wiki pages** (`Lightmap`, `VRAD`). They were blocked by an anti-bot interstitial when fetched. I did not cite them. The Source claims use Valve's SIGGRAPH 2006 course [R2] and the Source SDK code [R3] instead.
- **Official Valve Source 2 lighting documentation or a Source 2 lighting paper.** Only the community Source 2 Wiki [R4] was available; it is labelled secondary.
- **Primary Assassin's Creed Unity GDC slides or recording** for its probe spacing and time-of-day count. The 50 cm/4 TOD figures come from GameSpot's report of a later Ubisoft talk [R34], labelled secondary. The AC4 GDC notes [R17] are primary but describe the previous game.
- **A Naughty Dog GI technical talk with bake times, probe layout, or runtime cost.** The SIGGRAPH technical-art talk [R20] is tangential; Digital Foundry [R21] is secondary and only says "pre-computed global illumination."
- **Destiny's static GI bake/probe specification.** The SIGGRAPH 2013 talk [R22] documents baked AO and per-frame SH probes for transparents, not the full static lightmap/probe pipeline.
- **Exact Unity/Unreal bake times and texel densities for named shipped projects.** The docs give settings and qualitative guidance, not per-project numbers. The numbers in this document are from Frostbite, Ubisoft, Crytek, Treyarch, and Guerrilla, which published them.
- **Frostbite Battlefield 3's runtime radiosity cost in milliseconds.** The GDC 2011 slides describe the pipeline and the 20-minute precompute, but not a per-frame radiosity timing.
- **Unreal Volumetric Lightmap runtime cost beyond "0.02 ms per character on PS4."** No broader budget was published in the docs I verified.
- **Guerrilla/Decima probe counts and bake wall-clock times.** The interview describes the four time-of-day bakes and the render farm, but does not publish probe counts or bake duration [R19].
- **Unity Adaptive Probe Volume artifact size and runtime memory numbers.** The docs describe streaming and cells, but do not publish a per-scene memory figure I could verify [R30][R33].
- **A shipped game using Godot VoxelGI/SDFGI as a flagship case study.** Godot's docs are engine documentation, not game postmortems; I did not find a named shipped title with measured bake/runtime numbers.
- **A shipped game with harbagsa's exact combination**: one bounce, no ambient floor, 25 cm face-local lightmap, 1 m octahedral probe grid with depth moments, hard ray-query shadows, explicit stale status. The analogues are architectural, not identical.
- **id Tech 6/7 lighting architecture details.** The SIGGRAPH 2016 "idTech 666" slides I checked do not cover GI/lightmaps. The Quake claim is id Tech 2 only.
- **Half-Life 2/Quake per-level VRAD/light bake times.** The sources describe the pipeline, not per-map wall-clock numbers.

---

## References

Primary means the studio, engine vendor, or paper author. Secondary means press, community, or third-party summary. All URLs accessed 2026-11-10.

- **[R1]** Michael Abrash, "Quake's Lighting Model: Surface Caching," *Graphics Programming Black Book*, chapter 68 (originally Dr. Dobb's). Primary historical account. https://www.bluesnews.com/abrash/chap68.shtml
- **[R2]** Valve Corporation, "Shading in Valve's Source Engine," SIGGRAPH 2006 Advances in Real-Time Rendering course, chapter 8. Primary. https://cdn.cloudflare.steamstatic.com/apps/valve/2006/SIGGRAPH06_Course_ShadingInValvesSourceEngine.pdf
- **[R3]** Valve Corporation, Source SDK 2013, `src/utils/vrad/lightmap.cpp`. Primary implementation. https://github.com/ValveSoftware/source-sdk-2013/blob/3300848d/src/utils/vrad/lightmap.cpp
- **[R4]** Source 2 Wiki, "Using Lightmap Player Space." Secondary (community wiki; not affiliated with Valve). https://www.source2.wiki/EngineTools/HammerEditor/Lighting/lightmapPlayerSpace
- **[R5]** Unity Technologies, "Lighting Mode," Unity 6.6 Manual. Primary. https://docs.unity3d.com/Manual/lighting-mode.html
- **[R6]** Unity Technologies, "Global illumination," Unity 6.6 Manual. Primary. https://docs.unity.com/en-us/engine/6000.6/manual/lighting-overview/direct-and-indirect-lighting/lightmapping/choose-a-lighting-setup
- **[R7]** Unity Technologies, "Introduction to Realtime Global Illumination using Enlighten," Unity 6.6 Manual. Primary. https://docs.unity.com/en-us/engine/6000.6/manual/lighting-overview/direct-and-indirect-lighting/lightmapping/realtime-gi-using-enlighten/enlighten
- **[R8]** Unity Technologies, "Lightmapping settings in the Lighting Settings Asset reference." Primary. https://docs.unity3d.com/Manual/Lightmaps-reference.html
- **[R9]** Unity Technologies, "The Progressive Lightmapper," Unity 2021.2 Manual. Primary. https://docs.unity3d.com/2021.2/Documentation/Manual/progressive-lightmapper.html
- **[R10]** Epic Games, "Lightmass Basics," Unreal Engine 5.7 documentation. Primary. https://dev.epicgames.com/documentation/en-us/unreal-engine/lightmass-basics-in-unreal-engine
- **[R11]** Epic Games, "Stationary Light Mobility," Unreal Engine 5.7 documentation. Primary. https://dev.epicgames.com/documentation/en-us/unreal-engine/stationary-light-mobility-in-unreal-engine
- **[R12]** Epic Games, "Volumetric Lightmaps," Unreal Engine 5.7 documentation. Primary. https://dev.epicgames.com/documentation/en-us/unreal-engine/volumetric-lightmaps-in-unreal-engine
- **[R13]** Epic Games, "GPU Lightmass Global Illumination," Unreal Engine 5.8 documentation. Primary; noted only as the path-traced/denoised alternative outside this comparison. https://dev.epicgames.com/documentation/en-us/unreal-engine/gpu-lightmass-global-illumination-in-unreal-engine
- **[R14]** Yuriy O'Donnell (Electronic Arts/Frostbite), "Precomputed Global Illumination in Frostbite," GDC 2018. Primary. Slides: https://media.contentapi.ea.com/content/dam/eacom/frostbite/files/gdc2018-precomputedgiobalilluminationinfrostbite.pdf · Talk: https://www.gdcvault.com/play/1025434/Precomputed-Global-Illumination-in
- **[R15]** Kenny Magnusson (DICE), "Lighting You Up in Battlefield 3," GDC 2011. Primary. https://media.contentapi.ea.com/content/dam/eacom/frostbite/files/gdc11-lightingyouupinbattlefield3.pdf
- **[R16]** Nikolay Stefanov (Ubisoft Massive), "Global Illumination in Tom Clancy's The Division," GDC 2016. Primary. Talk: https://www.gdcvault.com/play/1023273/Global-Illumination-in-Tom-Clancy · Slides (third-party host): http://mrakobes.com/Nikolay.Stefanov.GDC.2016.pdf
- **[R17]** Bart Wronski (Ubisoft), "Assassin's Creed 4: Road to next gen graphics," GDC 2014 speaker notes. Primary. https://bartwronski.com/wp-content/uploads/2014/03/ac4_gdc_notes.pdf
- **[R18]** Colin Barré-Brisebois (Electronic Arts SEED), "A Certain Slant of Light: Past, Present and Future Challenges of Global Illumination in Games," SIGGRAPH 2017 Open Problems in Real-Time Rendering course. Primary industry survey. https://colinbarrebrisebois.com/wp-content/uploads/2022/06/siggraph2017-acertainslantoflight.pdf
- **[R19]** Guerrilla Games, "Horizon Zero Dawn: Interview With the Team," 80.lv, 2018. Primary studio interview; lighting section with Roderick van der Steen. https://80.lv/articles/horizon-zero-dawn-interview-with-the-team
- **[R20]** Waylon Brinck and Andrew Maximov (Naughty Dog), "The Technical Art of Uncharted 4," SIGGRAPH 2016 Production Session. Primary, but tangential to GI. https://www.realtimerendering.com/advances/other/2016/naughty_dog/NaughtyDog_TechArt_Final.pdf
- **[R21]** Digital Foundry, "Tech Analysis: Uncharted 4: A Thief's End," 2016. Secondary. https://www.digitalfoundry.net/articles/digitalfoundry-2016-uncharted-4-thiefs-end-tech-analysis
- **[R22]** Natalya Tatarchuk (Bungie), "Destiny: From Mythic Science Fiction to Rendering in Real-Time," SIGGRAPH 2013. Primary. https://advances.realtimerendering.com/s2013/Tatarchuk-Destiny-SIGGRAPH2013.pdf
- **[R23]** JT Hooker (Treyarch), "Volumetric Global Illumination at Treyarch," SIGGRAPH 2016 Advances in Real-Time Rendering course. Primary. https://advances.realtimerendering.com/s2016/Volumetric%20Global%20Illumination%20at%20Treyarch.pptx
- **[R24]** Anton Kaplanyan and Carsten Dachsbacher, "Cascaded Light Propagation Volumes for Real-Time Indirect Illumination," I3D 2010, pp. 99–107. Primary. https://dl.acm.org/doi/10.1145/1730804.1730821 · Author PDF: https://cg.ivd.kit.edu/publications/p2010/CLPVFRII_Kaplanyan_2010/CLPVFRII_Kaplanyan_2010.pdf
- **[R25]** Anton Kaplanyan (Crytek), "Real-time Diffuse Global Illumination in CryENGINE 3," SIGGRAPH 2010 Global Illumination Across Industries course slides. Primary. https://cgg.mff.cuni.cz/~jaroslav/gicourse2010/giai2010-07-anton_kaplanyan-slides.pdf
- **[R26]** Digital Foundry, "The Making of Crysis 2," 2011, page 3, with direct quotes from Tiago Sousa (Crytek). Secondary. https://www.digitalfoundry.net/articles/digitalfoundry-the-making-of-crysis-2?page=3
- **[R27]** Godot Engine documentation, "Introduction to global illumination." Primary. https://docs.godotengine.org/en/stable/tutorials/3d/global_illumination/introduction_to_global_illumination.html
- **[R28]** Godot Engine documentation, "Using Voxel global illumination." Primary. https://docs.godotengine.org/en/stable/tutorials/3d/global_illumination/using_voxel_gi.html
- **[R29]** Godot Engine documentation, "Signed distance field global illumination (SDFGI)." Primary. https://docs.godotengine.org/en/stable/tutorials/3d/global_illumination/using_sdfgi.html
- **[R30]** Unity Technologies, "Introduction to Adaptive Probe Volumes," Unity Manual. Primary. https://docs.unity3d.com/Manual/urp/probevolumes-concept.html
- **[R31]** Unity Technologies, "Troubleshooting light leaks in Adaptive Probe Volumes in URP." Primary. https://docs.unity3d.com/Manual/urp/probevolumes-troubleshoot-light-leaks.html
- **[R32]** Unity Technologies, "Troubleshooting dark blotches or streaks in Adaptive Probe Volumes in URP." Primary. https://docs.unity3d.com/Manual/urp/probevolumes-troubleshoot-artefacts.html
- **[R33]** Unity Technologies, "Optimize loading Adaptive Probe Volume data," Unity 6.6 Manual. Primary. https://docs.unity.com/en-us/engine/6000.6/manual/lighting-overview/lighting/probevolumes/streaming
- **[R34]** GameSpot, "The Hidden Tech That Makes Assassin's Creed Shadows Feel More Alive (And Not Require 2TB)," 2025, reporting a GDC 2025 talk by Nicolas Lopez (Ubisoft). Secondary. https://www.gamespot.com/articles/the-hidden-tech-that-makes-assassins-creed-shadows-feel-more-alive-and-not-require-2tb/1100-6532659/
- **[R35]** Wolfire Games, "GDC session summary: Battlefield 3 Radiosity," 2011. Secondary (session summary), but it records the PC/console split of the Enlighten system. https://www.wolfire.com/blog/2011/03/GDC-session-summary-Battlefield-3-Radiosity/
- **[R36]** Unity Technologies, "Introduction to Lightmap UVs." Primary. https://docs.unity3d.com/Manual/LightingGiUvs.html
- **[R37]** Unity Technologies, "Lighting Data Assets," Unity 6.6 Manual. Primary. https://docs.unity.com/en-us/engine/6000.6/manual/lighting-overview/direct-and-indirect-lighting/lightmap-data/lightmap-snapshot
- **[R38]** Epic Games, "Understanding Lightmapping in Unreal Engine," Unreal Engine 5.7 documentation. Primary. https://dev.epicgames.com/documentation/en-us/unreal-engine/understanding-lightmapping-in-unreal-engine

**In-repo evidence cited.** `docs/adr/0042-single-volume-ddgi.md`, `docs/adr/0045-mixed-static-baked-indirect.md`, `docs/evidence/mixed-lighting.md`, and `docs/evidence/perf-baseline.md`. These are first-party measurements and decisions, not external case studies.
