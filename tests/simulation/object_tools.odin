#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package simulation

import "core:testing"

import b3 "libs:box3d"
import game "src:game"

@(private)
tool_dm :: proc(t: ^testing.T, sim: ^game.Simulation) -> game.Debug_Mode {
	dm := game.debug_mode_create(context.allocator)
	dm.active = true
	dm.camera = {
		position = sim.player.position + b3.Vec3{0.0, game.PLAYER_STANDING_EYE, 0.0},
		yaw      = 0.0,
		pitch    = OBJECT_EDITOR_SELECT_PITCH,
	}
	return dm
}

@(private)
place_block :: proc(sim: ^game.Simulation, dm: ^game.Debug_Mode, center: b3.Vec3) -> game.Object_Id {
	return game.debug_place_object(
		dm,
		sim,
		{prefab = .Block, body_mode = .Static, center = center, yaw = 0},
	)
}

@(test)
select_object_by_id_and_clear :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)
	dm := tool_dm(t, &sim)
	defer game.debug_mode_destroy(&dm)

	id := game.simulation_objects(&sim)[1].id
	testing.expect(t, game.debug_select_object(&dm, &sim, id), "select failed")
	testing.expect_value(t, dm.selection, game.Debug_Selection.Object)
	testing.expect_value(t, dm.selected_object_id, id)
	testing.expect(t, game.debug_select_object(&dm, &sim, 0), "clear failed")
	testing.expect_value(t, dm.selection, game.Debug_Selection.None)
	testing.expect(t, !game.debug_select_object(&dm, &sim, 99), "unknown id selected")
}

@(test)
drag_pushes_one_history_entry_per_drag :: proc(t: ^testing.T) {
	sim, dm := object_editor_setup(t)
	defer game.debug_mode_destroy(&dm)
	defer game.simulation_destroy(&sim)

	object_editor_select(&dm, &sim)
	testing.expect_value(t, game.debug_history_depth(&dm), 0)
	id := first_object_id(&sim)
	before := game.simulation_object_box(&sim, id).center

	object_editor_step(&dm, &sim, game.Debug_Input{look_delta = {10.0, 0.0}, captured = true})
	object_editor_step(&dm, &sim, game.Debug_Input{look_delta = {10.0, 0.0}, captured = true})

	testing.expect_value(t, game.debug_history_depth(&dm), 1)
	after := game.simulation_object_box(&sim, id).center
	expect_near(t, after.x - before.x, 20.0 * game.OBJECT_DRAG_SCALE, 0.0001, "drag x")

	_ = game.debug_undo(&dm, &sim)
	testing.expect_value(t, game.simulation_object_box(&sim, id).center, before)
}

@(test)
rotate_and_wheel_edit_the_selection_and_undo :: proc(t: ^testing.T) {
	sim, dm := object_editor_setup(t)
	defer game.debug_mode_destroy(&dm)
	defer game.simulation_destroy(&sim)

	object_editor_select(&dm, &sim)
	object_editor_step(&dm, &sim, game.Debug_Input{primary_released = true, captured = true})
	id := first_object_id(&sim)
	start_y := game.simulation_object_box(&sim, id).center.y
	testing.expect_value(t, game.debug_history_depth(&dm), 0)

	object_editor_step(&dm, &sim, game.Debug_Input{rotate_right = true, captured = true})
	expect_near(t, game.simulation_object_yaw(&sim, id) * 180.0 / 3.14159265, 15.0, 0.25, "yaw 15")
	object_editor_step(
		&dm,
		&sim,
		game.Debug_Input{rotate_left = true, large_step = true, captured = true},
	)
	expect_near(t, game.simulation_object_yaw(&sim, id) * 180.0 / 3.14159265, -30.0, 0.25, "yaw -30")
	object_editor_step(&dm, &sim, game.Debug_Input{wheel_delta = 1.0, captured = true})
	expect_near(t, game.simulation_object_box(&sim, id).center.y, start_y + 0.5, 0.0001, "wheel")
	testing.expect_value(t, game.debug_history_depth(&dm), 3)

	_ = game.debug_undo(&dm, &sim)
	expect_near(t, game.simulation_object_box(&sim, id).center.y, start_y, 0.0001, "undo wheel")
	_ = game.debug_undo(&dm, &sim)
	expect_near(t, game.simulation_object_yaw(&sim, id) * 180.0 / 3.14159265, 15.0, 0.25, "undo turn")
	_ = game.debug_undo(&dm, &sim)
	expect_near(t, game.simulation_object_yaw(&sim, id), 0.0, 0.001, "undo all")
	testing.expect_value(t, game.debug_history_depth(&dm), 0)
}

@(test)
duplicate_offsets_selects_pops_and_restores_without_a_pop :: proc(t: ^testing.T) {
	sim, dm := object_editor_setup(t)
	defer game.debug_mode_destroy(&dm)
	defer game.simulation_destroy(&sim)

	source := place_block(&sim, &dm, {4, 0.5, 9})
	step_world(&sim, 30)
	source_center := game.simulation_object_box(&sim, source).center
	testing.expect_value(t, game.debug_history_depth(&dm), 1)

	copy := game.debug_duplicate_selected(&dm, &sim)
	testing.expect(t, copy != game.INVALID_OBJECT_ID, "duplicate failed")
	testing.expect_value(t, game.simulation_object_count(&sim), game.INITIAL_CRATE_COUNT + 2)
	testing.expect_value(t, dm.selected_object_id, copy)
	testing.expect_value(t, game.debug_history_depth(&dm), 2)
	expect_near(
		t,
		game.simulation_object_box(&sim, copy).center.x,
		source_center.x + game.prefab(.Block).half_extents.x,
		0.0001,
		"duplicate offset",
	)
	testing.expect_value(t, game.simulation_object_scale(&sim, copy), game.SPAWN_POP_MIN_SCALE)

	_ = game.debug_undo(&dm, &sim)
	testing.expect_value(t, game.simulation_object_count(&sim), game.INITIAL_CRATE_COUNT + 1)
	testing.expect_value(t, game.simulation_object_box(&sim, source).center, source_center)
	testing.expect_value(t, game.debug_history_depth(&dm), 1)

	step_world(&sim, 30)
	_ = game.debug_redo(&dm, &sim)
	testing.expect_value(t, game.simulation_object_count(&sim), game.INITIAL_CRATE_COUNT + 2)
	testing.expect_value(t, dm.selected_object_id, game.INVALID_OBJECT_ID)
	testing.expect_value(t, game.simulation_object_scale(&sim, copy), 1.0)
	testing.expect_value(t, game.simulation_object_spawn_age(&sim, copy), 0.0)
	testing.expect_value(t, game.debug_history_depth(&dm), 2)
	testing.expect_value(t, game.debug_history_redo_depth(&dm), 0)
}

@(test)
delete_and_undo_restore_the_same_id :: proc(t: ^testing.T) {
	sim, dm := object_editor_setup(t)
	defer game.debug_mode_destroy(&dm)
	defer game.simulation_destroy(&sim)

	id := first_object_id(&sim)
	placement := game.simulation_object_box(&sim, id)
	testing.expect(t, game.debug_select_object(&dm, &sim, id), "select failed")
	testing.expect(t, game.debug_delete_selected(&dm, &sim), "delete failed")
	testing.expect_value(t, game.simulation_object_count(&sim), game.INITIAL_CRATE_COUNT - 1)
	testing.expect_value(t, dm.selection, game.Debug_Selection.None)
	testing.expect_value(t, game.debug_history_depth(&dm), 1)

	testing.expect(t, game.debug_undo(&dm, &sim), "undo failed")
	testing.expect_value(t, game.simulation_object_count(&sim), game.INITIAL_CRATE_COUNT)
	testing.expect_value(t, game.simulation_object_box(&sim, id).center, placement.center)
	testing.expect_value(t, game.simulation_object_scale(&sim, id), 1.0)
	testing.expect_value(t, dm.selection, game.Debug_Selection.None)

	testing.expect(t, game.debug_redo(&dm, &sim), "redo failed")
	testing.expect_value(t, game.simulation_object_count(&sim), game.INITIAL_CRATE_COUNT - 1)
	testing.expect_value(t, game.debug_history_depth(&dm), 1)
}

@(test)
body_conversion_recreates_at_the_transform_and_undoes :: proc(t: ^testing.T) {
	sim, dm := object_editor_setup(t)
	defer game.debug_mode_destroy(&dm)
	defer game.simulation_destroy(&sim)

	id := first_object_id(&sim)
	placement := game.simulation_object_box(&sim, id)
	testing.expect(t, game.debug_select_object(&dm, &sim, id), "select failed")
	old_body := game.simulation_object_body(&sim, id)
	b3.Body_SetLinearVelocity(old_body, {3.0, 4.0, 5.0})

	testing.expect(t, game.debug_flip_selected_body(&dm, &sim), "flip failed")
	body := game.simulation_object_body(&sim, id)
	testing.expect_value(t, b3.Body_GetType(body), b3.BodyType.staticBody)
	testing.expect(t, !b3.Body_IsValid(old_body), "the old body survived")
	testing.expect_value(t, b3.Body_GetLinearVelocity(body), b3.Vec3_zero)
	testing.expect_value(t, game.simulation_object_box(&sim, id).center, placement.center)
	testing.expect_value(t, game.debug_history_depth(&dm), 1)

	testing.expect(t, game.debug_convert_selected(&dm, &sim, .Static), "same-mode convert failed")
	testing.expect_value(t, game.debug_history_depth(&dm), 1)

	testing.expect(t, game.debug_undo(&dm, &sim), "undo failed")
	restored := game.simulation_object_body(&sim, id)
	testing.expect_value(t, b3.Body_GetType(restored), b3.BodyType.dynamicBody)
	testing.expect_value(t, game.simulation_object_box(&sim, id).center, placement.center)
	testing.expect_value(t, game.simulation_object_yaw(&sim, id), 0.0)
	testing.expect_value(t, game.debug_history_depth(&dm), 0)
}

@(test)
ray_selection_and_drag_work_for_a_placed_static_prefab :: proc(t: ^testing.T) {
	sim, dm := object_editor_setup(t)
	defer game.debug_mode_destroy(&dm)
	defer game.simulation_destroy(&sim)

	pillar := game.debug_place_object(
		&dm,
		&sim,
		{prefab = .Pillar, body_mode = .Static, center = {0, 1.5, 10}, yaw = 0},
	)
	testing.expect(t, pillar != game.INVALID_OBJECT_ID, "pillar did not place")
	_ = game.debug_select_object(&dm, &sim, 0)
	object_editor_select(&dm, &sim)
	testing.expect_value(t, dm.selected_object_id, pillar)

	before := game.simulation_object_box(&sim, pillar).center
	object_editor_step(&dm, &sim, game.Debug_Input{look_delta = {10.0, 0.0}, captured = true})
	after := game.simulation_object_box(&sim, pillar).center
	expect_near(t, after.x - before.x, 10.0 * game.OBJECT_DRAG_SCALE, 0.0001, "pillar drag x")
	expect_near(t, after.z, before.z, 0.0001, "pillar drag z")
}

@(test)
keyboard_duplicate_undo_redo_and_body_follow_the_palette_rule :: proc(t: ^testing.T) {
	sim, dm := object_editor_setup(t)
	defer game.debug_mode_destroy(&dm)
	defer game.simulation_destroy(&sim)

	object_editor_select(&dm, &sim)
	object_editor_step(&dm, &sim, game.Debug_Input{primary_released = true, captured = true})
	id := first_object_id(&sim)
	before := game.simulation_object_box(&sim, id)

	object_editor_step(&dm, &sim, game.Debug_Input{duplicate_pressed = true, captured = true})
	testing.expect_value(t, game.simulation_object_count(&sim), game.INITIAL_CRATE_COUNT + 1)
	testing.expect_value(t, game.debug_history_depth(&dm), 1)
	testing.expect(t, dm.selected_object_id != id, "duplicate did not select the copy")

	object_editor_step(&dm, &sim, game.Debug_Input{undo_pressed = true, captured = true})
	testing.expect_value(t, game.simulation_object_count(&sim), game.INITIAL_CRATE_COUNT)
	testing.expect_value(t, game.debug_history_depth(&dm), 0)
	testing.expect_value(t, game.debug_history_redo_depth(&dm), 1)

	object_editor_step(&dm, &sim, game.Debug_Input{redo_pressed = true, captured = true})
	testing.expect_value(t, game.simulation_object_count(&sim), game.INITIAL_CRATE_COUNT + 1)
	testing.expect_value(t, game.debug_history_depth(&dm), 1)

	testing.expect(t, game.debug_select_object(&dm, &sim, id), "select failed")
	game.debug_palette_open(&dm)
	game.debug_body_key(&dm, &sim)
	testing.expect_value(t, dm.palette.body_mode, game.Body_Mode.Static)
	selected, _ := game.simulation_object_find(&sim, id)
	testing.expect_value(t, selected.body_mode, game.Body_Mode.Dynamic)

	game.debug_palette_close(&dm)
	game.debug_body_key(&dm, &sim)
	object, _ := game.simulation_object_find(&sim, id)
	testing.expect_value(t, object.body_mode, game.Body_Mode.Static)
	testing.expect_value(t, game.simulation_object_box(&sim, id).center, before.center)
}
