#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package simulation

import "core:testing"

import b3 "libs:box3d"
import game "src:game"

// A level ray from the spawn eye passes over the 1 m crates, so the select
// tests aim slightly down.
OBJECT_EDITOR_SELECT_PITCH :: -0.2

@(private)
object_editor_setup :: proc(t: ^testing.T) -> (game.Simulation, game.Debug_Mode) {
	sim := create(t)
	dm := game.debug_mode_create(context.allocator)
	dm.active = true
	dm.camera = {
		position = sim.player.position + b3.Vec3{0.0, game.PLAYER_STANDING_EYE, 0.0},
		yaw      = 0.0,
		pitch    = OBJECT_EDITOR_SELECT_PITCH,
	}
	return sim, dm
}

@(private)
object_editor_select :: proc(dm: ^game.Debug_Mode, sim: ^game.Simulation) {
	edit_step(dm, sim, {game.Primary_Press{}})
}

@(private)
first_object_id :: proc(sim: ^game.Simulation) -> game.Object_Id {
	return game.simulation_objects(sim)[0].id
}

@(test)
debug_edit_selects_object_under_crosshair :: proc(t: ^testing.T) {
	sim, dm := object_editor_setup(t)
	defer game.debug_mode_destroy(&dm)
	defer game.simulation_destroy(&sim)

	object_editor_select(&dm, &sim)

	testing.expect_value(t, dm.selection, game.Debug_Selection.Object)
	testing.expect_value(t, dm.selected_object_id, first_object_id(&sim))
	testing.expect_value(t, dm.dragging, game.Debug_Drag.Object)
}

@(test)
debug_edit_drag_moves_object_horizontally :: proc(t: ^testing.T) {
	sim, dm := object_editor_setup(t)
	defer game.debug_mode_destroy(&dm)
	defer game.simulation_destroy(&sim)

	object_editor_select(&dm, &sim)
	id := first_object_id(&sim)
	before := game.simulation_object_box(&sim, id).center

	edit_step(&dm, &sim, {game.Drag_Move{look_delta = {10.0, 0.0}}})

	after := game.simulation_object_box(&sim, id).center
	testing.expect_value(t, dm.dragging, game.Debug_Drag.Object)
	expect_near(t, after.x - before.x, 10.0 * game.OBJECT_DRAG_SCALE, 0.0001, "drag x")
	expect_near(t, after.z, before.z, 0.0001, "drag z")
	expect_near(t, after.y, before.y, 0.0001, "drag y")
}

@(test)
debug_edit_wheel_raises_and_clamps_object :: proc(t: ^testing.T) {
	sim, dm := object_editor_setup(t)
	defer game.debug_mode_destroy(&dm)
	defer game.simulation_destroy(&sim)

	object_editor_select(&dm, &sim)
	edit_step(&dm, &sim, {game.Primary_Release{}})
	testing.expect_value(t, dm.dragging, game.Debug_Drag.None)

	id := first_object_id(&sim)
	before := game.simulation_object_box(&sim, id).center.y
	edit_step(&dm, &sim, {game.Wheel{steps = 2}})
	after := game.simulation_object_box(&sim, id).center.y
	expect_near(t, after - before, 2.0 * game.OBJECT_WHEEL_STEP, 0.0001, "wheel height")

	edit_step(&dm, &sim, {game.Wheel{steps = -100}})
	expect_near(
		t,
		game.simulation_object_box(&sim, id).center.y,
		game.prefab(.Crate).half_extents.y,
		0.0001,
		"wheel floor clamp",
	)
}

@(test)
debug_edit_right_click_clears_the_selection :: proc(t: ^testing.T) {
	sim, dm := object_editor_setup(t)
	defer game.debug_mode_destroy(&dm)
	defer game.simulation_destroy(&sim)

	object_editor_select(&dm, &sim)
	edit_step(&dm, &sim, {game.Secondary_Press{}})

	testing.expect_value(t, dm.selection, game.Debug_Selection.None)
	testing.expect_value(t, dm.selected_object_id, game.INVALID_OBJECT_ID)
	testing.expect_value(t, dm.dragging, game.Debug_Drag.None)
}

@(test)
debug_edit_delete_removes_selected_object :: proc(t: ^testing.T) {
	sim, dm := object_editor_setup(t)
	defer game.debug_mode_destroy(&dm)
	defer game.simulation_destroy(&sim)

	object_editor_select(&dm, &sim)
	edit_step(&dm, &sim, {game.Delete_Selected{}})

	testing.expect_value(
		t,
		game.simulation_object_count(&sim),
		game.INITIAL_OBJECT_COUNT - 1,
	)
	testing.expect_value(t, dm.selection, game.Debug_Selection.None)
	testing.expect_value(t, dm.selected_object_id, game.INVALID_OBJECT_ID)
	testing.expect_value(t, dm.dragging, game.Debug_Drag.None)
}

@(test)
debug_edit_empty_click_clears_selection :: proc(t: ^testing.T) {
	sim, dm := object_editor_setup(t)
	defer game.debug_mode_destroy(&dm)
	defer game.simulation_destroy(&sim)

	object_editor_select(&dm, &sim)
	edit_step(&dm, &sim, {game.Primary_Release{}})
	dm.camera.pitch = 0.6

	edit_step(&dm, &sim, {game.Primary_Press{}})

	testing.expect_value(t, dm.selection, game.Debug_Selection.None)
	testing.expect_value(t, dm.selected_object_id, game.INVALID_OBJECT_ID)
	testing.expect_value(t, dm.dragging, game.Debug_Drag.None)
	testing.expect_value(
		t,
		game.simulation_object_count(&sim),
		game.INITIAL_OBJECT_COUNT,
	)
}

@(test)
debug_edit_clears_stale_selection :: proc(t: ^testing.T) {
	sim, dm := object_editor_setup(t)
	defer game.debug_mode_destroy(&dm)
	defer game.simulation_destroy(&sim)

	objects := game.simulation_objects(&sim)
	id := objects[len(objects) - 1].id
	dm.selection = .Object
	dm.selected_object_id = id
	dm.dragging = .Object
	testing.expect(t, game.simulation_remove_object(&sim, id), "remove failed")

	editor_step(&dm, &sim, {captured = true})

	testing.expect_value(t, dm.selection, game.Debug_Selection.None)
	testing.expect_value(t, dm.selected_object_id, game.INVALID_OBJECT_ID)
	testing.expect_value(t, dm.dragging, game.Debug_Drag.None)
}

@(test)
debug_edit_draws_selected_object_outline :: proc(t: ^testing.T) {
	sim, dm := object_editor_setup(t)
	defer game.debug_mode_destroy(&dm)
	defer game.simulation_destroy(&sim)

	lines: game.Debug_Lines
	game.collect_object_editor_lines(&dm, &sim, &lines)
	testing.expect_value(t, lines.count, 0)

	object_editor_select(&dm, &sim)
	game.collect_object_editor_lines(&dm, &sim, &lines)
	testing.expect_value(t, lines.count, 12)
}
