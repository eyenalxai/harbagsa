#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package simulation

import "core:testing"

import b3 "libs:box3d"
import game "src:game"

// A level ray from the spawn eye passes over the 1 m crates, so the select
// tests aim slightly down.
OBJECT_EDITOR_SELECT_PITCH :: -0.2
OBJECT_EDITOR_FLOOR_PITCH :: -0.9

@(private)
object_editor_setup :: proc(t: ^testing.T) -> (game.Simulation, game.Debug_Mode) {
	sim := create(t)
	dm := game.debug_mode_create()
	dm.active = true
	dm.camera = {
		position = sim.player.position + b3.Vec3{0.0, game.PLAYER_STANDING_EYE, 0.0},
		yaw      = 0.0,
		pitch    = OBJECT_EDITOR_SELECT_PITCH,
	}
	return sim, dm
}

@(private)
object_editor_step :: proc(dm: ^game.Debug_Mode, sim: ^game.Simulation, input: game.Debug_Input) {
	game.debug_mode_update(dm, sim, input, game.SIMULATION_STEP)
}

@(private)
object_editor_select :: proc(dm: ^game.Debug_Mode, sim: ^game.Simulation) {
	object_editor_step(dm, sim, game.Debug_Input{primary_pressed = true, captured = true})
}

@(private)
first_object_id :: proc(sim: ^game.Simulation) -> game.Object_Id {
	return game.simulation_objects(sim)[0].id
}

@(test)
debug_edit_selects_object_under_crosshair :: proc(t: ^testing.T) {
	sim, dm := object_editor_setup(t)
	defer game.simulation_destroy(&sim)

	object_editor_select(&dm, &sim)

	testing.expect_value(t, dm.selection, game.Debug_Selection.Object)
	testing.expect_value(t, dm.selected_object_id, first_object_id(&sim))
	testing.expect_value(t, dm.dragging, game.Debug_Drag.Object)
}

@(test)
debug_edit_drag_moves_object_horizontally :: proc(t: ^testing.T) {
	sim, dm := object_editor_setup(t)
	defer game.simulation_destroy(&sim)

	object_editor_select(&dm, &sim)
	id := first_object_id(&sim)
	before := game.simulation_object_box(&sim, id).center

	object_editor_step(
		&dm,
		&sim,
		game.Debug_Input{look_delta = {10.0, 0.0}, captured = true},
	)

	after := game.simulation_object_box(&sim, id).center
	testing.expect_value(t, dm.dragging, game.Debug_Drag.Object)
	expect_near(t, after.x - before.x, 10.0 * game.OBJECT_DRAG_SCALE, 0.0001, "drag x")
	expect_near(t, after.z, before.z, 0.0001, "drag z")
	expect_near(t, after.y, before.y, 0.0001, "drag y")
}

@(test)
debug_edit_wheel_raises_and_clamps_object :: proc(t: ^testing.T) {
	sim, dm := object_editor_setup(t)
	defer game.simulation_destroy(&sim)

	object_editor_select(&dm, &sim)
	object_editor_step(&dm, &sim, game.Debug_Input{primary_released = true, captured = true})
	testing.expect_value(t, dm.dragging, game.Debug_Drag.None)

	id := first_object_id(&sim)
	before := game.simulation_object_box(&sim, id).center.y
	object_editor_step(&dm, &sim, game.Debug_Input{wheel_delta = 2.0, captured = true})
	after := game.simulation_object_box(&sim, id).center.y
	expect_near(t, after - before, 2.0 * game.OBJECT_WHEEL_STEP, 0.0001, "wheel height")

	object_editor_step(&dm, &sim, game.Debug_Input{wheel_delta = -100.0, captured = true})
	expect_near(
		t,
		game.simulation_object_box(&sim, id).center.y,
		game.prefab(.Crate).half_extents.y,
		0.0001,
		"wheel floor clamp",
	)
}

@(test)
debug_edit_add_places_crate_on_surface :: proc(t: ^testing.T) {
	sim, dm := object_editor_setup(t)
	defer game.simulation_destroy(&sim)
	dm.camera.pitch = OBJECT_EDITOR_FLOOR_PITCH

	object_editor_step(&dm, &sim, game.Debug_Input{add_pressed = true, captured = true})

	testing.expect_value(
		t,
		game.simulation_object_count(&sim),
		game.INITIAL_CRATE_COUNT + 1,
	)
	testing.expect_value(t, dm.selection, game.Debug_Selection.Object)
	testing.expect_value(t, dm.selected_object_id, game.Object_Id(game.INITIAL_CRATE_COUNT + 1))
	testing.expect_value(t, dm.dragging, game.Debug_Drag.None)

	box := game.simulation_object_box(&sim, dm.selected_object_id)
	expect_near(
		t,
		box.center.y,
		game.prefab(.Crate).half_extents.y + game.OBJECT_ADD_GAP,
		0.0001,
		"added crate bottom",
	)
}

@(test)
debug_edit_add_is_ignored_when_full :: proc(t: ^testing.T) {
	sim, dm := object_editor_setup(t)
	defer game.simulation_destroy(&sim)
	dm.camera.pitch = OBJECT_EDITOR_FLOOR_PITCH

	for game.simulation_object_count(&sim) < game.MAX_PLACED_OBJECTS {
		_ = game.simulation_create_object(
			&sim,
			{prefab = .Block, body_mode = .Static, center = {0.0, -5.0, 0.0}, yaw = 0.0},
		)
	}

	object_editor_step(&dm, &sim, game.Debug_Input{add_pressed = true, captured = true})

	testing.expect_value(t, game.simulation_object_count(&sim), game.MAX_PLACED_OBJECTS)
	testing.expect_value(t, dm.selection, game.Debug_Selection.None)
	testing.expect_value(t, dm.selected_object_id, game.INVALID_OBJECT_ID)
}

@(test)
debug_edit_delete_removes_selected_object :: proc(t: ^testing.T) {
	sim, dm := object_editor_setup(t)
	defer game.simulation_destroy(&sim)

	object_editor_select(&dm, &sim)
	object_editor_step(&dm, &sim, game.Debug_Input{delete_pressed = true, captured = true})

	testing.expect_value(
		t,
		game.simulation_object_count(&sim),
		game.INITIAL_CRATE_COUNT - 1,
	)
	testing.expect_value(t, dm.selection, game.Debug_Selection.None)
	testing.expect_value(t, dm.selected_object_id, game.INVALID_OBJECT_ID)
	testing.expect_value(t, dm.dragging, game.Debug_Drag.None)
}

@(test)
debug_edit_empty_click_clears_selection :: proc(t: ^testing.T) {
	sim, dm := object_editor_setup(t)
	defer game.simulation_destroy(&sim)

	object_editor_select(&dm, &sim)
	object_editor_step(&dm, &sim, game.Debug_Input{primary_released = true, captured = true})
	dm.camera.pitch = 0.6

	object_editor_step(&dm, &sim, game.Debug_Input{primary_pressed = true, captured = true})

	testing.expect_value(t, dm.selection, game.Debug_Selection.None)
	testing.expect_value(t, dm.selected_object_id, game.INVALID_OBJECT_ID)
	testing.expect_value(t, dm.dragging, game.Debug_Drag.None)
	testing.expect_value(
		t,
		game.simulation_object_count(&sim),
		game.INITIAL_CRATE_COUNT,
	)
}

@(test)
debug_edit_clears_stale_selection :: proc(t: ^testing.T) {
	sim, dm := object_editor_setup(t)
	defer game.simulation_destroy(&sim)

	objects := game.simulation_objects(&sim)
	id := objects[len(objects) - 1].id
	dm.selection = .Object
	dm.selected_object_id = id
	dm.dragging = .Object
	testing.expect(t, game.simulation_remove_object(&sim, id), "remove failed")

	object_editor_step(&dm, &sim, game.Debug_Input{captured = true})

	testing.expect_value(t, dm.selection, game.Debug_Selection.None)
	testing.expect_value(t, dm.selected_object_id, game.INVALID_OBJECT_ID)
	testing.expect_value(t, dm.dragging, game.Debug_Drag.None)
}

@(test)
debug_edit_draws_selected_object_outline :: proc(t: ^testing.T) {
	sim, dm := object_editor_setup(t)
	defer game.simulation_destroy(&sim)

	lines: game.Debug_Lines
	game.collect_object_editor_lines(&dm, &sim, &lines)
	testing.expect_value(t, lines.count, 0)

	object_editor_select(&dm, &sim)
	game.collect_object_editor_lines(&dm, &sim, &lines)
	testing.expect_value(t, lines.count, 12)
}
