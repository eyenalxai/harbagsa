# WCAG 2 contrast for the overlay

WCAG 2 is the contrast gate for the 2D layer. APCA is recorded as a reference,
not a gate.

## Why

The overlay has three text levels. On `surface_menu`, `text_primary` is 15.39:1,
`text_secondary` is 8.05:1, and `text_tertiary` is 5.07:1. All three pass the
WCAG 2 4.5:1 floor for body text.

APCA scores the same pairs at Lc 97, 60, and 40, and `accent` at 63. The APCA
body floor is 60. To lift `text_tertiary` to 60, its luminance must reach about
0.41. The current
`text_secondary` is about 0.44. The tertiary level would become as light as the
secondary level, and the three-level ramp would collapse to two.

The tertiary level is deliberate. It carries `Detail` and `Header` rows and the
legend actions, and it never carries a selectable row. The quiet step is the
point. A standard that removes it changes the design.

APCA is stricter for small, light text on a dark surface, which is this
overlay. The project accepts the WCAG 2 floor and the APCA gap on purpose.

## Consequences

- `text_tertiary` on the composited menu holds 4.5:1.
- `text_tertiary` on `surface_raised` is 3.86:1 and stays below the text floor.
  It must never carry selectable text. `docs/ui/colour.md` records the rule.
- A future change that lightens `text_tertiary` to APCA 60 is a design change.
  It needs a capture and a new ADR.

## Considered Options

- **APCA as the gate**: lighten `text_tertiary` to Lc 60. The ramp loses a
  level.
- **Both standards as gates**: every text token must pass both. This is the
  APCA option with a WCAG floor, so the ramp still collapses.
- **WCAG 2 as the gate**: keep the three levels. This is the decision.
