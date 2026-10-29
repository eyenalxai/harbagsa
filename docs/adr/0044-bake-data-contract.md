# Bake data contract and runtime loader

The renderer loads a versioned `.hbake` artifact and creates the lightmap and
probe resources from it. A missing, stale, or rejected bake is a visible state,
never a fill value.

## Why

- The mixed-lighting split needs one static indirect representation shared by
  the bake tool, the runtime, and the harness. An ad-hoc runtime probe update
  cannot be validated or reproduced.
- The artifact must carry the lightmap atlas, the per-face atlas rects, the
  static probe atlases, the probe volume, the quality settings, and the key that
  identifies its inputs.
- The bake tool is a separate ticket. Until it lands, the runtime must still
  start, render the direct path, and report that indirect data is missing.
  A compile-time `#load` of a nonexistent file would make that state impossible.

## Decisions

- **Version first.** Every file starts with `HBAK`, a `u16` format version, a
  `u16` header size, a tool version, flags, the bake key, and an FNV-1a payload
  hash. Version 1 is the only accepted version. An unknown magic, version,
  atlas format, or section layout is an error; the runtime reports `failed` and
  creates no bake resources.
- **Header and section table.** The header names the atlas size, face, slot, and
  probe counts, the probe volume, and the section table. Every section is
  16-byte aligned and checked against its declared stride and count. Raw
  sections hold the atlas and probe payloads; typed sections hold 32-byte face
  rects, 16-byte slots, 8-byte probe states, 36-byte quality, and 40-byte stats.
  Section sizes must match the header exactly.
- **Atlas.** One linear `R16G16B16A16_SFLOAT` image, one mip, one layer, 1024
  square, 4 texels per metre, an 8-texel minimum chart, and a 4-texel gutter.
  Every static box owns one slot and six face rects. Slots are slot-major: slot
  `i` owns faces `i * 6` through `i * 6 + 5` in the face order +X, -X, +Y, -Y,
  +Z, -Z. The rects are center-to-center and stay inside `[0, 1]`.
- **Probes.** A regular grid at 1 m spacing is the default; 2 m remains the
  quality fallback. Each probe stores an 8 x 8 octahedral irradiance block and
  an 8 x 8 first/second moment block. Probes are packed into a 2D shelf atlas;
  the header stores the column count so a reader can derive both image extents.
  The probe state buffer carries the valid flag and virtual offset, so the
  runtime never re-derives validity from live geometry. The bake repairs a
  probe that the virtual offset cannot move out of geometry by dilating it from
  nearby valid probes; a probe with no valid source stays invalid. The runtime
  samples the four probes of the containing tetrahedron, applies normal bias,
  the facing weight, and the depth-moment test, and skips an invalid probe.
- **Key.** The key hashes the canonical static boxes (arena in array order, then
  placed static objects by object id), the active static fixtures, the quality,
  and the tool version. Dynamic lamps and dynamic bodies are excluded. The
  renderer recomputes the key with the artifact's own quality block, so a 1 m
  or 2 m artifact validates against the same static inputs. The runtime reports
  `current` or `stale`.
- **Runtime resources.** The lightmap image and sampler, the probe irradiance
  and moment images, the shared linear clamp sampler, the face and slot buffers,
  the probe state buffer, and the probe volume buffer are created with the
  renderer and destroyed with it. A rejected or missing artifact creates none of
  the artifact-backed resources; a placeholder lightmap image and one-face
  buffer keep the descriptor set valid until a bake is published.
- **Loader source.** The runtime reads `build/bake/arena.hbake` by default. The
  harness accepts `--bake PATH` so a loader fixture or a build from another
  checkout can be exercised. A missing file is `missing`; a parse failure is
  `failed` with the loader error. Neither falls back to black or to an old bake.
- **Observability.** `state.renderer.bake` reports the status, the current key,
  the artifact key, format and tool versions, atlas and probe counts, spacing,
  artifact and GPU bytes, bake time, and the load error. The render digest
  includes the current key and the applied status, so two bakes cannot compare as
  the same image.

## Considered options

- **Embed the artifact with `#load` now.** Rejected for this slice. The bake
  tool does not exist yet, so the build would fail instead of exposing the
  required `missing` state. The loader is independent of the source, so a later
  build step can embed the same bytes.
- **KTX2 container.** Rejected. The artifact also carries probes, rects, and
  stats, and the first version uses no mips, layers, or compression.
- **Parse the file every publish.** Rejected. The artifact is loaded once at
  renderer creation; republishing is a later lifecycle ticket.
- **Silent fallback to black, to probes, or to an older bake.** Rejected. The
  mixed-lighting spec requires a visible missing or stale state, and a silent
  substitution makes a capture lie.
- **Per-frame probe updates.** Rejected. This is baked data, not DDGI.

## Consequences

- The runtime still renders direct light, hard shadows, and the emissive term
  while an artifact is missing. Indirect is absent until a bake is published.
- A static geometry or static fixture edit changes the key and reports `stale`
  immediately. The old indirect data stays bound until a later publish path
  replaces it.
- `src:bake` is compiled by `make check` and imported by the frame and the
  renderer. It does not import either package, so the bake tool can share it.
- The lightmap sampler, the face buffer, the probe images, the probe state
  buffer, and the probe volume are bound in the scene descriptor set. Static
  boxes sample the lightmap; dynamic boxes sample the probe field. A missing or
  failed artifact binds placeholder images, a one-face buffer, a one-probe state
  buffer, and a one-probe volume so the descriptor set stays valid. Every
  object's lightmap and probe weights are zero in that state, so nothing samples
  a placeholder.
- The design guide, `README.md`, `GLOSSARY.md`, and ADR 0042 still describe the
  removed dynamic DDGI field and ban baked light or textures. This ADR starts
  the replacement but does not edit those pages; #386 owns that cleanup. Do not
  read the current guide as agreeing with this contract.
