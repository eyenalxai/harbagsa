# Ambient occlusion scales direct light only

## Context

The lit pass has two visibility terms. Ambient occlusion traces the local
hemisphere and scales the direct sun and point lights. The DDGI probe volume
adds indirect diffuse radiance, and its depth moments already reject probes
behind geometry.

If AO also multiplied the indirect term, a corner would darken twice: once
because the direct light is occluded, and again because the indirect probe
samples are weighted by the same local visibility. A probe already carries the
radiance that reached it; multiplying that result by the surface's AO would
remove light that the probe really saw.

## Decision

The formula is:

```text
albedo * (direct * occlusion + probe_indirect)
```

- `occlusion` scales the sun and the point lights.
- `probe_indirect` is added after the occlusion.
- The probe sampler keeps its own visibility weights: surface facing, inverse
  square distance, and the Chebyshev depth test.
- The contact term is the direct AO. There is no second AO on the indirect term.

## Why

- One visibility term per light path. The direct path uses the surface AO; the
  indirect path uses the probe depth map.
- A lamp that only reaches a surface through a bounce lights it; AO cannot see
  that path and must not subtract it.
- The contact band stays where direct light meets a corner. The indirect term
  fills the corner without a second dark edge.

## Considered Options

- **AO on the total.** Simple, but it double counts the corner occlusion and
  darkens indirect light that the probe actually saw.
- **No AO.** The direct contact band disappears, and boxes look like they float.
- **A separate indirect AO pass.** More accurate, but it needs another ray set
  and it duplicates the probe depth rejection.
- **AO on direct, no probe visibility.** Leaks increase. The probe depth test is
  cheaper and already part of the sampler.

## Consequences

- `scenarios/ddgi.json` captures the chamber with AO on and off while GI stays
  on. AO off is brighter on the direct contact band, and the probe atlas energy
  is unchanged.
- A surface lit only by a bounce stays lit even when its direct AO is 1.
- The next leak-control work can tune probe visibility without touching the AO
  strength.
