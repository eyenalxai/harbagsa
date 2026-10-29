# Mixed static baked indirect and dynamic direct light

The renderer shades every box with real-time direct light from static fixtures and
dynamic lamps, hard point-light shadows, and a baked one-bounce static indirect
term. Static boxes sample a lightmap; dynamic boxes sample a static probe field.
A dynamic lamp contributes no indirect. The bake is a versioned artifact with an
explicit publish step: a static edit makes it stale, and the old indirect stays
bound until the new bake is published.

ADR 0043 already names the third-person spider, so this decision takes the next
free number.

## Why

- The dynamic DDGI field leaked through thin walls and left dark corners. A
  static bake can use a static-only BVH and a much larger ray budget without a
  per-frame probe pass.
- Static fixtures and static geometry are the inputs that change rarely. Dynamic
  lamps and crates are the inputs that move. Splitting them keeps the expensive
  transport out of the frame while direct light and hard shadows stay live.
- A stale bake must not look current. The artifact carries a key over the static
  inputs, so the renderer can report `current` or `stale` without guessing.
- The flat box look needs one diffuse bounce in corners, not a dynamic GI system.
  A lightmap gives static surfaces a stable corner term; a probe field gives
  dynamic objects the same static bounce.

## Decisions

- **Lamp kind.** A lamp carries a `Lamp_Kind`: `Static_Fixture` or
  `Dynamic_Lamp`. A static fixture uses a static body; a dynamic lamp uses a
  dynamic body. The kind is separate from the prefab and from an ordinary box
  body mode. Newly placed lamps default to dynamic. The starting three lamps are
  static fixtures. `K` toggles the selected or next-placement lamp kind, and the
  body follows the kind. A direct body change on a lamp is refused.
- **Bake inputs.** The bake hashes and traces the arena static boxes, placed
  static bodies, active static fixtures, and static emissive boxes. Dynamic
  lamps, dynamic crates, the spider, the camera, TAA, and the UI never enter the
  bake.
- **One bounce.** The bake traces one diffuse bounce. A miss returns zero; there
  is no sky, sun, or ambient term.
- **Lightmap.** One linear `1024²` `RGBA16F` atlas holds one tile per static box
  face. Face UVs come from the local position and face normal, so there is no
  vertex UV channel. The lightmap contains static indirect only; direct light and
  hard shadows stay real-time.
- **Denoise.** The bake filters each chart once, after the buried fill and before
  the gutter: a separable 3x3 binomial over RGB, clamped at the chart edge. One
  chart is one planar face, so the kernel cannot bleed across a surface. The
  texel seed follows `(source, id, face, x, y)`, not the atlas position, so a
  static edit that only moves charts leaves their noise field alone.
  `TOOL_VERSION` is 2.
- **Probes.** A static 1 m grid covers the playable volume; 2 m is the quality
  fallback. Each probe stores an 8 x 8 octahedral irradiance block and depth
  moments. Dynamic boxes sample the four probes of the containing tetrahedron
  with normal bias, facing weight, and the baked depth test. Static boxes never
  read the probes.
- **Key and status.** The bake key hashes the canonical static boxes, the active
  static fixtures, the quality, and the tool version. The renderer recomputes it
  from the current static input. A missing artifact is `missing`; a parse failure
  is `failed`; a key mismatch is `stale`; a match is `current`.
- **Publish.** A static fixture or static geometry edit changes the key and marks
  the bake stale. Direct light updates immediately; the old indirect remains
  bound and visible. An explicit `bake` command rebuilds from the current static
  input and publishes the new artifact. A failed publish leaves the old artifact
  bound and reports `failed`; it never falls back to black or to another bake.
- **Harness.** The `bake` command builds, optionally writes the artifact, and
  publishes it. `state.bake` reports the status, key, artifact key, format and
  tool versions, measured bake time, atlas and probe counts, memory, and the load
  or publish error. `make bake` writes `build/bake/arena.hbake` for the game.
- **Empty bake.** Removing every static fixture and publishing a fresh bake
  yields zero indirect. A lamp-free scene stays black.
- **Editor and docs.** The editor HUD shows the lamp kind and the bake status.
  The design guide, README, glossary, and harness guide describe the mixed
  system, not DDGI.

## Considered options

- **Keep dynamic DDGI.** Rejected. It leaks through thin walls, needs a per-frame
  probe pass, and cannot use a static-only caster.
- **Bake indirect from every lamp, including dynamic lamps.** Rejected. A moving
  lamp would require a rebake, which defeats the split.
- **Rebake on every static edit.** Rejected. The default bake is about 5 s; an
  edit would freeze the frame. The stale state is visible and the publish is
  explicit.
- **Silent fallback to black, probes, or an older artifact.** Rejected. A capture
  must not lie about the indirect data it used.
- **A surface or material texture.** Rejected. The lightmap is lighting data, not
  a material texture. The one-texture rule becomes "no surface or material
  textures"; the lightmap sampler is allowed.
- **More than one bounce.** Deferred. One bounce covers the corner and wall
  cases in the flat box arena.
- **Raise the lightmap ray count.** Rejected for now. 128 to 512 rays is four
  times the lightmap stage, and the bake already misses its 2 s target.
- **Denoise at runtime in screen space.** Rejected. It smears the real-time
  direct light and the hard shadows, and a per-chart bake pass costs nothing per
  frame.
- **A 5x5 Gaussian.** Rejected. It buys eight points of clean-window stddev over
  the binomial at two texels (50 cm) of softening at contact corners instead of
  one, and it does not change the whole-wall number.

## Consequences

- A static fixture edit changes direct light immediately and reports `stale`
  until the next publish. A dynamic lamp or crate move reports `current`.
- A bake is deterministic for the same static input, quality, and tool version.
  The measured wall time travels in a `.time` sidecar, not in the artifact bytes.
- The lightmap is denoised per chart, so an artifact built by tool version 1 is
  `stale` and must be rebuilt. A static edit that only moves charts leaves their
  noise field byte-identical.
- The default bake is about 5 s at 16 threads, not the 2 s target. The 2 m probe
  fallback reduces probe work. Quality and performance measurement stay in the
  follow-up ticket.
- The bake artifact is about 14 MiB for the default arena and stays under the
  32 MiB budget.
- This supersedes ADR 0042 (dynamic DDGI), ADR 0039 (dynamic-only lamps), and
  the "no probe" wording in ADR 0041. The no-ambient-floor rule, direct clustered
  lights, hard shadows, TAA, and the emissive term stay in force.
