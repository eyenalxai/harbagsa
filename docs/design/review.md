# Review

Run this before a visual change lands. It turns "does this look right" into a
pass with a fixed order and reproducible evidence.

## Evidence

A review works from a capture, not a memory. Use the harness and name the
scenario:

```sh
./bin/harbagsa-agent run scenarios/settings-menu.json --out runs/design-review
```

Point the review at `runs/design-review`. Do not commit the PNG. The repository
bans images, and a run directory is reproducible from its scenario.

If the change needs a view that no scenario covers, add the scenario in the same
change. The harness is part of the feature.

## Subtract first

Before the ordered check, walk every new element and ask what breaks if it is
gone. Delete what does not break. The common survivors are a divider that
spacing already separates, a caption that restates a title, and an icon that
repeats a label.

## Flag on sight

This is the short form of the order below. Use it for a fast pass; use the
order for the full review.

- A literal colour outside `src/renderer/ui_theme.odin`.
- A bare pixel size in `src/renderer/hud.odin`, `src/renderer/hud_menu.odin`,
  `src/renderer/hud_rows.odin`, or `src/ui/layout.odin`.
- `accent` on anything but the selection bar.
- `text_tertiary` as the label or value of a selectable row.
- Any fade, slide, or scale on the overlay.
- A new `Row_Kind` without the five touch points.
- A third hue.
- A value column that moves.

## Order

The order is the triage order. A broken interaction outranks a weak colour.

1. **Keyboard only.** Every action is reachable from the keyboard. The pointer is
   an addition, not a requirement: the Type weight slider takes arrow keys and a
   drag, and no action hides behind a hover.
2. **Fits at 800x600.** The menu and every panel are fully visible at the
   smallest supported window. Nothing clips and nothing is cut.
3. **Contrast on the brightest frame.** Read the text over the brightest sky the
   renderer can produce, not over a dim test scene. The floors are in
   [colour.md](../ui/colour.md).
4. **Fixed fields.** Every number that changes during play is in a fixed-width
   field and drawn in mono. The panel width must not move on a selection or a
   value change; a type-weight change may resize it once.
5. **Token only.** No literal colour and no bare pixel size in
   `src/renderer/hud.odin`, `src/renderer/hud_menu.odin`,
   `src/renderer/hud_rows.odin`, or `src/ui/layout.odin`. The one
   exception is the documented 2 px accent-bar floor. Every other value belongs in
   `src/renderer/ui_theme.odin`.
6. **One of the documented components.** A new panel is a status panel, a capture
   hint, a crosshair, or the settings panel; the selection band, legend, rows,
   and slider are parts of those. Otherwise read
   [README.md](../ui/README.md#adding-a-surface) first.
7. **No new row kind.** The kind set is closed. A new kind must extend
   `row_label_style`, `row_value_style`, `row_gap`, `row_height`, and
   `rows_emit_row`, plus any emitter it draws.
8. **No motion.** The overlay does not animate. See
   [motion.md](motion.md).
9. **Copy rules.** Sentence case in the source, `·` between peers, `×` for
   dimensions, `…` for an ellipsis.
10. **Evidence matches the claim.** The capture shows the thing the change says it
    changed.

## Output

Lead with the verdict on one line: **Ship**, **Changes**, or **Blocked**. Then
three groups, each a table row with what, where (`file:line`), why, and the fix.

- **Blocking**: a broken interaction, a contrast failure, or a claim the capture
  does not support.
- **Should fix**: a real defect that can wait one change.
- **Nits**: optional polish, labelled as optional.

Do not pad the list. A clean change gets "Ship it" with no findings.

## What review is not

Not a redesign. A reviewer fixes defects and records taste-level ideas as a
separate proposal. The week before a demo is the wrong time to change the
palette.
