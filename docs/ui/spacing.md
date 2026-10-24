# Spacing and surfaces

One scale, one hairline width, square corners. Depth comes from a surface step
and a hairline ring, not from a blur.

## The scale

Values are pixels at density 1 and multiply by density. Tokens are in
`src/renderer/ui_theme.odin`.

| Token | 720p | 1080p | Where |
| --- | --- | --- | --- |
| `spacing.xxs` | 2 | 3 | band padding above and below a selected row |
| `spacing.xs` | 4 | 6 | gap above a `Metric` or `Detail` row, key to action |
| `spacing.sm` | 6 | 9 | gap above a `Setting`, `Action`, or `Slider` row, gap above a divider, slider tick height and track gap, menu label inset |
| `spacing.md` | 8 | 12 | status panel margin, capture hint padding, slider knob |
| `spacing.lg` | 12 | 18 | status panel padding, gap above a section header, note gap, slider track zone |
| `spacing.xl` | 16 | 24 | settings panel padding, label-to-value gutter, legend column gap |
| `spacing.xxl` | 24 | 36 | reserved for a future full-bleed split |

Use the nearest step. A value between two steps means the layout is wrong, not
that the scale needs a new entry.

## Hairlines

`theme.hairline` is `max(1, round(density))` device pixels: 1 px at 720p, 2 px at
1080p and above. It never lands on a fraction: a 1.5 px line resolves to a
two-pixel grey smear.

- A panel ring is `line_hairline` on all four edges. `hud_emit_frame` draws the
  top and bottom full width and the sides the inner height, so each corner is
  covered once.
- A translucent surface cannot take a border by filling a larger rect behind it,
  because the fill shows through the panel. An opaque surface hides the larger
  rect instead, so it gets no border at all.
- A divider is `line_separator`, one hairline tall, spanning the panel's inner
  width.
- The accent bar is `max(2, hairline * 2)`: two device pixels minimum, so it is a
  bar and not a line.

## Panel anatomy

```
┌──────────────────────────────────────────┐  ← hairline ring, line_hairline
│  padding.xl                              │
│  Title                                   │  ← type_title, centred
│  ──────────────────────────────────────  │  ← separator, inner width
│  padding.sm                              │  ← rows start sm inside the inner edge
│  Label            value                  │  ← label type_body_strong
│  Type weight          400                │  ← Slider, line one
│  ─────●─────────────                    │  ← Slider track, ticks, knob
│  ──────────────────────────────────────  │
│  Action                                  │
│                                          │
│  SECTION HEADER                          │  ← type_caption_caps
│  key  action    key  action    key  act  │  ← legend grid
│  padding.xl                              │
│  note, centred                           │  ← type_caption, tertiary
└──────────────────────────────────────────┘
```

Rules that follow from the drawing:

- The value column ends on `panel_x + panel_width - padding`, not on the widest
  row. `build_menu` widens `rows_layout.value_width` to reach the edge.
- The label column is the widest label. `rows_measure` skips a `Header` when it
  measures that column, and skips values on `Header` and `Divider` rows. The
  value column starts `spacing.xl` after the label column.
- One gap, one owner: the row layout adds the gap above a row, so no row carries
  its own margin and the last row leaves no trailing gap. A row gets `spacing.xs`
  above it, a `Setting`, `Action`, or `Slider` row `spacing.sm`, a divider
  `spacing.sm`, and a section header `spacing.lg`.
- A `Slider` row is `type_body.line_height + spacing.sm + spacing.lg`, which is
  40.5 px at density 1. The track spans `frame_x .. frame_x + frame_width`; the
  knob travel is the inner width minus `spacing.md`, so the ticks and the knob
  stay inside the panel.
- The settings content width freezes when the menu opens, at 5 % above its
  opening value. The frozen value is a floor, not a cap. For the weight axis the
  headroom covers the growth, so the track does not move under the cursor while
  the value changes.
- A divider and the selection band both span `frame_x .. frame_x + frame_width`,
  the panel's inner rectangle. They share one edge with each other. The legend
  grid has its own pitch: caption line height plus `spacing.xxs`.
- The status panel uses the same row layout with `value_align = .Left`, because a
  readout reads label-then-value, while a settings list reads label-then-edge.

## Surfaces

Square corners, always. The world is boxes; a rounded card would be the only soft
edge on screen.

| Surface | Fill | Edge |
| --- | --- | --- |
| Status panel | `surface_hud` | `line_hairline` ring |
| Capture hint | `surface_hud` | `line_hairline` ring |
| Settings panel | `surface_menu` over `scrim` | `line_hairline` ring |
| Selected row | `surface_raised` | `accent` bar on the leading edge |

No shadow, no gradient, no radius token. `docs/ui/README.md` explains why.

## Bans

- No per-child margins. The parent owns the gap.
- No `width: auto` equivalent: every panel width traces to measured content plus
  padding: rows, the hint grid, the title, or the note, raised to the
  `menu_min_width` floor of 200 px at density 1. The settings menu then freezes
  its content at 5 % headroom for the weight axis.
- No nested panels. A row is not a card.
- No clipping. The settings panel is 494 px wide and 517 px tall at 720p at the
  default weight; the smallest supported window is 800x600, so it fits. The panel
  still clamps its top to `spacing.md`, so an offscreen target of any size keeps
  the header on screen. A new surface must say what happens when it does not fit.
