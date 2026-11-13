# Review

Run this before a visual change lands. It turns "does this look right" into a
pass with a fixed order and reproducible evidence.

## Evidence

A review works from a capture, not a memory. Use the harness with a scenario
that captures the view under review:

```sh
./bin/harbagsa-agent run <scenario>.json --out runs/design-review
```

Point the review at `runs/design-review`. Do not commit the PNG. The repository
bans images, and a run directory is reproducible from its scenario.

For a UI change, start with `scenarios/rune-ui.json`, `rune-menu.json`,
`rune-palette.json`, and `rune-fx.json`. If the change needs a view that no
scenario covers, add the scenario in the same change. The harness is part of the
feature.

## Subtract first

Before the ordered check, walk every new element and ask what breaks if it is
gone. Delete what does not break. The common survivors are a divider that
spacing already separates, a caption that restates a title, and an icon that
repeats a label.

## Flag on sight

- A colour literal outside `ui/shim/src/theme.rs` or the game's content data.
- A type size, font file, atlas, or layout pass in the Odin tree.
- A vertex buffer, shader, or draw call added for the 2D layer.
- `accent` on anything but the selected row or card bar, the filled slider track, the focus
  ring, and the primary action.
- `text_tertiary` as the label or value of a selectable row or card.
- A fade, slide, or scale that ignores reduce motion. Kit motion is allowed when
  the reduce-motion setting lands it; the status HUD does not animate. The
  rune-fx glow is opt-in and static.
- A new `Row_Kind` without updating both the game and the shim.
- A third hue.
- A player light, or an emissive spider part that is not an eye or one of the two
  abdomen marks.
- A foot that hovers above the floor or sinks through it.
- A camera that crosses a wall, the floor, or a ceiling.
- A row value whose width changes.
- `view.fx` turned on by default.

## Order

The order is the triage order. A broken interaction outranks a weak colour.

1. **Keyboard only.** Every action is reachable from the keyboard. The pointer is
   an addition: it can click a palette card, the Place button, or a dialog
   control when the cursor is free, and no action hides behind a hover. The
   Settings dialog controls take the keyboard. The HUD opacity slider takes
   Left and Right.
2. **Fits at 800x600.** The settings dialog and every panel are fully visible at
   the smallest supported window. Rune scales the view; nothing clips.
3. **Contrast on the brightest frame.** Read the text over the brightest lamp
   field the renderer can produce, not over a dim scene. The floors are in
   [colour.md](../ui/colour.md).
4. **Fixed fields.** Every number that changes during play is in a fixed-width
   field. The panel text must not move on a selection or a value change.
5. **One owner of the view.** A UI change touches `src/game` data and
   `ui/shim/src` (the theme and view modules). A change that adds layout,
   colour, or text rendering to `src/ui`, `src/frame`, or `src/renderer` is in
   the wrong layer.
6. **One of the documented components.** A new panel is the status panel, the
   settings dialog, or the palette. Otherwise read
   [README.md](../ui/README.md#adding-a-surface) first.
7. **No new row kind without both sides.** The kind set is closed. A new kind
   must update the game producer and the shim's Rune view in the same change.
8. **Reduced motion.** Kit motion follows the reduce-motion setting; see
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
