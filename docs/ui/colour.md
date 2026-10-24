# Colour

Two hues and a neutral ramp. Cool ink for surfaces, one amber accent that means
"selected". The accent is already the debug selection colour on placed objects
and the sun gizmo, so it is reused rather than invented.

Every colour lives in `src/renderer/ui_theme.odin` as an sRGB hex constant. It is
converted to linear when `ui_theme_init` builds the theme, because the renderer
blends in linear space and an sRGB attachment expects linear output.
`prepare_overlay` calls `ui_theme_init` every frame, so the conversion is not a
persistent cache. A component never sees a hex value and never converts one.

## The palette

The six neutral tokens are authored at OKLCH hue 253. The 8-bit hex rounds each
token, so the measured hues span 7.8 degrees. The table records the measured
value for every token, so a future change can move one channel and leave the
others. Hue is undefined when chroma is zero.

| Token | sRGB | Alpha | L | C | H | Role |
| --- | --- | --- | --- | --- | --- | --- |
| `text_primary` | `#EEF2F6` | 1.0 | 0.959 | 0.007 | 247.9 | a `Setting`, `Action`, `Metric`, or `Slider` value, a panel title, the selected label, the slider knob |
| `text_secondary` | `#A7B2BF` | 1.0 | 0.759 | 0.022 | 252.5 | a `Setting`, `Action`, `Slider`, or `Metric` label, a blocked value, a legend key, the slider fill |
| `text_tertiary` | `#818C99` | 1.0 | 0.635 | 0.023 | 252.6 | a `Detail` label, a `Detail` value, a section header, a legend action, the slider ticks |
| `accent` | `#E6AF3A` | 1.0 | 0.785 | 0.142 | 82.2 | the selection bar, and nothing else |
| `surface_hud` | `#0F141A` | 0.94 | 0.189 | 0.015 | 253.2 | the status panel, the capture hint |
| `surface_menu` | `#151B23` | 1.0 | 0.220 | 0.018 | 255.7 | the settings panel |
| `surface_raised` | `#26313D` | 1.0 | 0.308 | 0.026 | 250.9 | the selected row |
| `line_hairline` | `#FFFFFF` | 0.09 | 1.000 | 0.000 | 0.0 | the hairline ring around a panel |
| `line_separator` | `#FFFFFF` | 0.16 | 1.000 | 0.000 | 0.0 | a divider inside a panel |
| `slider_track` | `#FFFFFF` | 0.20 | 1.000 | 0.000 | 0.0 | the slider track, 3.4:1 on `surface_raised` |
| `scrim` | `#000000` | 0.62 | 0.000 | 0.000 | 0.0 | the dim behind the settings panel |
| `crosshair` | `#FFFFFF` | 0.90 | 1.000 | 0.000 | 0.0 | the crosshair arms |
| `crosshair_edge` | `#000000` | 0.55 | 0.000 | 0.000 | 0.0 | the crosshair outline, so it reads on any background |

The hairline is `max(1, round(density))` device pixels: 1 px at 720p, 2 px at
1080p and above. A ring, divider, or outline is one hairline wide, not one pixel.

## Contrast

Measured on the authored sRGB values, the WCAG 2 way. WCAG 2 is the gate. APCA
is a reference, not a gate. The APCA Lc scores on `surface_menu` are 97 for
`text_primary`, 60 for `text_secondary`, 40 for `text_tertiary`, and 63 for
`accent`. ADR 0019 records why the tertiary level stays below the APCA body
floor.

| Foreground | On `surface_menu` | On `surface_raised` | On `surface_hud` |
| --- | --- | --- | --- |
| `text_primary` | 15.39:1 | 11.75:1 | 16.44:1 |
| `text_secondary` | 8.05:1 | 6.14:1 | 8.60:1 |
| `text_tertiary` | 5.07:1 | 3.86:1 | 5.40:1 |
| `accent` | 8.70:1 | 6.64:1 | 9.30:1 |

The floor is 4.5:1 for text and 3:1 for a non-text element such as the accent bar.
`tests/renderer/text.odin` checks `text_primary` and `text_secondary` on the
composited HUD and menu, `text_tertiary` on the composited menu, `text_primary`
and `text_secondary` on the raised surface, and `accent` and the slider track
against the raised surface. It does not check the slider fill, the ticks, or
the knob.

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
