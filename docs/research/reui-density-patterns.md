# Density and layout for the 1280x720 Rune overlay

- **Date:** 2026-11-12
- **Status:** Research complete. Current state only. No source changes.
- **Scope:** layout, density, and usability. Brand colour is out of scope; colour
  is discussed only where it changes readability.
- **Evidence base:** the three named captures, a fresh harness reproduction of
  all three, the local ReUI template cache, and the repo's UI/design docs.

## Question

Which density and layout rules should a 1280x720 game overlay borrow from dense
web apps, and which should it reject because the overlay is a game HUD over a
scene? What concrete density spec, four surface layouts, and interaction
checklist should replace the current overlay, and which single visual direction
should it follow?

Sub-questions answered below:

1. Borrow versus reject.
2. Concrete density spec: widths, padding, rows, headers, gaps, controls, type,
   radii, borders, shadows; compact HUD and comfortable settings.
3. Layouts for the status HUD, settings dialog, palette grid with preview, and
   right-side debug inspector; what fits at 1280x720 without scrolling.
4. Pointer and keyboard interaction checklist, with table stakes marked.
5. Anti-patterns in the current overlay, from captures and docs.
6. One recommended visual direction.

## Answer

Short version: borrow the web app's **spacing scale, row densities, section
grouping, control sizes, and state model**. Reject its **page chrome, card
decoration, page-level scrolling, and dashboard scale**. The current overlay
cannot be judged on density yet: the panel surface is painted at the wrong size,
the settings menu and palette do not form a panel at all, and the previous
surface remains visible when a new one opens. Those are layout/paint defects
first; the density numbers below assume they are fixed.

All numbers are Rune points at a 720p target. Rune scales the whole view by
`clamp(target_height / 720, 1, 2)`, so the same numbers become 1.5x at 1080p and
2x at 1440p. Values are design targets, not measurements of the current build.

### 1. What to borrow, what to reject

#### Borrow

| Rule | Why it transfers | Limit in the overlay |
| --- | --- | --- |
| A 4-point spacing grid with a fixed rung set (2, 4, 6, 8, 12, 16, 20, 24, 32) | ReUI templates get their calm rhythm from a small, repeated set, not from per-component values | Stop at 32; the overlay has no page-level 48/64 bands |
| Three row densities: 24 compact, 32 dense list, 40 comfortable | A HUD or inspector needs 24, a dense list 32, a settings row 40; one density cannot serve all three | Never use 48+ rows; the inspector has 12 rows |
| Section grouping with a header band and hairline separators | Atlas preferences and Strata settings both group related rows; this is the strongest usability gain over the current flat list | Group by task (Display, Interface, Controls), not by data type |
| Label left, control or value right, on one baseline | Atlas `SettingRow` and Strata `SettingRow` both do this; it makes scanning a column of labels fast | Long values (position triples) get their own value line |
| 32-point default control height, 28 compact, 36 primary | Atlas button/input/select defaults are all 32; 28 and 36 are the existing small/large rungs | The game's 720p view should not use the web's 40/44 heights |
| 3-point focus ring plus a border change | ReUI repeats this on buttons, inputs, selects, switches, and toggles; it is the one state treatment that is consistent everywhere | Use 2 points at 720p to keep the ring inside tight rows |
| Pressed = 1-point translate, disabled = 50% opacity | ReUI's `active:translate-y-px` and `disabled:opacity-50` are small, legible state changes | No transitions; the overlay swaps in one frame |
| Tabular numerals and a mono face for values | Atlas metric tiles use `tabular-nums`; the game already uses Geist Mono for numeric values | Mono only for values, never labels |
| Fixed header/footer with one scrolling body | Pulse's detail sheet and Atlas dialogs both keep actions out of the scroll region | Only the settings body and the inspector body scroll; the HUD never scrolls |
| Right-side inspector as a narrow sheet | Pulse's sheet is 30rem, Tempo's is 29rem, both inset 1rem; a 340-point game inspector is the same pattern at game scale | Do not use the 464-480 sheet width in the game; 340 is enough for label + value |
| Empty state as text plus one action | ReUI ships an `empty` primitive; a game panel still needs a sentence, not a blank region | No illustrations in the overlay |

#### Reject

| Rule | Why it does not transfer |
| --- | --- |
| 250-point sidebar, 64-point app header, breadcrumbs, workspace switcher | The overlay is not an app shell. It would consume 25% of the width and permanently cover the scene |
| Page-level vertical scroll and an 80rem content grid | The overlay is a fixed viewport. Each panel either fits or scrolls its own body; the scene never scrolls |
| 16-point body text and 16-20-point titles as the default | At 720p, 16-point text makes a 12-row inspector ~320 points tall; 40-point rows would make a 6-row settings dialog 500+ points tall. Use 12/13 for labels and 18 for the dialog title |
| Four-up metric card grids, sparklines, badges, KPI tiles | A dashboard is the product; the HUD is an annotation on the product. One readout column is enough |
| `rounded-xl` cards, 1px rings plus shadows, gradients, glass | The game's panels are rectangles with hairlines; shadows and rounded panels are banned by the design docs, and they obscure the scene |
| 40-48-point rows everywhere | The current 26.5-point HUD pitch is already close to the right density; 40 would double the HUD height for no gain |
| A description under every row | It doubles row height. Use a short label and a value; put the explanation in one line under the section, or in the status line for the selected row |
| Hover-only menus, hover-expanded navigation, tooltip-only values | The pointer is captured during play; hover cannot be an affordance. Hover is an enhancement, never the only path |
| Light/dark theming and a five-hue semantic palette | There is one overlay over a variable scene. One surface scale and one accent are enough; a third hue is banned |
| 100-200ms transitions on every control | The overlay must not animate. State changes happen in one frame; use fill/ring changes, not tweens |
| A select popover for a two-option choice | A segmented control is faster and has fewer layers; reserve popovers for long lists |
| A switch for a two-state mode that changes the window | A switch implies an immediate, low-risk toggle. Window mode is a segmented choice or a button, with the result visible in the value |
| Disabled controls with no reason | A game HUD should prefer a blocked row that explains itself over a silent disabled control |

### 2. Density spec

#### Global tokens

| Token | Value | Use |
| --- | --- | --- |
| `space-0` | 2 | Row gap in the compact HUD; hairline offset |
| `space-1` | 4 | Inner control gap; slider track inset |
| `space-2` | 6 | Tight group gap |
| `space-3` | 8 | Section gap in the HUD; button gap |
| `space-4` | 12 | Compact panel padding; comfortable row gap before a section |
| `space-5` | 16 | Comfortable panel padding; group padding; dialog header padding |
| `space-6` | 20 | Dialog outer padding |
| `space-7` | 24 | Outer margin; section header height |
| `space-8` | 32 | Maximum gap; empty-state block |

Radii: panels `0`; group boxes `0`; buttons, inputs, selects, segmented controls
`4`; the bottom action buttons `6`; the switch track and thumb are full pills;
the slider thumb is `7` (a 14-point circle). The no-radius rule is deliberate:
the scene is hard-edged boxes, and a rounded panel would read as a different
product.

Borders: one hairline at roughly `#59616B` at 25% (the existing token). A selected
row adds a 2-point accent bar on its leading edge and a 4-6% fill lift. No
shadow, no gradient, no glow. Focus adds a 2-point accent ring at 80% with a
1-point offset and a 1-point dark inner ring so the ring survives over a bright
floor.

Surface opacity: HUD 96%; inspector 96%; settings dialog 98%; scrim 55-62%.
The current 94% HUD is not opaque enough over the brightest lamp field; verify on
the brightest frame, not on a dim one.

#### Compact HUD

| Property | Value |
| --- | --- |
| Panel width | 320 (player status); 340 (debug inspector) |
| Outer inset | 12 from the target edge |
| Padding | 12 |
| Row gap | 2 |
| Section gap | 8 |
| Row height | 24 (single line) |
| Header row | 24 |
| Section header | 24 (11/16, semibold, uppercase, `0.04em`) |
| Divider | 1-point line with 7 points of surrounding space |
| Type | Title 13/18 semibold; label 12/18; value 12/18 mono; caption 11/16 |
| Panel height, 6 rows | 158 |
| Panel height, 12 rows | 334 |
| Panel height, 9 placement rows | 256 |

The 6-row player HUD at 320x158 fits at (12, 12), ends at y=170, and leaves the
rest of the 720-point height to the scene and the bottom action row. The 12-row
debug inspector at 340x334 is better placed on the right (see 3d) than in the
top-left, because the top-left position collides with the player HUD.

#### Comfortable settings dialog

| Property | Value |
| --- | --- |
| Panel width | 520 (max 560) |
| Outer padding | 20 |
| Header | 56 (title 18/24 semibold, subtitle 12/16 secondary, 1-point bottom rule) |
| Section header | 32 (12/16 semibold, uppercase, `0.04em`, secondary) |
| Section padding | 16 horizontal |
| Row height | 40 (two-line row 52) |
| Slider row | 48 (20 label/value + 4 track + hit area) |
| Section gap | 12 |
| Footer | 56 (1-point top rule, right-aligned actions, 8 gap) |
| Panel height, 5 settings rows + 3 headers + legend + footer | 512 |
| Max height | 576 at a 600-point target; body scrolls above that |

The width is between Pulse's 480-point sheet and Atlas's 544-point sheet. It is
wide enough for a label column of 160-180 points, a control column of 240-280,
and a 480-point inner content width for the slider. It is narrow enough to keep
the scene visible on both sides at 1280.

#### Control sizes

| Control | Compact | Comfortable | Notes |
| --- | --- | --- | --- |
| Button | 28 high | 32 high; primary 36 | Horizontal padding 10 (compact) / 12 (comfortable); 4/6 radius |
| Icon button | 28x28 | 32x32 | 16-point icon, centered |
| Input / select | 28 high | 32 high | 8/10 horizontal padding; 4 radius |
| Switch | 18x32 | 20x36 | Pill; invisible hit area at least 44x36 |
| Segmented control | 26 high | 30 high | 2-4 items, 1-point divider, 4 radius; selected item = raised fill |
| Slider | Track 4, thumb 12 | Track 4, thumb 14 | Hit area 24/28 high; thumb is the only round control besides the switch |
| Checkbox | 14 | 16 | Hit area 28/32; 4 radius |
| Row hit area | Full row width | Full row width | No text-only hit rectangles |
| Bottom action row | 64 minimum | 64 minimum | Padding 16, gap 8, buttons centered; grows with notice/hint lines |

The switch is the one control that cannot be square: a pill track is the
recognizable form. If the "only rounded edge" ban is kept literally, the switch
must become a two-item segmented control instead. That is a real choice, not a
detail; see Conflicts.

#### Type scale

| Role | Compact HUD | Comfortable settings | Notes |
| --- | --- | --- | --- |
| Title | 13/18 semibold | 18/24 semibold | The HUD's header row is its title |
| Section | 11/16 semibold uppercase | 12/16 semibold uppercase | `0.04em` tracking; tertiary/secondary |
| Label | 12/18 | 13/18 | Secondary; primary when selected |
| Value | 12/18 mono | 13/18 mono | Primary; tabular figures |
| Big value | 18/22 mono | 20/24 mono | Only one per panel, if any |
| Caption | 11/16 | 11/16 | Tertiary; never a selectable row's label |
| Button | 12/16 medium | 13/18 medium | Sentence case |
| Palette card title | 12/16 medium | 13/18 medium | Short name |
| Palette card subtitle | 11/16 | 11/16 | Full name, tertiary |

The current view sets no size at all and relies on Rune's default; the only
variation is the Type weight axis. A size scale is required for hierarchy. Do
not use more than five sizes in one panel.

#### Radii, border, and shadow treatment

| Surface | Radius | Border | Shadow |
| --- | --- | --- | --- |
| HUD panel | 0 | 1-point hairline | None |
| Inspector panel | 0 | 1-point hairline | None |
| Settings dialog | 0 | 1-point hairline | None; the scrim separates it |
| Group box | 0 | 1-point hairline or separators only | None |
| Row | 0 | 1-point separator between rows | None |
| Button | 4 (6 for bottom actions) | 1-point border on secondary; transparent on primary | None |
| Input/select | 4 | 1-point hairline | None |
| Segmented control | 4 | 1-point hairline; 1-point divider | None |
| Switch | Pill | 1-point transparent | None |
| Slider thumb | 7 | 1-point dark ring | None |
| Focus | 2-point accent ring | 1-point offset + 1-point dark inner | None |

### 3. Layouts at 1280x720

#### (a) Top-left status HUD

```
(12,12)  320 wide
┌────────────────────────────────┐
│ Spider · Walk           13/18  │ 24
│ Speed            0.0 m/s       │ 24
│ Feet             8 planted     │ 24
│ ─────────────────────────────  │ 1 + 7
│ Grounded         yes           │ 24
│ Position  X 0.0 Y 0.0 Z 14.0   │ 24
└────────────────────────────────┘
```

Size: 320x158. Position: 12,12. Fits without scrolling. The 12-row debug
inspector is 340x334 and belongs on the right, not here. If both the player HUD
and the inspector must be visible, keep the HUD at 320 and the inspector at 340;
the pair uses 660 of 1280 points and still leaves 620 for the scene. At 800x600,
collapse the player HUD to a 3-row strip (header, speed, feet) while the
inspector is open.

Do not put the notice, capture hint, or action row inside the panel. They belong
to the bottom action column, as they do today. The panel is a readout, not a
container for actions.

#### (b) Centered settings dialog with grouped sections

```
                    scrim 55-62%
        ┌──────────────────────────────────┐ 520
        │ Settings                      ×  │ 56
        │ Window, interface, and controls  │
        ├──────────────────────────────────┤
        │ DISPLAY                          │ 32
        │ Window mode          Borderless  │ 40
        │ Display              Display 1   │ 40
        │ Resolution           1280×720    │ 40
        │ INTERFACE                        │ 32
        │ Type weight       ─────●──── 600 │ 48
        │ Sprint input     [ Hold | Toggle ]│ 40
        │ CONTROLS                         │ 32
        │ WASD move · Space jump · Esc close│ 32
        ├──────────────────────────────────┤
        │                          [Resume]│ 56
        └──────────────────────────────────┘
```

Size: 520x512. Centered. Fits at 720 with 104 points above and below; fits at
600 with 44 points above and below. No scroll for five settings rows.

Three changes from the current menu:

- Move `Resume` out of the row list and into the footer. It is an action, not a
  setting. The current list mixes a command with five values, which is why the
  selected row and the primary action compete.
- Group by task: Display, Interface, Controls. The current list has one divider
  and a "Controls" header; that is a legend, not a section structure.
- Reduce the hint legend to two lines. The current 12 hints at three per line
  are four lines; the debug set is 22 hints and eight lines.

Header close button: 32x32, ghost, `×`, top-right at 16,16. `Esc` is equivalent.
The footer primary is `Resume`; no second `Close` button in the dialog. The
bottom action row is hidden while the dialog is open.

#### (c) Object palette grid with 11 prefab cards and a preview

At 1280, use a 4x3 card grid. The 11th card leaves one empty cell, which is fine;
do not invent a 12th prefab.

```
        ┌────────────────────────────────────────────┐ 780
        │ Object palette                  11 prefabs │ 40
        ├──────────────────────────┬─────────────────┤
        │ [Crate] [Small] [Wide]   │ Preview         │
        │ [Block] [Platform] [Ramp]│ ┌─────────────┐ │
        │ [Pillar] [Wall] [Lamp]   │ │ colour chip │ │
        │ [Panel] [Beacon] [ ]     │ │ 1.0×1.0×1.0 │ │
        │                          │ │ dynamic     │ │
        │                          │ │ light line  │ │
        ├──────────────────────────┴─────────────────┤
        │ 1-9 select  Arrows move  Enter pick  Esc   │ 36
        └────────────────────────────────────────────┘
```

Size: 780x456. Centered at (250,132). Fits at 1280x720 with 250 points on each
side and 132 above/below. Cards are 104x100 with a 12-point gap; the grid is
452x324; the preview is 280x324.

Card contents, top to bottom: a 32x24 colour chip (the prefab colour, already in
the data), the short name at 12/16, the full name at 11/16 tertiary, and a
16-point key badge in the top-right. The selected card gets the existing 2-point
accent leading bar and a 4-6% fill lift. Hover gets a 4% lift and a pointer
cursor; focus gets the 2-point ring. The preview shows the name, dimensions, body
mode, and light line. Do not promise a 3D thumbnail: the shim draws rectangles
and text today and has no prefab thumbnail path, and it does not read the palette
colour or size fields.

At 800x600 the 780-point panel does not fit with a 12-point margin. Fall back to
3 columns x 4 rows: card 104x88, grid 324x388, preview 260x388, panel 632x520.
That fits at 800x600 with 84 points of horizontal margin and 40 vertical.

The current palette is a flat row list with no colour, no dimensions, and no
preview. The data for a preview exists (`Palette_Item.color`, `half_extents`,
`key`, `light_line`, `size`, `count`) but the Rune view maps only `short` and
`name`; the shim's colour and key fields are marked reserved and unread, and the
size/count strings are unread. A grid and preview require extending the view,
not new game data.

#### (d) Right-side debug inspector with object and lamp controls

```
                                              ┌──────────────────────┐ 340
                                              │ DEBUG · INSPECTOR     │ 24
                                              ├──────────────────────┤
                                              │ SELECTION            │ 24
                                              │ Crate          # 003 │ 24
                                              │ Objects            6 │ 24
                                              │ TRANSFORM            │ 24
                                              │ Body          dynamic│ 24
                                              │ Position             │ 24
                                              │  X 0.0  Y 0.0  Z 0.0 │ 24
                                              │ Yaw           0.0°   │ 24
                                              │ LIGHT                │ 24
                                              │ Kind     [Static|Dyn]│ 28
                                              │ Colour  ● ● ● ● ● ●  │ 24
                                              │ Intensity ───●── 1.0 │ 40
                                              │ Range     ───●── 6 m │ 40
                                              │ SCENE                │ 24
                                              │ Lights    3 / 3      │ 24
                                              │ Bake      current    │ 24
                                              └──────────────────────┘
```

Size: 340x500. Anchor right 12, top 12; ends at y=512. At 1280x720 it fits
without scrolling. At 800x600 it also fits (500 + 12 = 512), but it leaves only
about 116 points of scene between the left HUD and the panel; hide the player HUD
or collapse it to three rows in that case.

The inspector is not a dialog: no scrim, 96% fill, 1-point hairline. It replaces
the debug rows that currently live in the top-left status panel. The placement
rows already replace the inspector while the placement tool is armed; keep that
rule. Hide the inspector while the palette or settings is open. If both the
player HUD and the inspector are visible, the HUD stays at 320 and the inspector
at 340, and they never overlap.

Lamp controls:

- Kind: a two-item segmented control, `Static fixture` / `Dynamic lamp`. This is
  a two-state choice with immediate visual consequence; a switch would hide the
  fact that the body mode follows the kind.
- Colour: six 20x20 swatches with a 1-point selected ring. The game's light
  colour names are a fixed set; no colour picker.
- Intensity: a slider, 0-8, step 0.1, value right-aligned in mono. Track 4,
  thumb 14, hit area 28.
- Range: a slider, 0-20 m, step 0.5, value right-aligned in mono.
- Active light count: one readout, `3 / 3`, not a slider or a badge.

The current `Hud` row model has no selected index and no slider action path. The
inspector's sliders need a new interaction path: either a `Hud` selection index
plus a ratio per row, or a direct pointer-drag path that returns a setting
action. The existing action queue has only `Close_Menu`, `Toggle_Debug`, and
`Palette_Select`; it cannot express "set intensity to 4.2". This is the largest
implementation gap behind the design.

#### Fit summary at 1280x720

| Surface | Size | Position | Fits without scrolling? |
| --- | --- | --- | --- |
| Player HUD | 320x158 | 12,12 | Yes |
| Debug inspector | 340x500 | right 12, top 12 | Yes |
| Settings dialog | 520x512 | centered | Yes |
| Palette | 780x456 | centered | Yes |
| Bottom action row | 1280x64 | bottom, padding 16 | Yes |
| Palette at 800x600 | 632x520 (3x4) | centered | Yes |
| Settings at 800x600 | 520x512 | centered | Yes, 44-point margins |

### 4. Interaction and usability checklist

`Table stakes` means the overlay should not ship without it. `Current` describes
the code and captures inspected here, not a live window.

| Interaction | Table stakes | Spec | Current |
| --- | --- | --- | --- |
| Hover | Yes (pointer) | Fill +4-6%, pointer cursor, no layout shift, no transition. Hover is not selection | Missing: only `on_press`; no hover state |
| Focus ring | Yes | 2-point accent ring at 80%, 1-point offset, 1-point dark inner ring; `focus-visible` only | Missing: no focus model, no ring |
| Pressed | Yes | Fill -8% or 1-point downward translate; release inside commits, release outside cancels | Missing: press produces an action but no visual state |
| Drag | Yes (sliders) | Pointer capture on thumb or track; value from x; live update; Esc cancels and restores; release commits | Missing by design: "no drag path" |
| Wheel | Yes (scroll) | 48 points per notch, only over a scrollable body; never changes a value; never scrolls the scene | Missing: no scroll container |
| Hold repeat | Yes (slider/stepper) | 350ms delay, 50ms interval; arrows only; not for Enter, Esc, Tab, or destructive actions | Missing: "no key repeat" |
| Blocked | Yes | Row stays focusable; value secondary; inline reason under the section; Enter repeats the reason | Partial: value colour and a 2s status note |
| Disabled | Yes | 40% opacity, no hover, out of tab order, reason in the section caption | Missing: no disabled state beyond blocked |
| Empty state | Yes | Two lines: what is empty and one action; no blank panel | Missing: palette always has 11; inspector shows `None # 000` |
| Tooltip | No (enhancement) | 400ms delay, 12/16 text, max 240 wide, 8 offset; never the only place a value lives | Missing |
| Close / Esc | Yes | Esc closes the topmost layer only; a drag cancels before the panel closes; focus returns to the opener | Present for the menu; no drag layer |
| Scroll | Yes | Body only; 6-point bar, 40% thumb; PageUp/PageDown, Home/End; no scroll chaining | Missing |
| Hit target | Yes | 32x32 minimum, 40x40 primary, 44x44 touch; full-row hit area; switch hit area 44x36 | Partial: buttons only; settings rows are text-only |
| Cursor | Yes | Pointer on clickable, grab/grabbing on slider, default on labels | Missing |
| Tab order / focus trap | Yes | Visual order; skip headers; trap inside the dialog; initial focus on the first control | Missing: Tab is mapped but there is no focus model |
| Selection vs focus | Yes | Selection = raised fill + 2-point bar; focus = ring; both can coexist | Partial: selection only |
| Value commit / cancel | Yes | Settings apply live; drag commits on release; Esc restores the pre-drag value; no confirm dialog | Missing |
| Contrast | Yes | 4.5:1 text, 3:1 ring, measured on the brightest frame the scene can produce | Unverified: the captured pixels do not match the authored table; re-measure after the encoding fix |
| No hover-only action | Yes | Every pointer action has a keyboard equivalent | Present: the keyboard path exists |
| No animation | Yes (game) | One-frame state swap; no transitions, fades, slides, or scales | Present: the overlay does not animate |

Additional table stakes that are easy to forget:

- A click on a row selects it; a click on the control inside the row does not
  also select the row. Stop propagation at the control.
- Pressing Enter on a slider does not submit the dialog; it activates the
  default action only when focus is on a button.
- Space toggles a switch; Enter opens a select; Up/Down changes a segmented
  control only when it is focused.
- A blocked row is not the same as a disabled row: blocked rows stay reachable
  so the reason can be read.
- Status text must not be the only signal for a blocked action; pair it with a
  persistent inline note for the section.
- The action row's primary button must do something. The current `Close` is the
  accent primary in the status view and the game ignores it.

### 5. Anti-patterns in the current overlay

These are observed in the named captures and in a fresh reproduction of the
same three scenarios. Coordinates are read from the 1280x720 PNGs; they are
approximate where glyph bounds are involved.

1. **The panel surface does not cover its content.** In `ui-current`, the HUD
   fill spans x=12-390, y=12-52: a 380x40 block. The rows continue to y≈138, so
   `Speed`, `Feet`, `Grounded`, and `Position` sit on the scene with no panel
   behind them. The fill looks like padding plus the first row, not the column.
   This is the single worst defect; every density judgement above assumes it is
   fixed.

2. **The settings menu is not a panel.** In `menu-current`, menu rows occupy
   x≈16-420, y≈88-320; `Settings` is at x≈800, y≈635 and `Borderless` at x≈900,
   y≈661. The title and the first row are detached from the rest of the list, and
   there is no 430-point surface. The code intends a centered 430-wide panel, so
   the capture and the intent disagree.

3. **The HUD is still drawn under the menu.** `Grounded` and `Display 1` overlap
   at y≈150; `Position` and `Resolution` overlap at y≈170. The menu view is
   supposed to return before the status panel, and the docs say the status panel
   is not drawn while the menu is open. The capture shows both, so the menu is
   compositing over the previous surface or drawing a second copy.

4. **The palette surface is nearly full-screen and its title is detached.** In
   `palette-current`, the tinted surface covers x≈64-1278, y≈0-704. The rows are
   at x≈100; `Object palette` is at x≈765, y≈580; the note `dynamic` is at x≈83,
   y≈454; the hints are at x≈83, y≈485. A 430-wide centered panel was intended.
   The result reads as a full-screen text overlay, not a tool panel.

5. **There is no hover, press, or focus feedback.** The docs state the pointer
   may click a palette row or an action button and that there is no hover, no key
   repeat, and no drag. The shim uses `on_press` for the two buttons only; the
   menu rows have no press handler. A keyboard user cannot see where they are,
   and a pointer user gets no confirmation that a row is interactive.

6. **The slider has no knob and no drag.** The track is 4 points tall, the
   unfilled track is white at 20%, and the filled width is `ratio * 390`. There
   is no thumb, no tick, and no drag path. The 390 constant is also wrong for the
   430-wide panel with 16-point padding: the inner width is 398, so at 100% the
   fill stops 8 points short, and any padding change makes it worse.

7. **The settings are one flat list.** The menu has five settings, a divider, a
   `Resume` action, and a `Controls` header. There is no Display/Interface/
   Controls grouping. A divider is not a section, and a legend header is not a
   section title.

8. **There is no type hierarchy.** The shim sets no size and no tracking; it
   uses Rune's default text everywhere and varies only the weight axis. The
   title, section header, labels, and values are the same size. The title is
   centered with spacers and is visually no stronger than a row.

9. **The hint grid is too dense.** The menu carries 12 hints in normal mode and
   22 in debug mode, three pairs per line, with a 16-point gap. That is four or
   eight lines of key/action text, each pair unaligned with the next. In the
   debug menu the legend is taller than the settings list it documents.

10. **The buttons are small and stateless.** The measured `Close` button is
    50x32; `Debug` is 55x33. They have 8-point padding and a 6-point radius, no
    hover, no pressed state, and no focus ring. `Close` is the accent primary in
    the status view, but the game ignores it there, so the strongest control on
    screen does nothing.

11. **State coverage is thin.** A blocked row keeps its selection and changes
    only the value to secondary; the reason is a one-line status note that
    disappears after two seconds. There is no disabled state, no empty state, no
    tooltip, and no persistent explanation. The inspector's no-selection state
    is `None # 000`, which is a value, not an instruction.

12. **Pointer hit testing is keyed-element-only.** `element_key_at` returns the
    key of the topmost element whose rectangle contains the point. Only elements
    with a key are clickable: the two action buttons and the palette rows.
    Settings rows and the slider track have no key, so clicking a setting row or
    the track does nothing. The hit rectangle is the keyed element's bounds; the
    unkeyed rows have no hit area at all.

13. **There is no scroll or overflow plan.** The docs ban clipping and say the
    menu fits at 800x600. The debug menu has 22 hints plus eight rows; at 600
    points tall it does not fit with margins. Nothing scrolls, so content either
    clips or overflows. A fixed header/footer with one scrolling body is the
    minimum fix.

14. **The colour table does not describe the captures.** The authored HUD
    surface is `0.06, 0.08, 0.10` at 94% (the table calls it `#0F141A`), and the
    accent is `0.90, 0.69, 0.23` (`#E6B03B`). The captured HUD fill reads about
    `#434E56` and the accent about `#F0D683`. Those captured values match the
    sRGB encoding of the authored linear values (0.06/0.08/0.10 -> about
    68/80/89; 0.90/0.69/0.23 -> about 244/219/132). That points to a linear/sRGB
    mismatch in the overlay path, not a different palette. Do not use the
    contrast table as evidence for the captured image; re-measure after the
    surface and encoding fix.

### 6. Recommended visual direction

**Choose a blend: ReUI's density and grouping inside the game's hard-edged
surface language.** Do not choose the Rune settings-example card stack, and do
not choose the ReUI dashboard as a page.

Why not the card stack:

- A card stack spends 16 points of padding and 14 points of radius per group,
  plus a gap per card. At 720p, five settings rows become a 600+ point column
  and the scene disappears. The game's own design docs already ban rounded
  panels and shadows, so the card stack would require reversing the visual
  direction to gain chrome.
- The current menu's problems are hierarchy and grouping, not a lack of
  containers. A square group with a 32-point header and hairline rows solves
  them at half the vertical cost.

Why not the ReUI dashboard:

- The 250-point sidebar, 64-point header, 80rem content grid, and four-up KPI
  cards are a full-window application architecture. The overlay is an annotation
  on a 3D scene; it cannot own the viewport.
- Dashboard cards are designed to be looked at. The HUD is designed to be
  glanced at while moving. Different reading mode, different density.

What the blend keeps from ReUI:

- The 4-point spacing scale and the small set of rungs.
- The 24/32/40 row densities and the 28/32/36 control heights.
- The section header + hairline separator pattern from Atlas preferences and
  Strata settings.
- The 3-point focus ring (reduced to 2 at 720p), the 1-point pressed translate,
  and the 50% disabled opacity.
- The fixed header/footer, one-scrolling-body sheet pattern from Pulse and Tempo.
- Tabular numerals and mono values.

What it keeps from the game:

- Square panels, 1-point hairlines, no shadows, no gradients.
- One accent, reserved for selection and the primary action.
- No animation.
- Text-first content; no illustrations, thumbnails, or decorative icons.
- The scene stays visible; the settings dialog is the only surface with a scrim.

Six rules to implement the blend:

1. **Square surfaces, hairline structure.** Panels and groups have radius 0 and a
   1-point border; rows are separated by hairlines, not nested cards.
2. **Three densities, no more.** 24 for the HUD and inspector, 32 for dense
   lists, 40 for settings. A row's height is a property of its surface, not a
   global.
3. **One 4-point scale.** 2, 4, 6, 8, 12, 16, 20, 24, 32. No 10, 14, 18, or 22
   unless it is a type line height.
4. **Controls are 28/32/36.** Buttons and inputs at 32, compact at 28, primary at
   36. The switch is 20x36 with a 44x36 hit area. The segmented control is 30.
5. **Two signals for selection, one for focus.** Selection = raised fill + 2-point
   accent bar. Focus = 2-point accent ring + 1-point dark inner ring. Hover is a
   4-6% fill lift and nothing else.
6. **One scroll region per panel.** Fixed header/footer; the body scrolls only
   when it must. The HUD never scrolls. The scene never scrolls.

The result is a dense, readable, web-application-grade control system that still
looks like the game: a hard-edged readout over a hard-edged scene, not a SaaS
dashboard pasted on top of it.

## Evidence

One claim per bullet. ReUI paths are absolute because the templates live outside
the repository.

- **E1.** Atlas uses a 250-point sidebar, a 64-point header, an 80rem content
  cap, 24-point page padding, and a 16-point grid gap.
  `/home/ulezot/.local/share/reui/templates/atlas-admin/components/shell/app-shell.tsx:25,36,40,55`
- **E2.** Atlas buttons are 32 points high by default, with 24/28/36-point
  xs/sm/lg rungs, a 3-point focus ring, a 1-point pressed translate, and 50%
  disabled opacity.
  `/home/ulezot/.local/share/reui/templates/atlas-admin/components/ui/button.tsx:7,24-27`
- **E3.** Atlas cards use 16-point padding, a 16-point gap, `rounded-xl`, and a
  1-point ring; the card title is 16/22 and the description 14.
  `/home/ulezot/.local/share/reui/templates/atlas-admin/components/ui/card.tsx:15,41,53`
- **E4.** Atlas metric tiles use 16-point padding, a 14-point gap, a 13-point
  title, an 11-point uppercase label, a 20/24 tabular value, and a
  `border-t` context row with 10-point top padding.
  `/home/ulezot/.local/share/reui/templates/atlas-admin/features/dashboard/components/metric-tile.tsx:55,60,63,77,87`
- **E5.** Atlas settings rows use 20-point horizontal and 16-point vertical
  padding, a 16-point gap, and a 14-point description.
  `/home/ulezot/.local/share/reui/templates/atlas-admin/features/account/components/setting-row.tsx:37,49`
- **E6.** Atlas preference sections use a 16/10 header band, a 14-point title,
  and hairline separators between rows.
  `/home/ulezot/.local/share/reui/templates/atlas-admin/features/account/components/preferences-settings.tsx:65,152,155,166`
- **E7.** Atlas inputs are 32 points high, 10-point horizontal padding, with a
  3-point focus ring and 50% disabled opacity.
  `/home/ulezot/.local/share/reui/templates/atlas-admin/components/ui/input.tsx:12`
- **E8.** Atlas selects are 32 points high by default and 28 points in the small
  size.
  `/home/ulezot/.local/share/reui/templates/atlas-admin/components/ui/select.tsx:44`
- **E9.** Atlas switches are 32x18.4 (default) or 24x14 (small), with an
  invisible hit area that extends 12 points horizontally and 8 vertically.
  `/home/ulezot/.local/share/reui/templates/atlas-admin/components/ui/switch.tsx:19`
- **E10.** Atlas dialogs default to `max-w-sm` (384), 16-point padding, a
  16-point gap, `rounded-xl`, a 1-point ring, and a black/10 overlay with a
  small backdrop blur.
  `/home/ulezot/.local/share/reui/templates/atlas-admin/components/ui/dialog.tsx:56`
- **E11.** Strata's frame spacing rungs are: `sm` = 12-point horizontal, 14-point
  vertical, 6-point header vertical; `default` = 16/16, 8-point header vertical;
  `lg` = 20/20, 10-point header vertical.
  `/home/ulezot/.local/share/reui/templates/strata-observability/components/reui/frame.tsx:44-49,140`
- **E12.** Strata's settings nav is 160 points wide, with 12/6 tabs and a
  16-point content gap.
  `/home/ulezot/.local/share/reui/templates/strata-observability/features/settings/components/account-settings.tsx:52,67,84,119`
- **E13.** Strata's data grid header is 40 points high; body rows are 40 by
  default and 32 in dense mode; cells are 12/8 or 8/6.
  `/home/ulezot/.local/share/reui/templates/strata-observability/components/reui/data-grid/data-grid-table.tsx:47-52,979,1455,1519`
- **E14.** Strata's segmented toggle sizes are 32/28/36 points high, with a
  4-point gap by default and a 3-point focus ring.
  `/home/ulezot/.local/share/reui/templates/strata-observability/components/ui/toggle.tsx:8,17-19` and
  `/home/ulezot/.local/share/reui/templates/strata-observability/components/ui/toggle-group.tsx:45`
- **E15.** Pulse's ticket detail sheet is 30rem (480) wide, inset 1rem from the
  right/top/bottom, `rounded-xl`, with a 40-point header, 20/16 section padding,
  a 12-point uppercase section label, a 7.5rem label column, 10-point row gaps,
  and a 20/12 footer.
  `/home/ulezot/.local/share/reui/templates/pulse-helpdesk/src/features/tickets/components/ticket-detail-sheet.tsx:58-61,165,169,214,229,266`
- **E16.** Tempo's task sheet is 29rem (464) wide, inset 1rem, with a 24/32/24
  form body and 6.5rem label rows at 16/10 padding.
  `/home/ulezot/.local/share/reui/templates/tempo-tasks/src/features/tasks/components/task-sheet.tsx:648,899,919`
- **E17.** The Rune view scale is `clamp(target_height / 720, 1, 2)`: 720p gets 1,
  1080p 1.5, 1440p 2.
  `/home/ulezot/.t3/worktrees/harbagsa/t3-063166c8/docs/ui/spacing.md:4-6`
- **E18.** The current status panel is 380 wide at (12,12), with 12-point padding
  and a 6-point row gap; the bottom action row is a full-width column with
  16-point padding and an 8-point gap.
  `/home/ulezot/.t3/worktrees/harbagsa/t3-063166c8/docs/ui/spacing.md:32-36`
- **E19.** The current menu is 430 wide, centered, with 16-point padding, an
  8-point gap, 4-point row padding, a 12-point label/value gap, a 2x18 accent
  bar, a 4-point track with `ratio * 390` fill, and three hints per line.
  `/home/ulezot/.t3/worktrees/harbagsa/t3-063166c8/docs/ui/spacing.md:43-50`
- **E20.** The palette reuses the 430-wide menu panel, its padding, and its gap.
  `/home/ulezot/.t3/worktrees/harbagsa/t3-063166c8/docs/ui/spacing.md:54-57`
- **E21.** The design bans rounded panels, shadows, and gradients; the action
  buttons are described as the only rounded edges Rune draws.
  `/home/ulezot/.t3/worktrees/harbagsa/t3-063166c8/docs/ui/spacing.md:67-68`
- **E22.** The design also bans clipping and says the menu fits at 800x600
  because Rune scales the whole view.
  `/home/ulezot/.t3/worktrees/harbagsa/t3-063166c8/docs/ui/spacing.md:74`
- **E23.** The current input model has no hover, no key repeat, and no drag; one
  press is one action.
  `/home/ulezot/.t3/worktrees/harbagsa/t3-063166c8/docs/ui/states.md:89-91`
- **E24.** The slider is a 4-point track with no knob, no tick, and no drag path;
  Left/Right step by 5.
  `/home/ulezot/.t3/worktrees/harbagsa/t3-063166c8/docs/ui/states.md:40-47`
- **E25.** Blocked rows keep their selection and accent bar; only the value moves
  to secondary; the reason is a status note that holds for two seconds.
  `/home/ulezot/.t3/worktrees/harbagsa/t3-063166c8/docs/ui/states.md:31-36,56-71`
- **E26.** The action queue has only `Close_Menu`, `Toggle_Debug`, and
  `Palette_Select`; it has no set-value or slider action.
  `/home/ulezot/.t3/worktrees/harbagsa/t3-063166c8/docs/ui/states.md:75-85`
- **E27.** The shim sets no text size or tracking; it uses Rune's default and
  varies only the weight axis.
  `/home/ulezot/.t3/worktrees/harbagsa/t3-063166c8/docs/ui/type.md:9-11,31-39`
- **E28.** The authored HUD surface is `#0F141A` at 94%, the accent `#E6B03B`,
  and the contrast table is measured on those authored values.
  `/home/ulezot/.t3/worktrees/harbagsa/t3-063166c8/docs/ui/colour.md:12-21,35-40`
- **E29.** The overlay does not animate; the rune-fx glow is opt-in and off by
  default.
  `/home/ulezot/.t3/worktrees/harbagsa/t3-063166c8/docs/ui/README.md:95` and
  `/home/ulezot/.t3/worktrees/harbagsa/t3-063166c8/docs/design/README.md:24-25`
- **E30.** The menu has eight rows: five settings, a divider, a Resume action,
  and a Controls header; it carries 12 hints normally and 22 in debug mode.
  `/home/ulezot/.t3/worktrees/harbagsa/t3-063166c8/src/game/menu.odin:11-17,225-240`
- **E31.** The debug inspector has 12 rows; the placement view has 9; the player
  HUD has 6.
  `/home/ulezot/.t3/worktrees/harbagsa/t3-063166c8/src/game/hud_debug.odin:4-5,53,144-150` and
  `/home/ulezot/.t3/worktrees/harbagsa/t3-063166c8/src/game/hud.odin:7,83`
- **E32.** The catalog has 11 prefabs: crate, small crate, wide crate, block,
  platform, ramp, pillar, wall, lamp, light panel, beacon.
  `/home/ulezot/.t3/worktrees/harbagsa/t3-063166c8/src/game/prefabs.odin:12-24,185`
- **E33.** The palette item already carries colour, half extents, key, light
  line, and emissive; the Rune view maps only the short and full names. The
  bridge carries colour and key, the Rust struct marks them reserved and unread,
  and the shim never reads size or count.
  `/home/ulezot/.t3/worktrees/harbagsa/t3-063166c8/src/ui/ui.odin:52-63`,
  `/home/ulezot/.t3/worktrees/harbagsa/t3-063166c8/src/renderer/ui_bridge.odin:85-101`, and
  `/home/ulezot/.t3/worktrees/harbagsa/t3-063166c8/ui/shim/src/lib.rs:134-164,1019-1040`
- **E34.** The status panel is an absolutely positioned 380-wide column with a
  fill, 12-point padding, and a 6-point gap; the captured fill covers only the
  first 40 points of height.
  `/home/ulezot/.t3/worktrees/harbagsa/t3-063166c8/ui/shim/src/lib.rs:504-507` and
  `/home/ulezot/.t3/worktrees/harbagsa/t3-063166c8/runs/ui-current/frames/ui.png`
- **E35.** The menu is a 430-wide column with a fill and 16-point padding; the
  root centers it over an absolute scrim. The capture shows the title and first
  row detached at the bottom-right and no 430-wide surface.
  `/home/ulezot/.t3/worktrees/harbagsa/t3-063166c8/ui/shim/src/lib.rs:937-941,1010-1016` and
  `/home/ulezot/.t3/worktrees/harbagsa/t3-063166c8/runs/menu-current/frames/menu.png`
- **E36.** Menu rows are keyed only when a key prefix is supplied; the palette
  supplies one, the settings menu does not. Hit testing scans element rectangles
  in reverse and returns only an element key.
  `/home/ulezot/.t3/worktrees/harbagsa/t3-063166c8/ui/shim/src/lib.rs:976-978,1040-1049`
- **E37.** The slider fill is hard-coded to `ratio * 390` while the panel's inner
  width is 398 (430 minus 32).
  `/home/ulezot/.t3/worktrees/harbagsa/t3-063166c8/ui/shim/src/lib.rs:938-939,981-985`
- **E38.** The menu hint grid uses three pairs per line and a 16-point gap.
  `/home/ulezot/.t3/worktrees/harbagsa/t3-063166c8/ui/shim/src/lib.rs:997-1007`
- **E39.** Rune's parity matrix claims Taffy layout, CSS semantics, input
  routing, focus, and the hit list are available inside Rune; the shim uses only
  `on_press` and a manual hit scan.
  `/home/ulezot/.t3/worktrees/harbagsa/t3-063166c8/docs/research/rune-integration-plan.md:261-271` and
  `/home/ulezot/.t3/worktrees/harbagsa/t3-063166c8/ui/shim/src/lib.rs:543-576,1043-1049`
- **E40.** The review order puts keyboard reachability first, then fitting at
  800x600, then contrast on the brightest frame, then fixed fields, then one
  owner of the view, then one of the documented components, then no motion.
  `/home/ulezot/.t3/worktrees/harbagsa/t3-063166c8/docs/design/review.md:48-70`
- **E41.** The three scenarios capture at 1280x720 with the HUD on.
  `/home/ulezot/.t3/worktrees/harbagsa/t3-063166c8/scenarios/rune-ui.json:3`,
  `/home/ulezot/.t3/worktrees/harbagsa/t3-063166c8/scenarios/rune-menu.json:3`, and
  `/home/ulezot/.t3/worktrees/harbagsa/t3-063166c8/scenarios/rune-palette.json:3`
- **E42.** A fresh harness run on 2026-11-12 reproduced the same HUD, menu, and
  palette captures: the menu still shows the HUD underneath, the title and first
  row are still detached, and the palette still fills the screen. Run directories:
  `/tmp/opencode/fresh-ui`, `/tmp/opencode/fresh-menu`, `/tmp/opencode/fresh-palette`
  (not committed).
- **E43.** Strata's shell uses a 240-point sidebar and ships explicit empty and
  error panels with a title, a one-line description, and one action; the empty
  panel is not a blank region.
  `/home/ulezot/.local/share/reui/templates/strata-observability/components/app-shell/app-shell.tsx:65`
  and
  `/home/ulezot/.local/share/reui/templates/strata-observability/components/app-shell/page-states.tsx:51-80`

## Conflicts

| Conflict | Source A | Source B | Resolution |
| --- | --- | --- | --- |
| Palette grid + preview vs "the palette is a list, not a grid" | Requested direction; `docs/ui/README.md:71-77` and `docs/ui/components.md:47-57` say a list with text preview only | The palette data already carries colour, size, key, and light line (`src/ui/ui.odin:52-63`) | Update the docs and the Rune view together. The grid is a better use of the existing data; the "text preview" rule can stay for the preview body while the card gets a colour chip and dimensions |
| Switches, segmented controls, slider thumb vs "the action buttons are the only rounded edges" | Requested control set | `docs/ui/spacing.md:67-68` | Narrow the ban: panels and rows are square; controls may use a 4-point radius, and the switch is a pill. If the ban stays literal, replace the switch with a two-item segmented control |
| Slider drag vs "no drag path" | Requested slider | `docs/ui/states.md:43-45` | Add a drag path and a set-value action. A slider without a thumb or drag is a progress bar, not a slider |
| Hover vs "no hover" | Requested pointer usability | `docs/ui/states.md:91` | Add hover as a visual-only state. Keep every action on the keyboard path; hover must never be the only affordance |
| Hold repeat vs "no key repeat" | Requested keyboard usability | `docs/ui/states.md:91` | Allow repeat for sliders and steppers only: 350ms delay, 50ms interval. Never for Enter, Esc, Tab, or destructive actions |
| Grouped settings cards vs "no rounded panel, no shadow" and the closed surface list | Requested grouped cards | `docs/ui/spacing.md:67-68`; `docs/ui/components.md:3-5` | Use square group boxes with a 32-point header and hairline rows. This is grouping without card chrome; the surface list gains a "settings group" variant, not a new renderer |
| Right-side inspector vs "the debug inspector is the same top-left status panel" | Requested right-side panel | `docs/ui/README.md:79-86` | Keep one inspector, move it to the right at 340 wide. The placement rows still replace it. The top-left inspector becomes the player HUD, or is hidden while the inspector is open |
| 1280x720 density vs the 800x600 minimum and the no-clipping rule | Requested 1280x720 layout | `docs/ui/spacing.md:74`; `docs/design/review.md:55` | Design at 720p, then verify at 800x600. The settings dialog and inspector fit; the 4x3 palette does not, so it falls back to 3x4 below ~1000 points |
| Requested web-app component system vs "the view is a technical readout" | Requested direction | `docs/ui/README.md:8-11`; `docs/design/README.md:12-14` | Keep the Rune view as the only renderer and extend it. Do not add a web renderer, a second text stack, or an Odin layout pass |
| Capture vs code: the HUD and menu are both visible | `runs/menu-current/frames/menu.png` | `ui/shim/src/lib.rs:492-495` returns the menu before the status panel; `docs/ui/README.md:30-32` says the status panel is not drawn while the menu is open | Treat the capture as the bug. Either the UI layer is not cleared between states or the menu view is compositing over the previous surface. Fix the surface/clear path before judging density |
| Capture vs code: the menu title and first row are at the bottom-right | `runs/menu-current/frames/menu.png` | `ui/shim/src/lib.rs:937-941,1010-1016` builds a centered 430-wide panel | Same as above: the intended layout is not the captured layout. A clean capture is required after the fix |
| Authored colour table vs captured pixels | `docs/ui/colour.md:12-21` says `#0F141A` at 94% and `#E6B03B` | `runs/ui-current/frames/ui.png` reads ~`#434E56` for the HUD fill and ~`#F0D683` for the accent; both match the sRGB encoding of the authored linear values | Re-measure after the surface fix. Treat the colour path as a linear/sRGB bug, not a palette choice; the contrast table does not describe the captured image |
| ReUI's 40-point rows and 16-point body vs 720p scene visibility | ReUI templates | The overlay must leave the scene visible; a 12-row inspector at 40 points is 480+ points tall | Use ReUI's scale, not its page density. 24/32/40 row rungs, 12/13 body, 18 dialog title |
| The current menu's `Close` accent button vs its inert behavior | `ui/shim/src/lib.rs:543-556` draws the accent button and returns `Close_Menu` | `docs/ui/README.md:22-23` says the status view's Close is ignored because the menu is already closed | Make the status-view primary `Settings` (opens the menu) or remove it. Do not ship an accent primary that does nothing |

## Not found

- A local "Rune settings-example" template or file. There is no file by that name
  in the repo or in `/home/ulezot/.local/share/reui/templates`. The comparison in
  section 6 treats it as the card-stack pattern implied by the name, not as a
  cited artifact.
- A slider component in the Atlas or Strata ReUI trees. Neither has a
  `components/ui/slider.tsx`. The slider spec is derived from the game's 4-point
  track and standard web control sizing, not from a ReUI component.
- A table component in Atlas. Atlas has no `table.tsx`; the row-height evidence
  comes from Strata's data grid.
- Exact rendered font sizes in the captures. The values are Rune defaults and
  visual readings, not font-metric measurements.
- Whether the pinned Rune rev exposes `on_hover`, a focusable flag, or a focus
  ring helper. The parity matrix claims input routing, focus, and a hit list
  inside Rune, but the shim does not use them. Check the pinned rev before
  planning the interaction work.
- Whether Rune can draw a transformed or axonometric prefab thumbnail. The shim
  draws rectangles and text today. Do not promise a 3D preview; the proposed
  preview is a colour chip plus text and dimension bars.
- Whether the linear/sRGB mismatch is in the shim's colour conversion, the target
  format, or the capture path. The captured values match the sRGB encoding of the
  authored linear values, but the exact stage is not verified.
- A measured performance cost for the extra UI (more text nodes, a 780-wide
  palette, hover state). No frame-time comparison was run.
- A screen-reader or accessibility-tree bridge for the Rune view. No such bridge
  was found in the shim; the checklist assumes keyboard and visual access only.
- The owner's preference between square and rounded panels. No owner quotes are
  used, and the recommendation follows the existing design docs.

## References

### ReUI templates

- `/home/ulezot/.local/share/reui/templates/INDEX.md`
- `/home/ulezot/.local/share/reui/templates/atlas-admin/components/shell/app-shell.tsx`
- `/home/ulezot/.local/share/reui/templates/atlas-admin/components/ui/button.tsx`
- `/home/ulezot/.local/share/reui/templates/atlas-admin/components/ui/card.tsx`
- `/home/ulezot/.local/share/reui/templates/atlas-admin/components/ui/dialog.tsx`
- `/home/ulezot/.local/share/reui/templates/atlas-admin/components/ui/input.tsx`
- `/home/ulezot/.local/share/reui/templates/atlas-admin/components/ui/select.tsx`
- `/home/ulezot/.local/share/reui/templates/atlas-admin/components/ui/switch.tsx`
- `/home/ulezot/.local/share/reui/templates/atlas-admin/features/account/components/preferences-settings.tsx`
- `/home/ulezot/.local/share/reui/templates/atlas-admin/features/account/components/setting-row.tsx`
- `/home/ulezot/.local/share/reui/templates/atlas-admin/features/dashboard/components/metric-tile.tsx`
- `/home/ulezot/.local/share/reui/templates/strata-observability/components/reui/frame.tsx`
- `/home/ulezot/.local/share/reui/templates/strata-observability/components/app-shell/app-shell.tsx`
- `/home/ulezot/.local/share/reui/templates/strata-observability/components/app-shell/page-states.tsx`
- `/home/ulezot/.local/share/reui/templates/strata-observability/components/reui/data-grid/data-grid-table.tsx`
- `/home/ulezot/.local/share/reui/templates/strata-observability/components/ui/toggle.tsx`
- `/home/ulezot/.local/share/reui/templates/strata-observability/components/ui/toggle-group.tsx`
- `/home/ulezot/.local/share/reui/templates/strata-observability/features/settings/components/account-settings.tsx`
- `/home/ulezot/.local/share/reui/templates/strata-observability/features/settings/components/profile/settings-card.tsx`
- `/home/ulezot/.local/share/reui/templates/strata-observability/features/settings/components/profile/setting-row.tsx`
- `/home/ulezot/.local/share/reui/templates/pulse-helpdesk/src/features/tickets/components/ticket-detail-sheet.tsx`
- `/home/ulezot/.local/share/reui/templates/tempo-tasks/src/features/tasks/components/task-sheet.tsx`
- `/home/ulezot/.local/share/reui/templates/tempo-tasks/src/features/kanban/components/kanban-board.tsx`

### Repository docs

- `/home/ulezot/.t3/worktrees/harbagsa/t3-063166c8/docs/ui/README.md`
- `/home/ulezot/.t3/worktrees/harbagsa/t3-063166c8/docs/ui/spacing.md`
- `/home/ulezot/.t3/worktrees/harbagsa/t3-063166c8/docs/ui/components.md`
- `/home/ulezot/.t3/worktrees/harbagsa/t3-063166c8/docs/ui/states.md`
- `/home/ulezot/.t3/worktrees/harbagsa/t3-063166c8/docs/ui/colour.md`
- `/home/ulezot/.t3/worktrees/harbagsa/t3-063166c8/docs/ui/type.md`
- `/home/ulezot/.t3/worktrees/harbagsa/t3-063166c8/docs/design/README.md`
- `/home/ulezot/.t3/worktrees/harbagsa/t3-063166c8/docs/design/review.md`
- `/home/ulezot/.t3/worktrees/harbagsa/t3-063166c8/docs/research/rune-integration-plan.md`
- `/home/ulezot/.t3/worktrees/harbagsa/t3-063166c8/GLOSSARY.md`

### Code and captures

- `/home/ulezot/.t3/worktrees/harbagsa/t3-063166c8/ui/shim/src/lib.rs`
- `/home/ulezot/.t3/worktrees/harbagsa/t3-063166c8/src/ui/ui.odin`
- `/home/ulezot/.t3/worktrees/harbagsa/t3-063166c8/src/game/hud.odin`
- `/home/ulezot/.t3/worktrees/harbagsa/t3-063166c8/src/game/hud_debug.odin`
- `/home/ulezot/.t3/worktrees/harbagsa/t3-063166c8/src/game/menu.odin`
- `/home/ulezot/.t3/worktrees/harbagsa/t3-063166c8/src/game/palette_view.odin`
- `/home/ulezot/.t3/worktrees/harbagsa/t3-063166c8/src/game/prefabs.odin`
- `/home/ulezot/.t3/worktrees/harbagsa/t3-063166c8/src/renderer/ui_bridge.odin`
- `/home/ulezot/.t3/worktrees/harbagsa/t3-063166c8/runs/ui-current/frames/ui.png`
- `/home/ulezot/.t3/worktrees/harbagsa/t3-063166c8/runs/menu-current/frames/menu.png`
- `/home/ulezot/.t3/worktrees/harbagsa/t3-063166c8/runs/palette-current/frames/palette.png`
- `/home/ulezot/.t3/worktrees/harbagsa/t3-063166c8/scenarios/rune-ui.json`
- `/home/ulezot/.t3/worktrees/harbagsa/t3-063166c8/scenarios/rune-menu.json`
- `/home/ulezot/.t3/worktrees/harbagsa/t3-063166c8/scenarios/rune-palette.json`
