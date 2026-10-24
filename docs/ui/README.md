# The 2D layer

The overlay is a technical readout, not a poster. It sits on hard-edged geometry
and never competes with it. Square corners, one-pixel hairlines, two hues, and one
accent that means "this row". Nothing moves.

The type has to carry the whole personality, because nothing else does.

Three files decide everything. `src/renderer/ui_theme.odin` holds the tokens.
`src/ui/ui.odin` holds the data the game hands over. `src/renderer/hud_rows.odin`
lays rows out. Change a value in the theme, not in a component.

## The layer rule

| Layer | Owns | Must not |
| --- | --- | --- |
| `src/game` | which rows exist, their labels and values | know about colours, sizes, or pixels |
| `src/ui` | the row vocabulary | import anything |
| `src/frame` | passing the view through | add layout |
| `src/renderer` | tokens, layout, drawing | invent content |

A component reads `theme.*`. A literal `[4]f32` colour or a bare pixel size in
`hud.odin`, `hud_menu.odin`, or `hud_rows.odin` is a bug.

## Density

Everything scales from one number: `density = clamp(height / 720, 1, 2)`, where
`height` is the render target in pixels. A 720p window gets density 1, a 1080p
window 1.5, a 1440p window 2. Below 720p it stays at 1 so the smallest supported
window still shows every row.

## Files

- [type.md](type.md): the five type roles, leading, tracking, and the fixed-width
  number rule.
- [colour.md](colour.md): the ramp, the contrast table, and the alpha rules.
- [spacing.md](spacing.md): the spacing scale, panel anatomy, and hairlines.
- [components.md](components.md): the status panel, the capture hint, the
  crosshair, and the settings panel.

## Adding a surface

1. Decide the rows. Each row is a `ui.Row` with a `kind`: `Setting`, `Action`,
   `Metric`, `Detail`, `Header`, `Divider`, or `Spacer`.
2. Fill the rows in `src/game`. Format every number into a fixed field.
3. Draw the panel with `rows_measure` and `rows_emit`. Do not measure text by
   hand and do not position rows with per-row offsets.
4. If the surface needs a value the theme does not have, add a token to
   `ui_theme.odin`. Do not inline it.

If the surface needs a kind that does not exist, add it to `ui.Row_Kind` and to
`row_label_style`, `row_value_style`, `row_gap`, and `row_height` in the same
change. A kind that only two of the four know about draws at the wrong height.

## Rules that are easy to break

- A panel is square. No corner radius, no shadow, no gradient.
- Depth is one surface step plus a one-pixel ring. Never a blur.
- Selection is the raised surface plus the accent bar. Never a colour change on
  the text alone, and never a bright band behind white text.
- Every changing number is mono, in a fixed field. See [type.md](type.md).
- The capture hint sits below the crosshair, never across it.
