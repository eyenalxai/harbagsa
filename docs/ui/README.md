# The 2D layer

The overlay is a technical readout, not a poster. It sits on hard-edged geometry
and never competes with it. Square corners, device-pixel hairlines, two hues, and
one accent that means "this row". Nothing moves.

The type has to carry the whole personality, because nothing else does.

Fourteen files in `src/renderer` draw the overlay. `src/renderer/ui_theme.odin`
holds the tokens. `src/ui/ui.odin` holds the data the game hands over.
`src/renderer/hud_rows.odin` lays rows out, `src/renderer/hud_slider.odin` draws
the slider row, `src/renderer/hud_menu.odin` builds the settings panel and its
legend, and `src/renderer/hud.odin` draws the status panel, capture hint, and
crosshair. `src/renderer/overlay.odin`,
`src/renderer/overlay_draw.odin`, and `src/renderer/overlay_pipeline.odin` own
the vertex stream, pass, and pipelines. `src/renderer/text.odin`,
`src/renderer/text_shaper.odin`, `src/renderer/text_atlas.odin`,
`src/renderer/text_atlas_pack.odin`, `src/renderer/text_atlas_resources.odin`,
and `src/renderer/text_atlas_worker.odin` shape, pack, upload, and swap the
coverage atlas. Change a value in the theme, not in a component.

## The layer rule

| Layer | Owns | Must not |
| --- | --- | --- |
| `src/game` | which rows exist, their labels and values | know about colours, sizes, or pixels |
| `src/ui` | the row vocabulary | import anything |
| `src/frame` | passing the view through | add layout |
| `src/renderer` | tokens, layout, drawing | invent content |

A component reads `theme.*`. A literal `[4]f32` colour or a bare pixel size in
`src/renderer/hud.odin`, `src/renderer/hud_menu.odin`,
`src/renderer/hud_rows.odin`, or `src/renderer/hud_slider.odin` is a bug.

## Density

Everything scales from one number: `density = clamp(height / 720, 1, 2)`, where
`height` is the render target in pixels. A 720p window gets density 1, a 1080p
window 1.5, a 1440p window 2. Below 720p it stays at 1 so the smallest supported
window still shows every row. The theme has no density field; `ui_theme_init`
folds the factor into each token, including `menu_min_width`.

Text rasterizes at the scaled pixel size, so the coverage atlas repacks when a
rounded type size or the weight changes. The first build is synchronous at
startup; later changes use the worker. See [type.md](type.md).

## Files

- [type.md](type.md): the five type roles, the weight axis, leading, tracking,
  and the fixed-width number rule.
- [colour.md](colour.md): the ramp, the contrast table, and the alpha rules.
- [spacing.md](spacing.md): the spacing scale, panel anatomy, and hairlines.
- [components.md](components.md): the eight components: the status panel, the
  capture hint, the crosshair, the settings panel, the selection band, the
  legend grid, the rows, and the slider row.
- [states.md](states.md): the six row inputs, the six drawn states, blocked
  rows, and the status note.

## Adding a surface

1. Decide the rows. Each row is a `ui.Row` with a `kind`: `Setting`, `Action`,
   `Metric`, `Detail`, `Slider`, `Header`, or `Divider`.
2. Fill the rows in `src/game`. Format every number into a fixed field.
3. Draw the panel with `rows_measure` and `rows_emit`. Do not measure text by
   hand and do not position rows with per-row offsets.
4. If the surface needs a value the theme does not have, add a token to
   `src/renderer/ui_theme.odin`. Do not inline it.

If the surface needs a kind that does not exist, add it to `ui.Row_Kind` and to
`row_label_style`, `row_value_style`, `row_gap`, `row_height`, and
`rows_emit_row` in the same change. Add it to the `rows_measure` switch too when
it has no label or value to measure. A kind that only part of that set knows
about draws at the wrong height or draws nothing. A kind that draws a control
also adds its emitter and publishes its travel rect for the pointer. The
`Slider` does that in `src/renderer/hud_slider.odin`; `menu_slider_rect` exposes
the same rect before the first draw.

## Rules that are easy to break

- A panel is square. No corner radius, no shadow, no gradient.
- Depth is one surface step plus a hairline ring. Never a blur.
- Selection is the raised surface plus the accent bar. Never a colour change on
  the text alone, and never a bright band behind white text.
- Every changing number is mono, in a fixed field. See [type.md](type.md).
- A `Slider` is a settings control, not a selection state. Its filled track and
  knob show the value; `accent` still means selection.
- The capture hint sits below the crosshair, never across it.
- The status panel, the capture hint, and the crosshair are hidden while the
  menu is open; the menu replaces them.
