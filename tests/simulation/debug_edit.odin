#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package simulation

import "core:testing"

import b3 "libs:box3d"
import game "src:game"

// A level ray from the spawn eye passes over the 1 m crates, so the select
// tests aim slightly down.
CRATE_EDITOR_SELECT_PITCH :: -0.2
CRATE_EDITOR_FLOOR_PITCH :: -0.9

@(private)
crate_editor_setup :: proc(t: ^testing.T) -> (game.Simulation, game.Debug_Mode) {
	sim := create(t)
	dm := game.debug_mode_create()
	dm.active = true
	dm.camera = {
		position = sim.player.position + b3.Vec3{0.0, game.PLAYER_EYE_HEIGHT, 0.0},
		yaw      = 0.0,
		pitch    = CRATE_EDITOR_SELECT_PITCH,
	}
	return sim, dm
}

@(private)
crate_editor_step :: proc(dm: ^game.Debug_Mode, sim: ^game.Simulation, input: game.Debug_Input) {
	game.debug_mode_update(dm, sim, input, game.SIMULATION_STEP)
}

@(private)
crate_editor_select :: proc(dm: ^game.Debug_Mode, sim: ^game.Simulation) {
	crate_editor_step(dm, sim, game.Debug_Input{primary_pressed = true, captured = true})
}

@(test)
debug_edit_selects_crate_under_crosshair :: proc(t: ^testing.T) {
	sim, dm := crate_editor_setup(t)
	defer game.simulation_destroy(&sim)

	crate_editor_select(&dm, &sim)

	testing.expect_value(t, dm.selection, game.Debug_Selection.Crate)
	testing.expect_value(t, dm.selected_crate, 0)
	testing.expect_value(t, dm.dragging, game.Debug_Drag.Crate)
}

@(test)
debug_edit_drag_moves_crate_horizontally :: proc(t: ^testing.T) {
	sim, dm := crate_editor_setup(t)
	defer game.simulation_destroy(&sim)

	crate_editor_select(&dm, &sim)
	before := game.simulation_crate_box(&sim, 0).center

	crate_editor_step(
		&dm,
		&sim,
		game.Debug_Input{look_delta = {10.0, 0.0}, captured = true},
	)

	after := game.simulation_crate_box(&sim, 0).center
	testing.expect_value(t, dm.dragging, game.Debug_Drag.Crate)
	expect_near(t, after.x - before.x, 10.0 * game.CRATE_DRAG_SCALE, 0.0001, "drag x")
	expect_near(t, after.z, before.z, 0.0001, "drag z")
	expect_near(t, after.y, before.y, 0.0001, "drag y")
}

@(test)
debug_edit_wheel_raises_and_clamps_crate :: proc(t: ^testing.T) {
	sim, dm := crate_editor_setup(t)
	defer game.simulation_destroy(&sim)

	crate_editor_select(&dm, &sim)
	crate_editor_step(&dm, &sim, game.Debug_Input{primary_released = true, captured = true})
	testing.expect_value(t, dm.dragging, game.Debug_Drag.None)

	before := game.simulation_crate_box(&sim, 0).center.y
	crate_editor_step(&dm, &sim, game.Debug_Input{wheel_delta = 2.0, captured = true})
	after := game.simulation_crate_box(&sim, 0).center.y
	expect_near(t, after - before, 2.0 * game.CRATE_WHEEL_STEP, 0.0001, "wheel height")

	crate_editor_step(&dm, &sim, game.Debug_Input{wheel_delta = -100.0, captured = true})
	expect_near(
		t,
		game.simulation_crate_box(&sim, 0).center.y,
		game.CRATE_HALF_EXTENTS.y,
		0.0001,
		"wheel floor clamp",
	)
}

@(test)
debug_edit_add_places_crate_on_surface :: proc(t: ^testing.T) {
	sim, dm := crate_editor_setup(t)
	defer game.simulation_destroy(&sim)
	dm.camera.pitch = CRATE_EDITOR_FLOOR_PITCH

	crate_editor_step(&dm, &sim, game.Debug_Input{add_pressed = true, captured = true})

	testing.expect_value(t, game.simulation_crate_count(&sim), game.INITIAL_CRATE_COUNT + 1)
	testing.expect_value(t, dm.selection, game.Debug_Selection.Crate)
	testing.expect_value(t, dm.selected_crate, game.INITIAL_CRATE_COUNT)
	testing.expect_value(t, dm.dragging, game.Debug_Drag.None)

	box := game.simulation_crate_box(&sim, dm.selected_crate)
	expect_near(
		t,
		box.center.y,
		game.CRATE_HALF_EXTENTS.y + game.CRATE_ADD_GAP,
		0.0001,
		"added crate bottom",
	)
}

@(test)
debug_edit_add_is_ignored_when_full :: proc(t: ^testing.T) {
	sim, dm := crate_editor_setup(t)
	defer game.simulation_destroy(&sim)
	dm.camera.pitch = CRATE_EDITOR_FLOOR_PITCH

	for game.simulation_crate_count(&sim) < game.MAX_CRATES {
		_ = game.simulation_add_default_crate(&sim, {0.0, 50.0, 0.0})
	}

	crate_editor_step(&dm, &sim, game.Debug_Input{add_pressed = true, captured = true})

	testing.expect_value(t, game.simulation_crate_count(&sim), game.MAX_CRATES)
	testing.expect_value(t, dm.selection, game.Debug_Selection.None)
	testing.expect_value(t, dm.selected_crate, -1)
}

@(test)
debug_edit_delete_removes_selected_crate :: proc(t: ^testing.T) {
	sim, dm := crate_editor_setup(t)
	defer game.simulation_destroy(&sim)

	crate_editor_select(&dm, &sim)
	crate_editor_step(&dm, &sim, game.Debug_Input{delete_pressed = true, captured = true})

	testing.expect_value(t, game.simulation_crate_count(&sim), game.INITIAL_CRATE_COUNT - 1)
	testing.expect_value(t, dm.selection, game.Debug_Selection.None)
	testing.expect_value(t, dm.selected_crate, -1)
	testing.expect_value(t, dm.dragging, game.Debug_Drag.None)
}

@(test)
debug_edit_empty_click_clears_selection :: proc(t: ^testing.T) {
	sim, dm := crate_editor_setup(t)
	defer game.simulation_destroy(&sim)

	crate_editor_select(&dm, &sim)
	crate_editor_step(&dm, &sim, game.Debug_Input{primary_released = true, captured = true})
	dm.camera.pitch = 0.6

	crate_editor_step(&dm, &sim, game.Debug_Input{primary_pressed = true, captured = true})

	testing.expect_value(t, dm.selection, game.Debug_Selection.None)
	testing.expect_value(t, dm.selected_crate, -1)
	testing.expect_value(t, dm.dragging, game.Debug_Drag.None)
	testing.expect_value(t, game.simulation_crate_count(&sim), game.INITIAL_CRATE_COUNT)
}

@(test)
debug_edit_clears_stale_selection :: proc(t: ^testing.T) {
	sim, dm := crate_editor_setup(t)
	defer game.simulation_destroy(&sim)

	dm.selection = .Crate
	dm.selected_crate = game.INITIAL_CRATE_COUNT - 1
	dm.dragging = .Crate
	testing.expect(t, game.simulation_remove_crate(&sim, dm.selected_crate), "remove failed")

	crate_editor_step(&dm, &sim, game.Debug_Input{captured = true})

	testing.expect_value(t, dm.selection, game.Debug_Selection.None)
	testing.expect_value(t, dm.selected_crate, -1)
	testing.expect_value(t, dm.dragging, game.Debug_Drag.None)
}

@(test)
debug_edit_draws_selected_crate_outline :: proc(t: ^testing.T) {
	sim, dm := crate_editor_setup(t)
	defer game.simulation_destroy(&sim)

	lines: game.Debug_Lines
	game.collect_crate_editor_lines(&dm, &sim, &lines)
	testing.expect_value(t, lines.count, 0)

	crate_editor_select(&dm, &sim)
	game.collect_crate_editor_lines(&dm, &sim, &lines)
	testing.expect_value(t, lines.count, 12)
}
