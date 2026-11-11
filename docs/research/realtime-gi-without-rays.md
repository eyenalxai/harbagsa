# Real-time GI without stochastic rays: what fits a box arena

**Question.** What real-time or semi-real-time global-illumination techniques exist that do not rely on stochastic path tracing or ray tracing, and how do they compare for harbagsa: a flat, hard-edged box arena with a static one-bounce bake, dynamic direct point lights, and no ambient floor?

**Date.** 2026-11-10

**Status.** Research note. Read-only: no code, build, or commit changes. Sources were checked on 2026-11-10. Claims that could not be verified are marked in **Not found** or inline as "not verified." This note does not change any ADR. The existing bake and the existing hard ray-query shadows are the baseline, not recommendations.

**Constraint used throughout.** "Noise-free" means no Monte Carlo variance: no stochastic sample selection, no random ray directions, no temporal denoising. A technique can be noise-free and still be biased, blocky, or leaky. Those are separate failures and are called out separately.

## Answer

The gap is two gaps, not one:

1. **A dynamic lamp has no indirect.** Its direct light and hard shadows are live, but the light it reflects off a wall never reaches the wall's neighbour.
2. **A moving crate has no indirect.** It receives the baked static probe field, but the light it reflects off its own faces never reaches the floor or the walls.

The static bake cannot close either gap without a rebake, and the bake is about 5 s, so a rebake per frame is not an option. The question is which noise-free transport structure can be added on top without double counting the bake.

The best fit is a **dynamic-only light propagation volume (LPV)** layered on the existing bake. It is raster/compute only: no stochastic sampling, no per-pixel rays, no temporal denoise. It handles both dynamic lamps and moving crates, because both can be injected as deterministic surface samples. At harbagsa scale it should cost roughly 1-2 ms at 0.5 m cells and 2-4 ms at 0.25 m cells, with about 2 MB and 14 MB of volume memory respectively. Those are engineering estimates from the published LPV numbers, not measurements on this renderer. The crucial design rule is **selective injection**: the LPV must exclude static fixtures bouncing off static surfaces, because the bake already contains that term. It should include dynamic lamps on all surfaces, moving crates lit by any source, and static fixtures/static emissive only when their light is reflected by a moving crate.

The cheapest partial fix is different: **promote the N moving crates to a few virtual point lights in the existing clustered direct-light list**, using their reflected flux. That is a one-bounce-from-N-important-objects trick, not a new transport system. It reuses the existing hard shadow ray, adds only 3-18 lights, and should cost well under 0.2 ms. It closes the crate gap but not the dynamic-lamp gap. Use 1-6 samples per crate: 1-4 is the cheap minimum, and 4-6 (one per face or one per visible face) gives a box-shaped bounce instead of a hard point. A single centre point is the worst version of the approximation.

None of the recommended paths adds a new ray-tracing pass. The LPV is raster/compute; the crate VPL reuse is the existing per-light hard shadow test; the bake is the existing offline solve.

The techniques that look attractive but fit poorly here:

- **Screen-space GI (SSDO/SSGI)** is cheap (roughly 0.5-1.5 ms) and deterministic with a fixed kernel, but it only sees what the camera sees. A lamp around the corner, or a crate behind the player, contributes nothing. The arena's hard box edges and thin walls are exactly the cases where screen-space thickness and edge assumptions fail. It is a partial fix for visible cases, not a replacement for the bake.
- **Voxel cone tracing (VCT)** can handle both dynamic lamps and crates and is noise-free for diffuse with a fixed cone set, but it is overkill for a scene with one cube mesh and no specular. At 1080p its published diffuse cost is already several milliseconds on older hardware, and the arena's thin walls are a voxel-leak risk. It does not fit the roughly 2 ms of headroom as comfortably as LPV.
- **Precomputed radiance transfer (PRT)** handles dynamic lamps on static geometry extremely well; The Division shipped exactly that with PRT probes. It does not handle moving crates, because the transfer is precomputed per static surfel. It is a large rewrite of the existing bake for only half the gap.
- **SDFGI** supports dynamic lights but explicitly not dynamic occluders or dynamic emissive surfaces. Moving crates therefore remain a non-contributor. It is a trap for an editable arena.
- **Reflective shadow maps (RSM) and imperfect shadow maps (ISM)** are the historical ancestors of LPV. RSM is noisy or banded at practical sample counts and ignores indirect occlusion entirely; ISM adds approximate visibility but still needs hundreds to thousands of VPLs and a denoising blur. They were superseded for good reasons.
- **Radiance cascades** are genuinely noise-free and do not use temporal reuse, but the shipped implementation is a screen-space, flatland hierarchy for a fixed camera (Path of Exile 2, per the author). A world-space 3D version for a third-person camera is research-grade and unproven.
- **A fixed-ray DDGI probe update** is the obvious full fix and was already implemented in ADR 0042. It measured about 1.29 ms but leaked through thin walls and was replaced by the static bake. Reintroducing it is a ray-based recommendation and repeats a rejected decision; it is listed for completeness, not recommended.

Ranked by how much of the two-gap problem they close; the budget and complexity columns show whether the fix is usable. A full fix that does not fit the roughly 2 ms of headroom is not a drop-in, even when it ranks high on capability.

| Rank | Technique | Dynamic lamps | Moving crates | Fits ~2 ms? | Noise / temporal | Est. runtime here | Est. memory | Integration | Verdict |
|---|---|---|---|---|---|---|---|---|---|
| 1 | Dynamic-only LPV | Yes | Yes | Yes at 0.5 m; tight at 0.25 m | Deterministic; bias only | 1-2 ms at 0.5 m; 2-4 ms at 0.25 m | 2-14 MB | Moderate | Best full fix |
| 2 | Voxel cone tracing | Yes | Yes | No / tight | Deterministic diffuse; fixed cones | 2-5 ms | 2-12 MB at arena scale | High | Full fix, but over budget and overkill |
| 3 | PRT probes | Yes, static receivers | No | Yes | Deterministic runtime | 0.3-1 ms | Large transfer/precompute | High | Half the gap; shipped proof |
| 4 | Screen-space GI (SSDO/SSGI) | Visible only | Visible only | Yes | Deterministic kernel; banding/blur | 0.5-1.5 ms | Depth + colour | Low | Cheap partial; off-screen fails |
| 5 | Crate VPLs in the direct list | No | Yes | Yes | Deterministic | <0.2 ms | Negligible | Low | Cheapest partial; crate-only |
| 6 | SDFGI | Yes | No | No / tight | Semi-real-time; static occluders | 2-5 ms | Cascades | High | Fails the crate gap |
| 7 | RSM / ISM | Yes, noisy | Yes, noisy | Yes / tight | Stochastic/banded; no indirect occlusion | 1-4 ms | Shadow maps | Moderate | Trap for a hard-edged box scene |
| 8 | Radiance cascades (3D) | Unproven | Unproven | No | Deterministic in the paper | 2-6 ms? | High | Research | High risk; 2D shipped only |
| - | Fixed-ray DDGI | Yes | Yes | Yes, but leaks | Deterministic | 1.29 ms measured in ADR 0042 | ~6 MB | Moderate | Excluded: ray-based and previously leaked |

The RSM/ISM row is the one estimate that is not comparable to the 96-light target: RSM's per-receiver VPL sampling does not scale to 96 lights, and the 1-4 ms figure assumes 4-8 dynamic lights. At 96 lights, an RSM per light is not a practical path.

**Practical fit order for harbagsa (budget first, then capability):** 1. LPV (full fix that fits at 0.5 m); 2. crate VPLs (cheap crate-only partial); 3. PRT (lamp-only, high complexity); 4. screen-space GI (visible-only, cheap); 5. VCT (full but over budget); 6. SDFGI (lamp-only, static); 7. RSM/ISM (noisy); 8. radiance cascades (research). The capability table above is deliberately not this order: VCT closes both gaps but does not fit the budget.

The recommended sequence is:

0. Before adding a transport tier, check whether the gap is a product rule. Newly placed lamps default to dynamic (ADR 0045); if a static default plus a visible rebake is acceptable for the player's lamps, that is cheaper than any GI tier. Add LPV only when a lamp must move and still bounce.
1. If the crate gap matters most and the budget is tight, add crate VPLs first. It is a small, deterministic change to the existing direct-light path.
2. If the dynamic-lamp gap matters, add a dynamic-only LPV at 0.5 m first, with a geometry volume and selective injection. Refine to 0.25 m only if the arena's thinnest walls bleed.
3. Keep the static bake. Do not replace it with SSGI, SDFGI, VCT, or PRT. The bake is the high-quality static term; the new system is an additive dynamic term.
4. If the frame budget is already spoken for, accept the gap. The current split is the same kind of split as Enlighten/Frostbite: static geometry carries the bounce, dynamic objects receive from probes and do not contribute much themselves. Enlighten goes further because its static lightmaps are relit by dynamic lights; harbagsa's bake is static. It is still a shipped trade-off, not an oversight.

## Evidence

### 1. Light propagation volumes

**What it is.** LPV, from Kaplanyan and Dachsbacher, stores a low-frequency directional radiance distribution in a lattice and propagates it between neighbouring cells. The published pipeline is: render a reflective shadow map per light; treat every RSM texel as a virtual point light and inject its flux into the lattice; build a coarse geometry volume from the same surface samples; propagate radiance along the six axial directions for a fixed number of iterations; then look up the lattice when shading surfaces. The directional distribution is low-order spherical harmonics: the CryENGINE implementation uses two SH bands, four coefficients per colour channel [1, §3-6].

**Determinism.** This is the important part for harbagsa. The 2010 paper does **not** choose a random subset of RSM texels. It injects the RSM's texels as VPLs and propagates a fixed lattice. The authors describe the result as "stable and flicker-free" and say the method produces "plausible, visually pleasing results without flickering and high temporal coherence" [1, Abstract and §7]. There is no Monte Carlo estimator and no temporal denoiser in the published pipeline. It is deterministic for a fixed grid, fixed RSM resolution, and fixed propagation order.

That does not mean artifact-free. The same paper reports light bleeding through thin geometry, strong blurring/diffusion, and unsteady indirect light from objects smaller than a grid cell. It also says an insufficient RSM resolution can cause flickering [1, §7 and Fig. 11]. "Noise-free" here means no variance, not "correct."

**Cost and memory (published).** The paper renders the Crytek Sponza at 1280x720 on a GTX 285 at 58 fps with three cascades at 50 m, 25 m, and 12.5 m spacing; the indirect computation is about 10 ms. Each cascade is a 32^3 grid, with 8 propagation iterations. A single 32^3 grid costs 3.4-4.2 ms total on GTX 285, Xbox 360, and PS3, of which propagation is 2.4 ms on GTX 285. The LPV memory is 3.75 MB and the geometry volume is 0.75 MB. The RSM is 256^2 on PC (65,536 injected VPLs) and 128^2 on consoles [1, Fig. 1 and Table 1]. The method was integrated into CryENGINE 3, which is the shipped-engine evidence for the technique [1, §6].

**Artifacts.** The 2010 paper's own list is the most useful:

- Light bleeding: light crosses a wall because the lattice and geometry volume are too coarse (Fig. 11, left).
- Strong blurring: "the light strongly diffuses and is not propagated strictly straight ahead" [1, §7]. Later literature often calls the six-axis behaviour anisotropic; the 2010 paper does not quantify anisotropy, so that label is an inference, not a quoted result.
- Small moving objects: if an object is smaller than a cell, its indirect contribution can be unsteady; the authors fade out VPLs from such objects [1, §4].
- Missing blockers: geometry not sampled by the RSM or the camera view is not injected into the geometry volume, so its shadow is missing (Fig. 11, right).

For harbagsa, the box arena is close to LPV's best case: large planar surfaces, few thin occluders, and a closed shell. The failure mode to watch is a wall thinner than about two cells. At 0.5 m cells, a 0.5 m wall is one cell and will bleed; at 0.25 m it is two cells and is much safer.

### 2. Reflective shadow maps and imperfect shadow maps

**RSM.** Dachsbacher and Stamminger's 2005 paper extends a shadow map with depth, world position, normal, and flux, and treats every pixel as an indirect light source [2, Abstract]. The receiver selects a small number of VPLs, roughly 400 in the paper's examples, using an importance-driven polar sampling pattern; the pattern is precomputed once and reused, which gives temporal coherency but can produce banding if the sample count is too low [2, §3-4]. The paper is explicit that it does **not** consider occlusion for the indirect sources: "this is a severe approximation, and can lead to very wrong results" [2, §3]. It also uses screen-space interpolation at low resolution to make the gather affordable.

So RSM is not a noise-free transport method at practical sample counts. It is a deterministic raster plus a stochastic sample pattern (uniform random numbers for the polar sample); reusing one pattern removes frame-to-frame flicker but leaves structured banding. The missing indirect occlusion is fatal in a closed box arena with walls: a VPL on the far side of a wall will light the near side.

**ISM.** Ritschel et al. replace accurate VPL visibility with low-resolution shadow maps rendered from a crude point-based scene representation. The abstract is clear: indirect illumination is smooth enough to tolerate approximate visibility, and the result is "an order of magnitude faster than using accurate visibility" [3, Abstract]. The paper reports 19 fps on a GeForce 8800 GTX for a fully dynamic scene, uses hundreds of ISMs, and selects a fixed random subset of the point set for each ISM; a geometry-aware blur removes the resulting noise [3, §3-4].

ISM is still a VPL method: it needs many VPLs, approximate visibility, and a denoising blur. It is not deterministic in the sense harbagsa needs: the point subset is random, and the blur trades noise for bias. The LPV paper's related-work section says the RSM/ISM family needs hundreds to thousands of VPLs to avoid flicker and temporal incoherence, which is the concise reason it was superseded [1, §2]. VCT later compared against LPV and found LPV suffered more light leaking, while VCT was smoother; both were still approximate [7, §10].

**Why they matter for harbagsa.** RSM is useful as an *injection* mechanism (LPV uses it), not as the final GI. The distinction is the whole point: LPV injects all 65k RSM texels and propagates a lattice, so it has no per-receiver VPL sampling. RSM as a final gather samples ~400 VPLs per receiver and is noisy/banded. That is why the LPV route is the noise-free one.

The general replacement pattern is to move the sampling from the receiver to a volume or a precomputed transfer: LPV injects every RSM texel into a lattice, VCT filters voxels into a hierarchy, and PRT bakes the transfer into coefficients. That removes the per-receiver VPL noise, at the cost of building and maintaining the volume or transfer. It is also why the volume/transfer methods can be deterministic while the VPL methods are not.

### 3. Screen-space GI

The screen-space family is a spectrum:

- **SSAO / HBAO / GTAO** compute a visibility term from depth, not radiance. HBAO uses 4-8 directions and about 6 steps per direction; the SIGGRAPH 2008 slides explicitly rotate the directions by a random per-pixel angle and then note that "randomization generates noise," which is removed with a blur [5, slides "Sampling" and "Noise"]. A deterministic hash makes the pattern reproducible, but the result is still a noisy estimate of the AO integral. GTAO reformulates the horizon integral, matches a ray-traced ground truth at 0.5 ms on a PS4 at 1080p, and adds a near-field GI extension and a specular (GTSO) term. The published 0.5 ms result uses temporal reprojection and spatial filtering: the paper says it integrates "almost 100 samples per pixel while computing only one each frame" [6, Abstract and §5]. A spatial-only GTAO with enough slices is deterministic, but it is not the 0.5 ms configuration.
- **SSDO** generalizes screen-space occlusion to directional occlusion and one diffuse indirect bounce. It runs at 20.4 fps at 1600x1200 on a 537k-polygon scene, uses M sets of N precomputed low-discrepancy samples, and applies a geometry-sensitive blur to remove the noise from using one set per pixel [4, Abstract and §3]. The paper is honest about the failure modes: the result is biased; sources and blockers outside the screen fade out; and a single depth buffer cannot tell whether a sample is behind the first surface or inside a solid object. Depth peeling is the proposed fix, at extra cost [4, §4].
- **SSGI** is the per-pixel radiance version of the same idea. Unity's HDRP documentation describes it as using the depth and colour buffer to calculate diffuse light bounces; when enabled, "SSGI and RTGI replace all lightmap and Light Probe data" [17]. That is a crucial integration warning: in Unity's design SSGI is an alternative to baked GI, not an additive layer. The docs do not claim noise-free single-frame results; production SSGI typically uses spatial and/or temporal filtering.

**Failure modes for harbagsa.** The arena is a closed box with hard edges and thin walls. Screen-space GI fails exactly where the box style is least forgiving:

- Off-screen: a lamp behind the camera or around a corner cannot contribute. This is the case the old DDGI was built for, and it is the case SSGI cannot solve.
- Thickness: a single depth buffer cannot represent the back side of a thin wall; light leaks or is wrongly occluded.
- Edges: at a box edge the screen-space neighbourhood is truncated, so the bounce changes with camera angle. The flat style has no texture or normal map to hide the seam.
- Disocclusion: when the camera turns, previously off-screen sources appear or disappear; a temporal filter smears, and a no-temporal implementation pops.

So SSGI is a useful cheap supplement for visible colour bleeding, but it is not a fix for "dynamic lamps contribute no indirect" in a closed arena. It also risks double counting if it is added on top of the bake without masking static surfaces.

### 4. Voxel cone tracing, SDFGI, radiance cascades, distance-field GI

**Voxel cone tracing.** Crassin et al. build a sparse voxel octree from the scene, inject radiance into the leaves, filter it up the hierarchy, and trace a few wide cones per pixel for diffuse and a narrow cone for specular. The paper reports two bounces for Lambertian and glossy materials at 25-70 fps on a GTX 480, with a 512^3 virtual resolution and nine octree levels. For Sponza at 512^2, indirect diffuse costs 7.8 ms, total direct+indirect diffuse+specular is 22 ms, dynamic octree update is 5.5 ms, initial octree construction is 280 ms, and light injection is 16 ms. The authors allocate roughly 1024 MB of video memory for that scene [7, Abstract and §10, Table 1]. They explicitly claim smooth, temporally coherent results without the noise/flicker of RSM-style final gathering [7, §1-2], and they compare against LPV: LPV 37 ms, VCT 32 ms, ground truth 14m12s; both leak, but LPV leaks more [7, §10, Fig. 12].

VCT is therefore **deterministic for diffuse** in the published pipeline: fixed cones and a fixed voxel grid. The paper does not describe stochastic sampling or temporal accumulation, and it claims temporally coherent results. The cost is the problem. The 7.8 ms figure is at 512^2 on 2011 hardware; at 1080p the pixel count is about four times higher, and even with a modern GPU and half-resolution GI, 2-5 ms is a realistic order of magnitude. The memory figure is not: 1 GB is for a 512^3 virtual scene, while harbagsa's arena at 0.25 m is about 160x20x160 = 512k voxels, roughly 4-8 MB for an RGBA16F volume plus mips. The arena is cheap in memory and expensive in cone-marching time.

VCT's other problem for this scene is that its strengths are high-frequency geometry, glossy reflections, and soft shadows. harbagsa has one cube mesh, flat faces, no specular, and hard shadows. The octree/voxelization/mipmap machinery buys little that LPV does not, and it introduces voxel leaking at thin walls and banding on large flat faces.

**Godot VoxelGI** is a shipped VCT-like engine feature and shows the practical trade-off. The docs call it "fully real-time global illumination" for small/medium scenes, but it requires a bake; after baking, meshes and lights can be marked Dynamic and "will still receive and contribute indirect lighting ... in real-time. This option is much slower compared to Static" [15]. It also warns about light leaks with thin geometry and recommends thickening or hiding blocker meshes [15]. That is a credible shipped data point for "VCT can handle dynamic objects, at a cost and with leaks."

**SDFGI.** Godot's SDFGI is a cascaded signed-distance-field method that marches probes through the distance field. The official docs are unusually clear about the limits: it provides "semi-real-time global illumination"; it "supports dynamic lights, but not dynamic occluders or dynamic emissive surfaces"; it is "one of the most demanding" GI techniques in Godot; it needs static meshes and a camera move away/back to regenerate after a change; and it defaults to one bounce [14]. The "Dynamic" mesh mode is explicitly "not supported with SDFGI" [14].

The docs do not describe a temporal denoiser or a deterministic sample count; they describe a semi-real-time system that regenerates as the camera moves. I did not find a noise-free single-frame guarantee in them.

For harbagsa this is decisive: SDFGI can fix the dynamic-lamp half (dynamic lights are supported), but it cannot fix the moving-crate half, because crates are dynamic occluders. It also conflicts with an editable arena: a static edit requires regeneration, which is the same kind of stale-data problem the project already has, but with a heavier system. It is a trap here.

**Radiance cascades.** Sannikov's manuscript proposes a hierarchy of radiance intervals: near-field cascades have high spatial resolution and low angular resolution, far-field cascades the reverse. It is explicitly designed to avoid the "sparse approximation plus spatiotemporal denoiser" pattern; the paper says its applications "explicitly [do] not rely on temporal reuse" and do not need additional denoising [16, Abstract and §1-2]. It is deterministic in the same sense as a fixed probe/ray set: no stochastic sampling. The paper also states that a practical implementation is integrated into **Path of Exile 2** as its GI solution, using a "flatlandlike screenspace radiance cascade hierarchy" and screen-space raymarching, motivated by the game's fixed camera [16, §1].

That is the catch. The shipped implementation is a 2D screen-space hierarchy for a fixed camera. The paper discusses 3D in the abstract, but I could not find a shipped 3D world-space implementation, a 3D cost measurement, or a peer-reviewed version. For a third-person camera in a 3D box arena, radiance cascades are promising research, not a production recommendation. They also use raymarching, so they are outside the "no rays" spirit even though they are noise-free.

**Distance-field GI more generally.** SDFGI is the main shipped distance-field GI I could verify. I did not find a GI system description in the 2015 Dreams talk, which is about geometry rendering and SDF evaluation; I did not find a primary source that describes Dreams' GI as an SDFGI variant, so I am not citing it as one. A distance-field method's appeal is cheap scene representation and cheap visibility; its weakness is the same as VCT's: voxel/SDF resolution, thin geometry, and the need to update the field for dynamic objects.

### 5. Precomputed radiance transfer

PRT precomputes, for a static object, the linear operator that maps incident low-frequency lighting to exit radiance. At runtime the shading integral becomes a dot product of 9-25 SH coefficients for diffuse receivers, or a small matrix for glossy receivers; view-dependent glossy effects come from applying the transfer matrix and evaluating the reflected direction [8, Abstract]. The 2002 paper also handles dynamic local lighting by sampling the lighting close to the object every frame, and it generalizes self-transfer to neighbourhood transfer so a rigidly moving precomputed object can cast soft shadows and caustics onto dynamic receivers [8, Abstract and §1]. The key restriction is stated in the paper: the object "can only move rigidly, not deform or move one part relative to another" [8, §4.2].

The variants matter:

- **Diffuse SH PRT** is the cheapest: 9 coefficients (Ramamoorthi-Hanrahan irradiance) up to 25 for higher quality; a dot product per vertex/pixel [8, 10].
- **Glossy PRT** uses a transfer matrix, which is view-dependent but much larger [8].
- **Wavelet PRT** (Ng, Ramamoorthi, Hanrahan) approximates all-frequency lighting with a non-linear wavelet basis; it captures sharper shadows than low-order SH but needs more coefficients and a more complex runtime [9].

PRT is deterministic at runtime: the transfer is precomputed, and the runtime is a dot product. The precompute may use Monte Carlo transport, but that is offline and not part of the frame. It is static-geometry-only: the transfer belongs to a fixed object; moving crates cannot contribute new indirect unless they are re-precomputed or represented by dynamic surfels.

**The Division is the shipped proof that PRT can handle dynamic local lights.** Its GDC 2016 talk describes "precomputed radiance transfer probes" for "high-frequency, dynamic light sources." The runtime relights probes every frame on the GPU, accumulating sky visibility plus radiance bricks; local lights are found per sector, evaluated at each surfel, and cached separately when static. The Manhattan data set is 1,156,021 probes and 56,442,867 surfels, 1.07 GB on disk; 600-800 probes are relit per frame at 0.47 ms on a GTX 760 and 0.95 ms on Xbox One [12, slides "Relighting", "Performance", and "Data set"]. The talk's post-mortem is also useful: the initial approach was an irradiance volume updated on the fly with no baking, and it suffered "visible light popping" and was "not suitable for day-night cycle or fast dynamic lighting"; PRT replaced it [12, "Post mortem"].

That is a strong existence proof for dynamic lamps on static geometry, and a strong warning against naive probe relighting. It does not close the moving-crate gap: the transfer and surfels are precomputed for static surfaces; the talk does not claim moving objects contribute new indirect. (This is an inference from the static surfel/probe design, not an explicit statement in the slides; see **Conflicts**.)

### 6. Hybrids in shipped games

The industry has settled on a small number of patterns. They are worth naming because harbagsa already uses one of them.

**Baked GI plus dynamic direct.** This is a common default in Unreal, Unity, and Godot: bake static geometry's indirect into lightmaps or probes, keep direct lights dynamic, and let dynamic objects receive from probes. It is the same shape as harbagsa's current architecture. It is cheap, deterministic, and looks good until a dynamic light or a moving object should contribute indirect. The cost of the gap is a design choice, not a bug.

**Irradiance volumes and probe re-lighting.** The classic irradiance volume (Greger et al. 1998) stores baked diffuse irradiance on a 3D grid and reconstructs it at a surface point [18]. It is a receiver structure, not a transfer. Re-lighting the grid with an analytic lamp evaluates that lamp's **direct** irradiance at the probes, not the lamp's bounce. That is why naive probe relighting pops and can double count; The Division's initial on-the-fly irradiance volume is a production example of the failure [12, "Post mortem"]. A transfer (PRT, LPV, radiosity) is what turns a lamp into indirect.

**Enlighten / Frostbite: dynamic lightmaps plus probes.** Enlighten is a CPU radiosity system with a precompute. Static geometry is parameterised and lit with dynamic lightmaps; dynamic objects sample lightprobes and, the talk says, are typically moving or small and do not affect the lighting much themselves [11, slide 22]. The runtime updates one system per CPU core per frame, and the talk reports radiosity convergence in four frames or less; a typical level precomputes in 10-30 minutes [11, slides 22-25]. The talk also says the lightmap has to be "very clean" because the format is dense: "you can't afford noise" [11, slide 12]. This is the cleanest shipped statement of the split harbagsa uses: static geometry bounces, dynamic objects receive but do not contribute much.

**LPV in CryENGINE 3.** The LPV paper reports integration into CryENGINE 3 [1, §6]. CryENGINE 3 is the engine behind Crysis 2 (2011), but the paper's numbers are engine numbers, not a specific game's shipped settings. This is the canonical "LPV for dynamic lights" example.

**PRT probes in The Division.** As above: dynamic local lights, per-frame probe relighting, static surfels/probes. This is the canonical "dynamic lamps on static geometry without stochastic GI" example [12].

**Dynamic light probes in Forza Motorsport.** Turn 10's GDC Summer 2020 talk is about procedurally placing dynamic light probes for GI in Forza Motorsport, using a CPU dependency graph [13]. I did not find the full talk or its numbers, so I am citing it only as evidence that dynamic light probes for GI are a shipped pattern, not as a performance data point.

**VoxelGI / SDFGI in Godot 4.** Godot ships both a VCT-like VoxelGI and SDFGI. VoxelGI supports dynamic objects and dynamic lights in "Dynamic" mode after a bake, at a much higher cost; SDFGI supports dynamic lights but not dynamic occluders [14, 15]. These are useful shipped counter-examples: the engine that ships the most accessible open-source GI also documents the same limits.

**"One-bounce from N important lights."** I could not find a canonical paper or shipped talk that uses this phrase as a named technique. The shipped form is the pattern above: select the lights that matter, evaluate them at surfels/probes (Enlighten, The Division), or inject their RSM texels into a lattice (LPV), then do one bounce. Treat the phrase as descriptive, not as a citation. The closest paper-level ancestor is RSM's VPL gather, and the closest shipped systems are Enlighten and The Division.

### 7. Comparison to harbagsa

**Current frame budget.** The measured full frame is 5.94 ms with shadows on an RX 9060 XT; the 96-light shadow term alone is 4.29 ms, the TLAS is about 0.30 ms, and the direct term is 1.5-1.9 ms [L1]. The target is 8 ms at 60 Hz, so the headroom is about 2 ms. The static bake and probe terms cost about 0.03 ms per frame [L2]. This budget is the single most important filter: a technique that costs 3-5 ms is not a drop-in, even if it is noise-free.

**What the current system already does well.** The static bake is a high-quality, deterministic one-bounce solve: 1024^2 RGBA16F lightmap, 4 texels/m, 128 cosine rays per texel, one 3x3 binomial denoise, one chart per box face; a 1 m probe grid (40x5x40) with 8x8 octahedral irradiance and depth moments for dynamic boxes; 1024 rays per probe, tetrahedral interpolation, normal bias, facing weight, Chebyshev depth test [L2]. That is a lot of quality for about 0.03 ms of runtime. The right move is to keep it and add a dynamic term, not to replace it.

**Selective dynamic-only LPV design.** This is the concrete proposal that follows from the evidence.

- **Grid.** One 3D grid over the arena. Start at 0.5 m cells: 80 x 10 x 80 = 64,000 cells, two SH bands (four coefficients), RGB FP16. Memory is about 1.5 MB for the radiance and well under 1 MB for the geometry volume. If the thinnest wall is one cell, refine to 0.25 m: 160 x 20 x 160 = 512,000 cells, about 12 MB for the radiance plus about 2 MB for the geometry volume. One grid is enough for a 40 x 5 x 40 m arena; cascades are not needed until the arena grows.
- **Geometry volume.** Voxelise the boxes once for static geometry and each frame for dynamic crates (and optionally the spider). Because every object is the same unit cube scaled/rotated, this is a trivial rasterisation, not a general mesh voxeliser. The static part rebuilds on a static edit; it is cheap and independent of the bake. The geometry volume provides the blocking potential for propagation and the first-hit surface for injection.
- **Injection.** For each dynamic lamp, render a low-resolution cube map (six faces, 128^2 or 256^2) of albedo, normal, and flux; inject every texel as a VPL. This is the point-light adaptation of the paper's per-light RSM injection, and it is deterministic rasterisation, not random sampling. Mask the lamp's own box, as the existing shadow ray does, so the lamp does not light itself. For each moving crate, evaluate the direct light from all sources at its surface samples and inject the reflected flux. The crate is a box, so its surface samples are exact; no random area sampling is needed.
- **Masking.** This is the part that must be right:
  - Static fixture -> static surface: already in the bake; do **not** inject.
  - Static fixture -> moving crate: inject the crate's reflected flux; this is the crate-to-other-surfaces bounce that the bake cannot contain.
  - Static emissive -> static surface: already in the bake; do not inject.
  - Static emissive -> moving crate: inject the crate's reflected flux.
  - Dynamic lamp -> any surface: inject; this is the missing term.
  - Moving crate -> any surface: inject; this is the missing term.
  - Do not inject the crate twice for the same light: if the dynamic-lamp cube map already captures the crate, the crate pass should not also add the dynamic lamp's contribution. One clean split is: dynamic-lamp cube maps capture all surfaces (including crates); the crate pass adds only the crate's reflection of static fixtures/static emissive. That captures each path once.
- **Propagation.** Six axial directions, eight iterations, fuzzy occlusion from the geometry volume, fixed order. This is the LPV paper's scheme [1, §5]. No stochastic sampling.
- **Shading.** Static surfaces: `baked_static_indirect + lpv_dynamic_indirect`. Dynamic boxes: `static_probe_indirect + lpv_dynamic_indirect`. The LPV term is zero when there are no dynamic lamps and no moving crates, so the lamp-free frame stays black.
- **State reporting.** The LPV is independent of the bake key. A stale bake stays stale; the LPV does not make it current. This preserves ADR 0045's rule that a capture must not lie about the indirect data it used.
- **Cost.** The paper's propagation is 2.4 ms for a 32^3 grid with eight iterations on a GTX 285; its finest cascade is 12.5 m over 32 cells, about 0.39 m per cell, so 0.5 m over 80 cells is the same order. A 64k-cell grid is twice the paper's 32k cells, and a modern GPU is much faster, so 1-2 ms is a reasonable order of magnitude for 0.5 m. At 0.25 m the cell count is eight times the 0.5 m grid (not sixteen; 512k / 64k = 8), so 2-4 ms is the range. Injection scales with the number of dynamic lamps and crates; with a cap of 4-8 lamps and 3 crates at 128^2 cube faces, it should be a few tenths of a millisecond. These are estimates, not measurements; measure before committing.
- **Risks.** Light bleeding at walls thinner than two cells; directional smearing on large flat faces; small crates crossing cell boundaries causing a visible step. The first is mitigated by 0.25 m or thicker walls; the second is the LPV look and may be acceptable for soft indirect; the third is mitigated by 0.25 m cells for a crate that is one cell or smaller, or by fading the crate's VPL injection near cell boundaries, which is exactly what the LPV paper does for sub-cell objects [1, §4].
- **Seam.** The bake and the LPV are different resolutions. Additive composition is correct because they carry different sources, but the contact between a lightmap surface and a dynamic crate can still show a step. Capture a static/dynamic contact strip with and without a dynamic lamp before committing; that is the same seam the probe field already has, now with a second dynamic term.

**Cheapest partial: crate VPLs.** If the crate gap is the priority and the lamp gap can wait, add 1-6 VPLs per crate to the existing clustered light list, sampled on the crate's faces. The VPL's flux is the crate's reflected direct light; the existing hard shadow ray provides visibility; mask the crate itself. This is deterministic and adds 3-18 lights for three crates to a 96-light budget; 1-4 VPLs is the cheap minimum, and 4-6 gives a better box-shaped bounce. It should cost well under 0.2 ms. It is the "one-bounce from N important objects" hybrid, using the existing direct-light path rather than a new transport. It does not fix dynamic lamps, and even 4-6 VPLs give a harder, more point-like shadow than a true area bounce; that is the approximation being bought.

**What not to do.**

- Do not replace the bake with SSGI. It loses the off-screen static corner term, and its screen-space leaks can light surfaces the bake would leave black. It will also double count if layered without masking.
- Do not use SDFGI. It cannot accept moving crates as occluders/emitters, and it needs regeneration after edits.
- Do not use RSM/ISM as the final gather. They are noisy/banded and ignore indirect occlusion, which is the exact failure the arena's walls expose.
- Do not use VCT at 1080p on this budget. It is a full fix but costs more than the available headroom, and its strengths are unused.
- Do not use PRT unless the goal is dynamic lamps only and the team is willing to replace the bake with a transfer precompute. It is a large change for half the gap.
- Do not "relight the probe grid from dynamic lamps" by evaluating the lamps directly at the probes. That produces direct light, not a bounce; it double counts and pops. The Division tried an on-the-fly irradiance volume and rejected it for exactly that reason [12, "Post mortem"].
- Do not reintroduce the old DDGI unchanged. It measured 1.29 ms but leaked through thin walls and was replaced for that reason [L3].

## Conflicts

**LPV's DOI and venue.** The author PDF says the definitive version appeared in the 2010 I3D proceedings but prints DOI `10.1145/1507149.1507176`; that DOI resolves to a different I3D 2009 paper ("Granular visibility queries on the GPU"). The ACM/Crossref record for the LPV paper is `10.1145/1730804.1730821`, I3D 2010, pp. 99-107. I cite the ACM record [1]. The mismatch is a metadata error in the author PDF, not a second paper.

**RSM page range.** Crossref lists pp. 203-231, but the author PDF's pages are numbered 203-208 and the last PDF page carries the number 231, apparently from a different article. I cite the DOI and note the range rather than pretending the pagination is clean [2].

**LPV "noise-free" vs. flicker.** The paper claims stable, flicker-free results, and it does not use stochastic sampling. It also says an insufficient RSM resolution can cause flickering and that sub-cell moving objects can cause unsteady indirect light. Both are true: the algorithm has no variance, but it has discretisation error. "Noise-free" in this note means no Monte Carlo variance, not "temporally stable under every input."

**LPV "anisotropy."** The 2010 paper reports strong blurring and non-straight propagation, and the six-axis scheme is inherently direction-dependent. It does not quantify anisotropy, and I did not find a primary measurement of the six-lobed artifact. The term is common in later discussion; treat it as a qualitative description, not a quoted result.

**RSM "deterministic."** RSM uses uniform random numbers to choose polar sample positions, then precomputes one pattern and reuses it. The pattern is fixed, so the output is reproducible; but the estimator is a 400-sample approximation with banding, not a noise-free integral. Calling RSM deterministic is misleading unless "deterministic" means "same pattern every frame."

**GTAO "0.5 ms, noise-free."** The 0.5 ms PS4 number is the spatio-temporal configuration: the paper says it integrates almost 100 samples per pixel while computing one per frame [6]. A spatial-only, no-temporal GTAO is deterministic but needs more slices and does not hit that number. GTAO is also AO, not radiance; with harbagsa's no-ambient-floor rule, AO alone multiplies zero [L4].

**SSGI "replaces lightmaps."** Unity's HDRP documentation says SSGI replaces all lightmap and Light Probe data when enabled [17]. That is a design choice of that pipeline, not a law. For harbagsa, SSGI would have to be masked to dynamic objects or used as an additive visible-only term; otherwise it destroys the static bake.

**SDFGI "real-time."** The Godot docs call it "semi-real-time" and list static-only occluders/emissive surfaces [14]. Marketing or forum descriptions that call it fully real-time are not supported by the official page.

**PRT "dynamic lighting."** PRT supports dynamic low-frequency lighting and, in The Division's probe variant, high-frequency dynamic local lights on static surfels. It does not support dynamic geometry contributing new transfer. The two claims are often conflated. The Division's talk does not explicitly say "moving objects do not contribute"; the static surfel/probe design implies it. The Enlighten talk is explicit about the same split for its own system [11]. I mark the Division inference as an inference.

**Radiance cascades "shipped."** The paper says Path of Exile 2 uses radiance cascades as its GI solution, in a screen-space flatland hierarchy for a fixed camera [16, §1]. I did not independently verify the shipped build, the quality, or the cost. The paper is an unpublished WIP manuscript using the JCGT template; it says so in its own README [16]. It is not peer-reviewed.

**VCT "no noise."** The paper claims smooth, temporally coherent results and no stochastic sampling for diffuse. It also reports light leaking and voxel-resolution limits [7, §10]. "No noise" and "no artifacts" are not the same claim.

**The Division's "PRT probes" vs. classic PRT.** The Division's probes use a transfer basis and radiance bricks; this is a probe-based PRT variant, not the 2002 object-space PRT. It is still a precomputed transfer, but the numbers (1.15M probes, 1.07 GB) are not comparable to a 14 MiB lightmap bake.

**Enlighten's "dynamic objects."** The talk says dynamic objects can only receive bounce light by sampling lightprobes and do not affect the lighting much themselves [11, slide 22]. This is a shipped statement of the limitation, not a claim that dynamic objects are physically correct.

**"One-bounce from N important lights."** No canonical source. The phrase describes a family (Enlighten's point-sampled lights, The Division's local-light surfel evaluation, LPV's RSM injection). Any citation that presents it as a named paper would be invented; I do not.

## Not found

- No primary measurement of LPV in a 40 x 5 x 40 m box arena, and no head-to-head against harbagsa's bake. The 1-2 ms / 2-4 ms figures are extrapolations from the 2010 paper's 32^3 numbers, not measurements.
- No exact cost or memory numbers for Godot SDFGI or VoxelGI in the official docs; they are qualitative ("one of the most demanding," "much slower").
- No shipped 3D world-space radiance-cascade game that I could verify. The Path of Exile 2 claim is the author's, and the described implementation is a screen-space flatland hierarchy for a fixed camera.
- No primary source describing Dreams' GI as an SDFGI or distance-field GI system. The 2015 Advances in Real-Time Rendering talk is about SDF geometry and rendering experiments; I did not find the GI claim in it.
- No verified shipped AAA title using RSM or ISM as the final GI solution. They are research techniques with research-paper results.
- No verified performance number for Enlighten in Frostbite beyond the precompute time (10-30 min) and the four-frame convergence statement.
- No exact LPV light-bleeding or anisotropy measurement. The paper shows the artifacts and describes them qualitatively.
- No exact VCT cost at the arena's 160x20x160 (0.25 m) resolution. The 7.8 ms / 22 ms figures are 512^2 Sponza on a GTX 480.
- No exact cost for the crate-VPL idea. The <0.2 ms figure is an estimate from the 96-light direct budget.
- No canonical "SSGI" paper. It is an engine feature family; I cite Unity's official docs and the SSDO paper for the underlying screen-space one-bounce idea.
- No independent verification of the Path of Exile 2 radiance-cascade claim, and no 3D quality/cost data for radiance cascades.
- No explicit statement in The Division talk that moving objects do not contribute indirect; the static surfel/probe design implies it, but the talk does not say it in one sentence.
- No exact "Crysis 2 used LPV" primary source beyond the LPV paper's statement that the method was integrated into CryENGINE 3. The engine integration is verified; the specific game setting is context.
- No exact HBAO/GTAO shipped title names. GTAO's paper says it was integrated in recent AAA console titles but does not name them; HBAO's slides do not name a game.

## References

Primary sources are marked **[P]** (peer-reviewed paper), **[T]** (industry talk or technical memo, primary but not peer-reviewed), or **[W]** (unpublished manuscript). Official engine documentation is **[D]** (secondary). Local project records are **[L]**.

**Source access.** Full text was read for [1]-[8], [11], [12], and [14]-[17]. [9], [10], and [18] are cited for standard results; their bibliographic metadata was verified, but their full text was not read. [13] is the GDC Vault session page and abstract, not the full talk. [16] is the author's WIP PDF. All metadata was checked via Crossref/DOI or the publisher page on 2026-11-10.

[1] **[P]** Anton Kaplanyan and Carsten Dachsbacher. "Cascaded light propagation volumes for real-time indirect illumination." *Proceedings of the 2010 ACM SIGGRAPH Symposium on Interactive 3D Graphics and Games (I3D 2010)*, pp. 99-107. DOI: 10.1145/1730804.1730821. Author PDF: https://cg.ivd.kit.edu/publications/p2010/CLPVFRII_Kaplanyan_2010/CLPVFRII_Kaplanyan_2010.pdf (accessed 2026-11-10). The author PDF's printed DOI (10.1145/1507149.1507176) is inconsistent with the ACM record; see **Conflicts**.

[2] **[P]** Carsten Dachsbacher and Marc Stamminger. "Reflective shadow maps." *Proceedings of the 2005 Symposium on Interactive 3D Graphics and Games (I3D 2005)*, pp. 203-231 (Crossref; the author PDF's pages are numbered 203-208). DOI: 10.1145/1053427.1053460. Author PDF: https://users.soe.ucsc.edu/~pang/160/s13/proposal/mijallen/proposal/media/p203-dachsbacher.pdf (accessed 2026-11-10).

[3] **[P]** Tobias Ritschel, Thorsten Grosch, Min H. Kim, Hans-Peter Seidel, Carsten Dachsbacher, and Jan Kautz. "Imperfect shadow maps for efficient computation of indirect illumination." *ACM Transactions on Graphics* 27(5), Article 129 (SIGGRAPH Asia 2008), 8 pp. DOI: 10.1145/1409060.1409082. Author PDF: https://www.csie.ntu.edu.tw/~cyy/senior/ISM.pdf (accessed 2026-11-10).

[4] **[P]** Tobias Ritschel, Thorsten Grosch, and Hans-Peter Seidel. "Approximating dynamic global illumination in image space." *Proceedings of the 2009 Symposium on Interactive 3D Graphics and Games (I3D 2009)*, pp. 75-82. DOI: 10.1145/1507149.1507161. Author PDF: https://phaazon.net/media/uploads/SSDO.pdf (accessed 2026-11-10).

[5] **[T]** Louis Bavoil, Miguel Sainz, and Rouslan Dimitrov. "Image-space horizon-based ambient occlusion." *ACM SIGGRAPH 2008 Talks*, Article 1. DOI: 10.1145/1401032.1401061. Slides: https://developer.download.nvidia.com/presentations/2008/SIGGRAPH/HBAO_SIG08b.pdf (accessed 2026-11-10). The slides name Bavoil and Sainz; Crossref lists Dimitrov as a third author.

[6] **[T]** Jorge Jimenez, Xian-Chun Wu, Angelo Pesce, and Adrian Jarabo. "Practical realtime strategies for accurate indirect occlusion." Technical Memo ATVI-TR-16-01, Activision Blizzard, 2016. Presented in the SIGGRAPH 2016 course *Physically Based Shading in Theory and Practice*. PDF: https://www.iryoku.com/downloads/Practical-Realtime-Strategies-for-Accurate-Indirect-Occlusion.pdf (accessed 2026-11-10).

[7] **[P]** Cyril Crassin, Fabrice Neyret, Miguel Sainz, Simon Green, and Elmar Eisemann. "Interactive indirect illumination using voxel cone tracing." *Computer Graphics Forum* 30(7), Proceedings of Pacific Graphics 2011, pp. 1921-1930. DOI: 10.1111/j.1467-8659.2011.02063.x. Author PDF: https://research.nvidia.com/sites/default/files/pubs/2011-09_Interactive-Indirect-Illumination/GIVoxels-pg2011-authors.pdf (accessed 2026-11-10).

[8] **[P]** Peter-Pike Sloan, Jan Kautz, and John Snyder. "Precomputed radiance transfer for real-time rendering in dynamic, low-frequency lighting environments." *Proceedings of SIGGRAPH 2002*, pp. 527-536. DOI: 10.1145/566570.566612. Author PDF: https://www.cs.jhu.edu/~misha/ReadingSeminar/Papers/Sloan02.pdf (accessed 2026-11-10).

[9] **[P]** Ren Ng, Ravi Ramamoorthi, and Pat Hanrahan. "All-frequency shadows using non-linear wavelet lighting approximation." *ACM Transactions on Graphics* 22(3), Proceedings of SIGGRAPH 2003, pp. 376-381. DOI: 10.1145/882262.882280.

[10] **[P]** Ravi Ramamoorthi and Pat Hanrahan. "An efficient representation for irradiance environment maps." *Proceedings of SIGGRAPH 2001*, pp. 497-500. DOI: 10.1145/383259.383317.

[11] **[T]** Sam Martin (Geomerics) and Per Einarsson (DICE). "Radiosity architecture" (Enlighten 2 in Frostbite). *SIGGRAPH 2010 Advances in Real-Time Rendering* course. PDF: https://advances.realtimerendering.com/s2010/Martin-Einarsson-RadiosityArchitecture(SIGGRAPH%202010%20Advanced%20RealTime%20Rendering%20Course).pdf (accessed 2026-11-10). The slide deck has no title slide; the title comes from the course file name. The formal ACM record for the related real-time live demo is: Sam Martin, "Enlighten real-time radiosity," *ACM SIGGRAPH 2011 Real-Time Live!*, Article 1, DOI: 10.1145/2037957.2037960.

[12] **[T]** Nikolay Stefanov. "Global Illumination in 'Tom Clancy's The Division'." *GDC 2016*, Ubisoft Massive. GDC Vault: https://www.gdcvault.com/play/1023273/Global-Illumination-in-Tom-Clancy (accessed 2026-11-10). Slides: https://mrakobes.com/Nikolay.Stefanov.GDC.2016.pdf (accessed 2026-11-10).

[13] **[T]** Diego Garzon. "Adaptive Placement of Dynamic Lighting Probes: Taking Full Advantage of Your CPU Using a Procedural Dependency Graph." *GDC Summer 2020*, Microsoft/Turn 10. GDC Vault: https://gdcvault.com/play/1026866/Adaptive-Placement-of-Dynamic-Lighting (accessed 2026-11-10).

[14] **[D]** Godot Engine documentation. "Signed distance field global illumination (SDFGI)." https://docs.godotengine.org/en/stable/tutorials/3d/global_illumination/using_sdfgi.html (accessed 2026-11-10).

[15] **[D]** Godot Engine documentation. "Using Voxel global illumination." https://docs.godotengine.org/en/stable/tutorials/3d/global_illumination/using_voxel_gi.html (accessed 2026-11-10).

[16] **[W]** Alexander Sannikov. "Radiance Cascades: A Novel Approach to Calculating Global Illumination [WIP]." Unpublished manuscript, 2024. GitHub: https://github.com/Raikiri/RadianceCascadesPaper; PDF: https://github.com/Raikiri/RadianceCascadesPaper/blob/main/out_latexmk2/RadianceCascades.pdf (accessed 2026-11-10). The README states that the paper was never sent to a journal and was never published in JCGT.

[17] **[D]** Unity Technologies. "Screen Space Global Illumination | High Definition Render Pipeline." https://docs.unity3d.com/Packages/com.unity.render-pipelines.high-definition@17.0/manual/Override-Screen-Space-GI.html (accessed 2026-11-10).

[18] **[P]** Gene Greger, Peter Shirley, Philip M. Hubbard, and Donald P. Greenberg. "The irradiance volume." *IEEE Computer Graphics and Applications* 18(2), 1998, pp. 32-43. DOI: 10.1109/38.656788.

[L1] **[L]** harbagsa ADR 0040, "Hard point-light shadows." `docs/adr/0040-hard-point-light-shadows.md`. Measured shadow term 4.29 ms at 1080p for 96 lights, full frame 5.94 ms with shadows, TLAS about 0.30 ms.

[L2] **[L]** harbagsa ADR 0045, "Mixed static baked indirect and dynamic direct light." `docs/adr/0045-mixed-static-baked-indirect.md`. 1024^2 RGBA16F lightmap, 4 texels/m, 128 cosine rays per texel, 3x3 binomial denoise; 1 m probe grid (40x5x40), 8x8 octahedral irradiance and depth moments, 1024 rays per probe; bake about 5 s, artifact about 14 MiB. `docs/evidence/mixed-lighting.md` measures the lightmap+probe terms at 0.025-0.035 ms (mixed 0.028-0.033 ms) at 96 lights and 1080p.

[L3] **[L]** harbagsa ADR 0042, "Single-volume DDGI indirect light." `docs/adr/0042-single-volume-ddgi.md`. Historical record: 64 rays per probe, 1200 probes, about 0.76 ms probe pass plus 0.58 ms gather, about 6 MB for two in-flight buffers; removed after thin-wall leaks.

[L4] **[L]** harbagsa ADR 0041, "Absolute darkness." `docs/adr/0041-absolute-darkness.md`. No ambient floor; AO alone multiplies zero because there is no ambient term.

## Summary for the owner

- The current bake plus dynamic direct is the same kind of split as Enlighten/Frostbite, though Enlighten's static lightmaps are relit by dynamic lights while harbagsa's bake is static. It is a legitimate shipped architecture, and the gap is a deliberate trade-off.
- The only noise-free technique in this survey that closes **both** gaps within the roughly 2 ms of headroom is a dynamic-only LPV layered on the bake. It should fit at 0.5 m; it will be tight at 0.25 m.
- The cheapest useful change is crate VPLs in the existing direct-light list: estimated under 0.2 ms, deterministic, crates only.
- Screen-space GI is cheap but cannot see around corners; it is not a fix for the arena's closed, hard-edged layout.
- VCT, PRT, SDFGI, RSM/ISM, and radiance cascades are either over budget, static-only, noisy, or research-grade for this use. They are worth understanding, not adopting.
