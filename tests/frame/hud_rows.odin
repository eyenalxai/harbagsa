#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package frame_test

import "core:testing"

import "src:display"
import "src:game"
import "src:renderer"

@(test)
status_panel_width_does_not_change_with_the_position :: proc(t: ^testing.T) {
	sim, debug, hud, _ := create_state(t)
	defer game.simulation_destroy(&sim)

	atlas, built := renderer.text_atlas_build(context.allocator)
	testing.expect(t, built, "the atlas did not build")
	defer renderer.text_atlas_destroy(&atlas, context.allocator)

	theme := renderer.ui_theme_init(720)
	spawn := measure_status_panel(t, &sim, &debug, &hud, &atlas, theme, {0, 0, 14})
	moved := measure_status_panel(t, &sim, &debug, &hud, &atlas, theme, {-19.9, 0.1, -19.9})

	testing.expectf(
		t,
		spawn.width == moved.width,
		"the panel width moved from %v to %v as the player walked",
		spawn.width,
		moved.width,
	)
}

@(test)
menu_rows_fit_the_measured_columns :: proc(t: ^testing.T) {
	sim, _, hud, _ := create_state(t)
	defer game.simulation_destroy(&sim)
	hud.menu.displays = display.fallback_list()
	game.menu_open(&hud.menu)
	game.menu_view(&hud.menu, sim.settings, false)

	atlas, built := renderer.text_atlas_build(context.allocator)
	testing.expect(t, built, "the atlas did not build")
	defer renderer.text_atlas_destroy(&atlas, context.allocator)

	theme := renderer.ui_theme_init(720)
	layout := renderer.rows_measure(&atlas, theme, hud.menu.view.rows, {})
	testing.expect(t, layout.label_column > 0, "the label column must have a width")

	for row in hud.menu.view.rows {
		if row.label != "" {
			label := renderer.text_measure(
				&atlas,
				renderer.row_label_style(theme, row.kind).type,
				row.label,
			)
			testing.expectf(
				t,
				label <= layout.label_column,
				"label %q overflows its column",
				row.label,
			)
		}
		if row.value != "" {
			value := renderer.text_measure(
				&atlas,
				renderer.row_value_style(theme, row).type,
				row.value,
			)
			testing.expectf(
				t,
				value <= layout.value_width,
				"value %q overflows its column",
				row.value,
			)
		}
	}
}

@(test)
every_menu_item_selects_a_selectable_row :: proc(t: ^testing.T) {
	sim, _, hud, _ := create_state(t)
	defer game.simulation_destroy(&sim)
	hud.menu.displays = display.fallback_list()
	game.menu_open(&hud.menu)

	for item in game.Menu_Item {
		hud.menu.selected = item
		game.menu_view(&hud.menu, sim.settings, false)
		row := hud.menu.view.rows[hud.menu.view.selected]
		selectable := row.kind == .Setting || row.kind == .Action
		testing.expectf(t, selectable, "%v selected a %v row", item, row.kind)
		testing.expect_value(t, row.label, game.MENU_ITEM_NAMES[item])
	}
}

@(private)
measure_status_panel :: proc(
	t: ^testing.T,
	sim: ^game.Simulation,
	debug: ^game.Debug_Mode,
	hud: ^game.HUD_State,
	atlas: ^renderer.Text_Atlas,
	theme: renderer.UI_Theme,
	position: [3]f32,
) -> renderer.Rows_Layout {
	snapshot := game.simulation_snapshot(sim)
	snapshot.position = position
	snapshot.velocity = {}
	snapshot.stance = .Standing
	snapshot.gait = .Walk
	snapshot.movement_state = .None
	snapshot.grounded = true

	game.hud_state_update(hud, sim, debug, snapshot, true)
	testing.expect(t, len(hud.view.rows) == game.HUD_ROW_COUNT, "the status rows went missing")
	return renderer.rows_measure(atlas, theme, hud.view.rows, {value_align = .Left})
}
