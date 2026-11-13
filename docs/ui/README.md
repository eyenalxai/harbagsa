# The Rune UI layer

The overlay is a Rune view drawn by the Rust shim in `ui/shim`. Rune owns the
layout, type, colour, hit testing, and the wgpu pass that draws onto the game's
swapchain or offscreen image. Odin owns the simulation and the flat data the
view reads. There is no second UI renderer in Odin.

The view is a technical readout: a status panel in the top-left, a bottom action
row with `Debug`, a settings dialog over a scrim, the object palette as a grid
over a scrim, and the debug inspector as a right rail. A notice and the capture
hint sit above the action row. Rune kit motion follows the reduce-motion setting.
The optional rune-fx glow is a demo and is off by default.

## The layer rule

| Layer | Owns | Must not |
| --- | --- | --- |
| `src/game` | which rows exist, their labels and values, menu state, palette state | know about Rune, pixels, or colours |
| `src/ui` | the flat snapshot vocabulary: `Row`, `Menu`, `Palette`, `Hud`, and the constants | import a project package |
| `src/frame` | assembling one `HUD_Frame` from the simulation and input | draw or lay out |
| `src/renderer/ui_bridge.odin` | the C ABI to the shim, snapshot marshalling, action queue | invent content |
| `ui/shim/src/views.rs` | the HUD and menu view | read game state directly |
| `ui/shim/src/palette.rs` | the palette grid, preview, and isometric shape | read game state directly |
| `ui/shim/src/inspector.rs` | the debug inspector rail | read game state directly |
| `ui/shim/src/theme.rs` | the view tokens and kit | read game state directly |
| `ui/shim/src/lib.rs` | the ABI entry points, host, paint, and rune-fx | read game state directly |

The frame protocol calls `ui_frame` before the scene is recorded and `ui_draw`
after the scene is submitted. The shim draws onto the same target image, so a
capture includes the UI. When the frame's `hud` flag is false, `HUD_Frame.enabled`
is false: `ui_step` does not rebuild the view and the frame protocol does not
call `ui_draw`, so a `hud:false` capture has no overlay. The game applies the
action queue after the draw: `Close_Menu`, `Debug_Inspector`, `Palette_Select`,
`Palette_Pick`, `Settings_Set`, `Type_Weight_Set`, `Object_Set`,
`Object_Duplicate`, `Object_Delete`, `Lamp_Set`, `Lamp_Kind`, `Lamp_Color`,
`Toggle_Inspector`, and `Physics_Debug`.

## Snapshot

`src/ui/ui.odin` is data only. `src/game/hud.odin` fills the player rows,
`src/game/hud_debug.odin` fills the keyboard-only debug or placement rows,
`src/game/inspector_view.odin` fills the inspector rail,
`src/game/settings_view.odin` and `src/game/menu.odin` fill the settings dialog,
and `src/game/palette_view.odin` fills the object palette. `src/frame/frame.odin` copies those values into the
`UI_Frame` struct in `src/renderer/ui_frame.odin`. The shim copies every string
during the `ui_frame` call; Odin keeps ownership and may reuse the storage on the
next frame.

The pointer, wheel, key, and focus events travel in one flat batch. Rune
hit-tests the view, routes focus and drag, and returns flat actions through
`ui_actions`.

`Row`, `Menu`, `Settings`, `Palette`, and `Hud` are the wire model: the shim consumes those
flat values, so they stay. The old row vocabulary (the Odin layout and draw
helpers that measured and painted them) is gone; do not bring that layer back.

## Files

- [type.md](type.md): Rune's type, the snapshot strings, and the numeric rule.
- [colour.md](colour.md): the shim's colour literals and the contrast floors.
- [spacing.md](spacing.md): panel geometry, view scale, and the action row.
- [components.md](components.md): the status panel, menu, palette, notice, hint,
  and the opt-in rune-fx demo.
- [states.md](states.md): row kinds, selection, blocked rows, and actions.

## Adding a surface

1. Add the data to `src/ui`: a row kind if one is missing, or a new field on
   `Hud`, `Menu`, or `Palette`.
2. Fill it in `src/game`. Format every changing number into a fixed field.
3. Extend the flat `UI_Frame` payload and the matching C ABI in
   `src/renderer/ui_bridge.odin`. `HUD_Frame` only carries `enabled` plus that
   frame, and the Rune shim must consume the new field.
4. Draw it in `ui/shim/src/views.rs` as a Rune element tree; the palette grid
   and preview live in `ui/shim/src/palette.rs`.
5. Add a scenario under `scenarios/rune-*.json` when the surface is visual.

Do not add a vertex buffer, a shader, a layout module, or a font asset to Odin.
The shim draws every 2D pixel.

## The object palette

The debug object palette is a 640-point dialog over the scrim: a 3×4 grid of
120×92 cards on the left and a 220-point preview on the right. Each card shows
the prefab colour, short name, full name, and key badge. Number keys 1-9 select
the first nine cards; the last two show a dash badge and are reached with the
arrow keys. The selected card lifts to the raised surface with a 2-point accent
bar; hover adds a fill overlay, and focus adds a 2-point ring.

Clicking a card returns `Palette_Select` with the item index and previews it.
`Place` or `Enter` returns `Palette_Pick`; the game arms the placement with the
selected prefab, body, and light. The preview shows the prefab colour,
dimensions, body, light line, and an isometric box drawn from the half extents
and base pitch. All eleven prefabs fit in the grid at 1280×720 and 800×600.

## The debug inspector

The interactive debug inspector is a 320-point-wide right rail, inset 12 from
the top and right, with a maximum height that leaves the bottom action row
clear; it scrolls only when the sections overflow. `I` opens it and frees the pointer;
`Esc` closes it and restores capture. It is hidden while Settings or the palette
is open, and it is mutually exclusive with the palette and placement: opening it
cancels the active tool or drag. The rail has Object, Placement, Lamp, and Debug
sections. Object edits use the editor action vocabulary, including an absolute
yaw setter. Lamp edits use the fixed light colour set. The Debug section carries
the type weight and the physics debug switch.

The old top-left debug rows remain the keyboard-only readout while the rail is
closed. Every changing number keeps a fixed field, so the panel text does not
change width.

## Rules that are easy to break

- The Odin side sends data, never draw commands.
- A UI colour lives in `ui/shim/src/theme.rs`; a panel size lives with its view
  in `ui/shim/src/views.rs`, `ui/shim/src/palette.rs`, or
  `ui/shim/src/inspector.rs`, not in `src/ui` or `src/frame`.
- A row is a `ui.Row`; a new kind must be understood by both the game and the
  shim.
- Kit motion follows `Settings.reduce_motion`; the rune-fx demo is opt-in and
  starts off.
- No image, font, or shader asset moves from Rune into the Odin tree.
