# Hard point-light shadows

> The ambient floor is removed by [ADR 0041](0041-absolute-darkness.md). The shadow decision otherwise stands.

The lit pass traces one ray query per clustered point light. A hit removes that lamp's contribution. The renderer has no shadow map, denoiser, or soft-shadow sampling. Ray-query hardware is required.

## Why

- Direct point lights crossed walls and crates. The owner asked for shadows.
- The scene has one cube mesh, so one BLAS serves every box and a TLAS follows the current transforms.
- A point light has no area. A hard edge is the correct visibility result for that light model and fits the flat box look.
- The long-term target is interiors with many lights. The renderer keeps one shadow path for every clustered lamp instead of a hero light or a fixed light cap.
- The measured shadow term is 4.35 ms at 1080p for a dense 96-light grid on the RX 9060 XT. The full frame is 6.23 ms with shadows on and 1.65 ms with them off. The TLAS pass is about 0.27 ms. This fits 60 Hz, but it is a real budget.

## Considered Options

- **Cube shadow maps with PCF or PCSS**: six faces per point light, depth bias, cube seams, and a filtering kernel. This is the portable fallback, but it is more code and more per-light state than the measured target needs.
- **Virtual shadow maps**: a large page/cache subsystem, designed for Nanite-scale worlds and hundreds of lights. The published many-light version is credible, but it is too much machinery for this renderer today.
- **Stochastic direct lighting**: the current production answer for 100+ dynamic shadowed lights. It replaces the direct-light loop and needs a denoiser. The 96-light target does not justify that rewrite yet.
- **Soft ray-query shadows**: needs a lamp radius, several rays per light, temporal accumulation, and usually a separate denoiser. That is a later light-shape decision.
- **Screen-space contact shadows**: cannot supply a long shadow from an off-screen box. It is not a complete visibility term.

## Decisions

- Require `VK_KHR_acceleration_structure`, `VK_KHR_ray_query`, and `VK_KHR_deferred_host_operations`, plus buffer device address, acceleration structure, and ray query features.
- Build one BLAS from the cube vertex and index buffers. Build one TLAS each frame from all current box transforms while shadows are enabled. Grow the instance capacity with the box count.
- Add a TLAS pass before the cluster pass. Time it as its own GPU pass.
- Bind the TLAS at descriptor binding 2.
- Give a lamp box instance mask `0x01`. Other boxes use `0xFF`. Shadow rays test `0x02`, so a lamp does not block its own light.
- Trace only after the normal test. Use `gl_RayFlagsTerminateOnFirstHitEXT | gl_RayFlagsOpaqueEXT`, an origin offset of `0.002 m`, `TMin = 0.001 m`, and `TMax = max(distance - 0.001, 0)`.
- Stop the ray short of the light. A lamp on a wall must not paint a fan of false shadows.
- Add the gated override `light_shadows`, default true, for paired captures and performance runs. Do not add a per-lamp editor toggle.
- Keep the direct clustered loop, ambient floor, emissive term, and TAA unchanged.

## Consequences

- A device without ray-query support is rejected. There is no silent fallback. A future portability target must add cube maps or choose a different renderer.
- The TLAS is rebuilt every frame, so moving lamps and boxes update shadows without a shadow-map cache.
- The 96-light shadow term is a measured budget. A target of 100+ overlapping shadowed lights, or a weaker GPU target, reopens the technique choice.
- The point light remains zero-area. Soft shadows and a lamp radius are out of scope.
- `scenarios/shadows.json`, `scenarios/shadow-move.json`, and `scenarios/lamp-wall-plane.json` gate the visual behavior. `scenarios/perf-shadows.json` gates the 96-light cost.
- This supersedes the no-shadow clauses in ADR 0021, ADR 0037, and ADR 0038. The rest of those decisions stays in force.
