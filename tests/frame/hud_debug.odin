#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package frame_test

import "core:strings"
import "core:testing"

import "src:game"
import "src:renderer"
import "src:ui"

@(private)
inspector_width :: proc(
	t: ^testing.T,
	sim: ^game.Simulation,
	debug: ^game.Debug_Mode,
	hud: ^game.HUD_State,
	atlas: ^renderer.Text_Atlas,
	theme: renderer.UI_Theme,
) -> (width: f32, values: [game.HUD_INSPECTOR_ROW_COUNT]string) {
	snapshot := game.simulation_snapshot(sim)
	game.hud_state_update(hud, sim, debug, snapshot, true, 0)
	testing.expect_value(t, len(hud.view.rows), game.HUD_INSPECTOR_ROW_COUNT)
	ctx: renderer.Layout_Context
	renderer.layout_context_init(&ctx, theme, atlas, 0, 0)
	layout := ui.rows_layout(ctx.inputs, hud.view.rows, {value_align = .Left})
	values = {}
	for row, index in hud.view.rows {
		values[index] = row.value
	}
	return layout.width, values
}

@(test)
debug_inspector_width_survives_every_selection :: proc(t: ^testing.T) {
	sim, debug, hud, _ := create_state(t)
	defer game.simulation_destroy(&sim)
	defer game.debug_mode_destroy(&debug)
	debug.active = true
	debug.camera = {position = {1234.5, 12.5, -678.5}, yaw = 0.0, pitch = 0.0}

	ids: [game.PREFAB_COUNT]game.Object_Id
	for prefab in game.Prefab_Id {
		ids[int(prefab)] = game.simulation_create_object(
			&sim,
			{
				prefab = prefab,
				body_mode = game.prefab(prefab).body_mode,
				center = {f32(int(prefab)) * 3.0, 2.0, -20.0},
				yaw_rad = f32(int(prefab)) * 0.3,
			},
		)
	}

	theme := renderer.ui_theme_init(720)
	atlas, built := build_atlas(t, theme)
	testing.expect(t, built, "the atlas did not build")
	defer renderer.text_atlas_destroy(&atlas)

	expected, _ := inspector_width(t, &sim, &debug, &hud, &atlas, theme)
	for id in ids {
		apply_expect(t, &debug, &sim, game.Select_Object{id = id}, "select failed")
		actual, _ := inspector_width(t, &sim, &debug, &hud, &atlas, theme)
		testing.expectf(t, actual == expected, "the inspector width moved from %v to %v", expected, actual)
	}

	apply_expect(t, &debug, &sim, game.Select_Object{id = 0}, "clear failed")
	actual, values := inspector_width(t, &sim, &debug, &hud, &atlas, theme)
	testing.expectf(t, actual == expected, "the empty inspector width moved to %v", actual)
	testing.expect_value(t, values[1], "None         # 000")

	apply_expect(t, &debug, &sim, game.Placement_Set_Snap{snap = true}, "snap failed")
	actual, _ = inspector_width(t, &sim, &debug, &hud, &atlas, theme)
	testing.expectf(t, actual == expected, "the snap row changed the width to %v", actual)
}

@(test)
debug_inspector_shows_the_lamp_light_and_budget :: proc(t: ^testing.T) {
	sim, debug, hud, _ := create_state(t)
	defer game.simulation_destroy(&sim)
	defer game.debug_mode_destroy(&debug)
	debug.active = true

	id := game.simulation_create_object(
		&sim,
		{prefab = .Lamp, body_mode = .Static, center = {2, 1, 6}, yaw_rad = 0},
	)
	apply_expect(t, &debug, &sim, game.Select_Object{id = id}, "select failed")
	snapshot := game.simulation_snapshot(&sim)
	game.hud_state_update(&hud, &sim, &debug, snapshot, true, 0)
	rows := hud.view.rows
	testing.expect(
		t,
		strings.contains(rows[game.HUD_INSPECTOR_ROW_COUNT - 2].value, "warm"),
		"the light row is missing",
	)
	testing.expect(
		t,
		strings.contains(rows[game.HUD_INSPECTOR_ROW_COUNT - 2].value, "1.5"),
		"the intensity is missing",
	)
	testing.expect(
		t,
		strings.contains(rows[game.HUD_INSPECTOR_ROW_COUNT - 1].value, "1 active"),
		"the active light count is missing",
	)
	testing.expect(
		t,
		strings.contains(rows[game.HUD_INSPECTOR_ROW_COUNT - 1].value, "1 lamps"),
		"the lamp count is missing",
	)

	apply_expect(t, &debug, &sim, game.Placement_Arm{prefab = .Beacon}, "arm failed")
	game.hud_state_update(&hud, &sim, &debug, snapshot, true, 0)
	testing.expect(
		t,
		strings.contains(hud.view.rows[game.HUD_PLACEMENT_ROW_COUNT - 1].value, "red"),
		"the placement light row is missing",
	)
}
