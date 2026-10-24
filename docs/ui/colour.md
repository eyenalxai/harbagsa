# Colour

Two hues and a neutral ramp. Cool ink for surfaces, one amber accent that means
"selected". The accent is sRGB `#E6AF3A`. The debug crate outline and the sun
gizmo are a linear `[1.0, 0.8, 0.2]`, a different value from the sRGB `#E6AF3A`;
they live in different spaces, so the accent is not reused from the debug draw.

Every colour lives in `src/renderer/ui_theme.odin` as an sRGB hex constant. It is
converted to linear when `ui_theme_init` builds the theme, because the renderer
blends in linear space and an sRGB attachment expects linear output.
`prepare_overlay` calls `ui_theme_init` every frame, so the conversion is not a
persistent cache. A component never sees a hex value and never converts one.

## The palette

| Token | sRGB | Alpha | Role |
| --- | --- | --- | --- |
| `text_primary` | `#EEF2F6` | 1.0 | a `Setting`, `Action`, `Metric`, or `Slider` value, a panel title, the selected label, the slider knob |
| `text_secondary` | `#A7B2BF` | 1.0 | a `Setting`, `Action`, `Slider`, or `Metric` label, a blocked value, a legend key, the slider fill |
| `text_tertiary` | `#808C99` | 1.0 | a `Detail` label, a `Detail` value, a section header, a legend action, the slider ticks |
| `accent` | `#E6AF3A` | 1.0 | the selection bar, and nothing else |
| `surface_hud` | `#10141A` | 0.94 | the status panel, the capture hint |
| `surface_menu` | `#161B23` | 1.0 | the settings panel |
| `surface_raised` | `#26313D` | 1.0 | the selected row |
| `line_hairline` | `#FFFFFF` | 0.09 | the hairline ring around a panel |
| `line_separator` | `#FFFFFF` | 0.16 | a divider inside a panel |
| `slider_track` | `#FFFFFF` | 0.20 | the slider track, 3.4:1 on `surface_raised` |
| `scrim` | `#000000` | 0.62 | the dim behind the settings panel |
| `crosshair` | `#FFFFFF` | 0.90 | the crosshair arms |
| `crosshair_edge` | `#000000` | 0.55 | the crosshair outline, so it reads on any background |

The hairline is `max(1, round(density))` device pixels: 1 px at 720p, 2 px at
1080p and above. A ring, divider, or outline is one hairline wide, not one pixel.

## Contrast

Measured on the authored sRGB values, the WCAG 2 way.

| Foreground | On `surface_menu` | On `surface_raised` | On `surface_hud` |
| --- | --- | --- | --- |
| `text_primary` | 15.4:1 | 11.7:1 | 16.4:1 |
| `text_secondary` | 8.0:1 | 6.1:1 | 8.6:1 |
| `text_tertiary` | 5.0:1 | 3.9:1 | 5.4:1 |
| `accent` | 8.7:1 | 6.6:1 | 9.3:1 |

The floor is 4.5:1 for text and 3:1 for a non-text element such as the accent bar.
`tests/renderer/text.odin` checks `text_primary` and `text_secondary` on the
composited HUD and menu, `text_primary` on the raised surface, and `accent` and
the slider track against the raised surface. It does not check `text_tertiary`,
the slider fill, the ticks, or the knob.

`text_tertiary` passes on the menu but not the text floor on the raised surface.
That is safe by construction for text: `Setting`, `Action`, and `Slider` labels
draw in `text_secondary` or `text_primary`. A `Detail` or `Header` row must never
become selectable without moving it to `text_secondary`. A Slider is selectable;
its fill uses `text_secondary` and its knob `text_primary`, both above 3:1 on the
raised surface. Its ticks stop at 3.9:1 on that surface; 3:1 is the non-text
floor. The track uses `slider_track` at 3.4:1 on the raised surface, never
`line_separator` and never the accent.

## Choosing a text colour

```
Is it a panel title, or the value of a Setting, Action, Metric, or Slider?
├── Yes → text_primary (text_secondary when the row is blocked)
└── No
    ├── Is it the label of a Setting, Action, Slider, or Metric, a legend key,
    │   or a blocked value?
    │   └── Yes → text_secondary
    └── Is it a Detail label, a Detail value, a section header, or a legend
        action?
        └── Yes → text_tertiary
```

Anything that is not text: `accent` for the selection bar, `line_hairline` for a
panel ring, `line_separator` for a divider, `slider_track` for the slider track,
`text_primary` for a slider knob, `text_secondary` for a slider fill, and
`text_tertiary` for a slider tick. Nothing else.

## Alpha

`surface_hud` is translucent so the scene reads through it, but only just. In
linear space a bright sky is fifty times brighter than ink, so 6% of it is
visible. The menu surfaces are opaque.

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
