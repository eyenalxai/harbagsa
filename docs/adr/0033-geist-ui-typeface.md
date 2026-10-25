# Geist as the 2D typeface

## Context

The overlay draws all text in Roboto Condensed and Roboto Mono. Roboto Condensed
was chosen for density: the status panel and the settings menu have little room.
The type is the whole personality of the 2D layer, so the face is a design
choice and not only a metric.

Geist is Vercel's open typeface. It is a neutral Swiss sans with a matching mono
face, both variable on `wght` 100-900 and both under the SIL Open Font License
1.1. Geist Mono uses tabular figures at 600 units of a 1000-unit em. Geist Sans
uses proportional figures.

## Decision

Ship Geist and Geist Mono as the two overlay faces.

- Subset both to ASCII plus `·`, `×`, and `…`, as the Roboto faces were.
- Keep the `wght` axis and the nine named instances.
- Remove the 700 clamp on the mono face, because Geist Mono runs to 900.
- Keep `Row.numeric` for every value that changes during play. The sans face has
  proportional digits, so a changing number must use the mono face.
- Keep the coverage atlas and the variable-weight pipeline unchanged.

## Why

- The two faces share a design and a weight axis. The menu and the HUD keep one
  typographic voice.
- Both are OFL 1.1, so the game can ship them in a commercial build with the
  licence file.
- Geist Mono is tabular, so the fixed-field rows keep their width.
- The full 100-900 mono axis removes the old edge case where numbers stopped
  gaining weight above Bold.

## Considered Options

- **Google Sans Flex.** Also OFL 1.1 and also variable. It carries a stronger
  Google association, and its roundness axis is not needed here.
- **Inter.** A common neutral sans, but it has no matching mono face from the
  same project and no advantage over Geist.
- **Keep Roboto Condensed.** It is narrower and already measured. Rejected
  because the type should carry the design, and the narrow face was a
  space-saving compromise.

## Consequences

- Text runs wider. The status panel and the settings menu grow; both still fit
  at 1280x720.
- `src/renderer/fonts/PROVENANCE.md` records the new source, subset command, and
  hashes.
- The mono weight clamp and `TYPE_WEIGHT_MONO_MAX` are gone. Every face follows
  the settings weight from 100 to 900.
- The type guide and the evidence page name Geist, and the HUD and menu captures
  are regenerated.
