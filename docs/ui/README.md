# The 2D layer

The overlay is a technical readout, not a poster. It sits on hard-edged geometry
and never competes with it. Square corners, device-pixel hairlines, two hues, and
one accent that means "this row". Nothing moves.

The type has to carry the whole personality, because nothing else does.

`src/ui/ui.odin` holds the data the game hands over, and `src/ui/layout.odin`,
`src/ui/menu_layout.odin`, `src/ui/notice_layout.odin`, and
`src/ui/palette_layout.odin` own the pure layout: rows, the slider rect, the hint
grid, the settings panel, the notice, and the palette grid.
They take a target extent and a `ui.Text_Metrics` adapter, so they run without a
renderer or an atlas. `src/renderer/ui_theme.odin` holds the tokens.
`src/renderer/ui_layout.odin` adapts the theme and atlas to `ui.Text_Metrics`.
`src/renderer/hud_rows.odin` emits rows, `src/renderer/hud_slider.odin` draws the
slider row, `src/renderer/hud_menu.odin` builds the settings panel and its
legend, `src/renderer/hud_notice.odin` draws the notice, and
`src/renderer/hud.odin` draws the status panel and the capture hint. `src/renderer/overlay.odin`,
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
| `src/ui` | the row vocabulary and the pure layout | import a project package |
| `src/frame` | passing the view through | add layout |
| `src/renderer` | tokens, the atlas adapter, drawing | invent content |

A component reads `theme.*`. A literal `[4]f32` colour or a bare pixel size in
`src/renderer/hud.odin`, `src/renderer/hud_menu.odin`,
`src/renderer/hud_rows.odin`, or `src/ui/layout.odin` is a bug.

## Density

Everything scales from one number: `density = clamp(height / 720, 1, 2)`, where
`height` is the render target in pixels. A 720p window gets density 1, a 1080p
window 1.5, a 1440p window 2. Below 720p it stays at 1 so the smallest supported
window still shows every row. `ui_theme_init` stores the factor in the theme and
folds it into every token, including `menu_min_width` and the palette constants
used by `ui.palette_layout`.

Text rasterizes at the scaled pixel size, so the coverage atlas repacks when a
rounded type size or the weight changes. The first build is synchronous at
startup; later changes use the worker. See [type.md](type.md).

## Files

- [type.md](type.md): the five type roles, the weight axis, leading, tracking,
  and the fixed-width number rule.
- [colour.md](colour.md): the ramp, the contrast table, and the alpha rules.
- [spacing.md](spacing.md): the spacing scale, panel anatomy, and hairlines.
- [components.md](components.md): the eight components: the status panel, the
  capture hint, the notice, the settings panel, the selection band, the legend
  grid, the rows, and the slider row.
- [states.md](states.md): the six row inputs, the six drawn states, blocked
  rows, and the status note.

## The object palette

The debug object palette is a bottom dock, not a menu: the scene and the status
panel stay visible. `ui.palette_layout` owns the geometry: a
6x2 grid of `PALETTE_CARD_SIZE` cards in a `PALETTE_PANEL_WIDTH` x
`PALETTE_PANEL_HEIGHT` panel, centred with `spacing.xl` below it, plus a preview
pane and a footer of key hints. The draw and the hit test read that one layout; no file
repeats the numbers. On a shorter target the top clamps to
`spacing.md`; the palette never clips at a supported size.

Twelve cells are laid out. The catalog fills the first cells; the rest draw only
a hairline frame, return no hit, and read as empty. A filled cell is a card: an
isometric thumbnail, the short name, and the number key. The selected card is
`surface_raised` plus a two-pixel `accent` bar on its leading edge, the same
signal as a selected menu row.

The preview is a larger isometric box, the full name, the size in `W × H × D m`,
the body, the optional light line, and the object count. The isometric box is
three HUD quads from one pure projection helper; it is not a render pass or an
image. Object colour is content, the chrome uses the theme tokens, and the ramp
pitch tilts the box so its true proportions show. See
[components.md](components.md#object-palette).

The capture hint is suppressed while the palette is open. The draw and the card
hit test read the same `palette_layout`; a normalized pointer maps to a card
index or `-1`, including the empty cells.

## The debug inspector

The debug inspector is the existing top-left status panel with object rows. It
shows the selection as `prefab # id`, the object count and capacity, and the
selected object's body, size, position, yaw, snap, light kind and values, the
active light count against the lamp count, and the bake status. The placement
rows replace it while the placement tool is armed and add the next lamp kind,
light, and bake status. The light line is always formatted into the same fields,
so a cold selection does not resize the panel.

Every changing number uses `Row.numeric` and a fixed field, exactly as the
player rows do. The panel width must not move when the selection changes, so
the selection name is padded to a fixed column and the position uses the debug
camera's two extra columns. The panel keeps its width across every prefab and the empty
selection.

## Adding a surface

1. Decide the rows. Each row is a `ui.Row` with a `kind`: `Setting`, `Action`,
   `Metric`, `Detail`, `Slider`, `Header`, or `Divider`.
2. Fill the rows in `src/game`. Format every number into a fixed field.
3. Measure with `ui.rows_layout` (or `ui.menu_layout`) and draw with
   `rows_emit`. Do not measure text by hand and do not position rows with
   per-row offsets.
4. If the surface needs a value the theme does not have, add a token to
   `src/renderer/ui_theme.odin`. Do not inline it.

If the surface needs a kind that does not exist, add it to `ui.Row_Kind` and to
`row_label_role`, `row_value_role`, `row_gap`, and `row_height` in
`src/ui/layout.odin`, and `rows_emit_row` in `src/renderer/hud_rows.odin` in the
same change. Add it to the `rows_layout` switch too when it has no label or
value to measure. A kind that only part of that set knows about draws at the
wrong height or draws nothing. A kind that draws a control also adds its emitter
and returns its travel rect in the layout. The `Slider` does that in
`src/ui/layout.odin`; input and draw both read that one rect.

## Rules that are easy to break

- A panel is square. No corner radius, no shadow, no gradient.
- Depth is one surface step plus a hairline ring. Never a blur.
- Selection is the raised surface plus the accent bar. Never a colour change on
  the text alone, and never a bright band behind white text.
- Every changing number is mono, in a fixed field. See [type.md](type.md).
- A `Slider` is a settings control, not a selection state. Its filled track and
  knob show the value; `accent` still means selection.
- The capture hint sits on the bottom margin, clear of the spider.
- The status panel, the notice, and the capture hint are hidden
  while the menu is open; the menu replaces them.
