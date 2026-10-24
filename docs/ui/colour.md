# Colour

Two hues and a neutral ramp. Cool ink for surfaces, one amber accent that means
"selected". The accent is already the debug selection colour on crates and the
sun gizmo, so it is reused rather than invented.

Every colour lives in `src/renderer/ui_theme.odin` as an sRGB hex constant. It is
converted to linear once, at theme init, because the renderer blends in linear
space and an sRGB attachment expects linear output. A component never sees a hex
value and never converts one.

## The palette

| Token | sRGB | Alpha | Role |
| --- | --- | --- | --- |
| `text_primary` | `#EEF2F6` | 1.0 | a value, a panel title, the selected label, the slider knob |
| `text_secondary` | `#A7B2BF` | 1.0 | a row label, a legend key, the slider fill |
| `text_tertiary` | `#808C99` | 1.0 | a detail value, a section header, a legend action, the slider ticks |
| `accent` | `#E6AF3A` | 1.0 | the selection bar, and nothing else |
| `surface_hud` | `#10141A` | 0.94 | the status panel, the capture hint |
| `surface_menu` | `#161B23` | 1.0 | the settings panel |
| `surface_raised` | `#26313D` | 1.0 | the selected row |
| `line_hairline` | `#FFFFFF` | 0.09 | the one-pixel ring around a panel |
| `line_separator` | `#FFFFFF` | 0.16 | a divider inside a panel |
| `scrim` | `#000000` | 0.62 | the dim behind the settings panel |
| `crosshair` | `#FFFFFF` | 0.90 | the crosshair arms |
| `crosshair_edge` | `#000000` | 0.55 | the crosshair outline, so it reads on any background |

## Contrast

Measured on the authored sRGB values, the WCAG 2 way.

| Foreground | On `surface_menu` | On `surface_raised` | On `surface_hud` |
| --- | --- | --- | --- |
| `text_primary` | 15.4:1 | 11.8:1 | 16.4:1 |
| `text_secondary` | 8.0:1 | 6.1:1 | 8.6:1 |
| `text_tertiary` | 5.0:1 | 3.9:1 | 5.4:1 |
| `accent` | 8.7:1 | 6.6:1 | 9.3:1 |

The floor is 4.5:1 for text and 3:1 for a non-text element such as the accent bar.
`tests/renderer/text.odin` holds the theme to it, including the selected row.

`text_tertiary` passes on the menu but not the text floor on the raised surface.
That is safe by construction for text: `Setting`, `Action`, and `Slider` labels
draw in `text_secondary` or `text_primary`. A `Detail` or `Header` row must never
become selectable without moving it to `text_secondary`. A Slider is selectable;
its fill and knob carry the value and meet the 3:1 non-text floor, and its ticks
clear 3:1 on the raised surface. The track is a divider-weight line.

## Choosing a text colour

```
Is it the row's value, or a panel title?
├── Yes → text_primary
└── No
    ├── Is it the row's label, or a legend key?
    │   └── Yes → text_secondary
    └── Is it secondary detail, a section header, or a legend action?
        └── Yes → text_tertiary
```

Anything that is not text: `accent` for the selection bar, `line_hairline` for a
panel ring, `line_separator` for a divider and the slider track, `text_primary`
for a slider knob, `text_secondary` for a slider fill, and `text_tertiary` for a
slider tick. Nothing else.

## Alpha

Surfaces are translucent so the scene reads through them, but only just. In
linear space a bright sky is fifty times brighter than ink, so 6% of it is
visible.

- `surface_hud` is 0.94. Below 0.9 the panel picks up the sky's hue and stops
  looking like a designed surface.
- `surface_menu` is 1.0. A modal over a dimmed scene has no reason to show the
  scene twice.
- `surface_raised` is 1.0. A selection must not depend on what is behind it.

Never build a tint by lowering alpha. Lower the chroma or move the lightness in
the token.

## Bans

- No third hue. If a new state needs one, it is not a state, it is a redesign.
- No colour-only signal. Selection adds the accent bar and the raised surface;
  a divider is a line, not a tint.
- No pure grey. The neutral ramp is cool because the sky is.
- No `dark:` equivalent. There is one theme. The scene is the backdrop, not the
  mode.
