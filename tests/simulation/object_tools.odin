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
place_block :: proc(t: ^testing.T, sim: ^game.Simulation, dm: ^game.Debug_Mode, center: b3.Vec3) -> game.Object_Id {
	apply_expect(t, dm, sim, game.Place_Object {
		prefab = .Block,
		body_mode = .Static,
		center = center,
		yaw_rad = 0,
	}, "place failed")
	return dm.selected_object_id
}

@(test)
select_object_by_id_and_clear :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)
	dm := tool_dm(t, &sim)
	defer game.debug_mode_destroy(&dm)

	id := game.simulation_objects(&sim)[1].id
	apply_expect(t, &dm, &sim, game.Select_Object{id = id}, "select failed")
	testing.expect_value(t, dm.selection, game.Debug_Selection.Object)
	testing.expect_value(t, dm.selected_object_id, id)
	apply_expect(t, &dm, &sim, game.Select_Object{id = 0}, "clear failed")
	testing.expect_value(t, dm.selection, game.Debug_Selection.None)
	testing.expect(t, !apply(&dm, &sim, game.Select_Object{id = 99}).applied, "unknown id selected")
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

	edit_step(&dm, &sim, {game.Drag_Move{look_delta = {10.0, 0.0}}})
	edit_step(&dm, &sim, {game.Drag_Move{look_delta = {10.0, 0.0}}})

	testing.expect_value(t, game.debug_history_depth(&dm), 1)
	after := game.simulation_object_box(&sim, id).center
	expect_near(t, after.x - before.x, 20.0 * game.OBJECT_DRAG_SCALE, 0.0001, "drag x")

	apply_expect(t, &dm, &sim, game.Undo{}, "undo failed")
	testing.expect_value(t, game.simulation_object_box(&sim, id).center, before)
}

@(test)
rotate_and_wheel_edit_the_selection_and_undo :: proc(t: ^testing.T) {
	sim, dm := object_editor_setup(t)
	defer game.debug_mode_destroy(&dm)
	defer game.simulation_destroy(&sim)

	object_editor_select(&dm, &sim)
	edit_step(&dm, &sim, {game.Primary_Release{}})
	id := first_object_id(&sim)
	start_y := game.simulation_object_box(&sim, id).center.y
	testing.expect_value(t, game.debug_history_depth(&dm), 0)

	edit_step(&dm, &sim, {game.Turn{steps = 1}})
	expect_near(t, game.simulation_object_yaw(&sim, id) * 180.0 / 3.14159265, 15.0, 0.25, "yaw 15")
	edit_step(&dm, &sim, {game.Turn{steps = -1, large = true}})
	expect_near(t, game.simulation_object_yaw(&sim, id) * 180.0 / 3.14159265, -30.0, 0.25, "yaw -30")
	edit_step(&dm, &sim, {game.Wheel{steps = 1}})
	expect_near(t, game.simulation_object_box(&sim, id).center.y, start_y + 0.5, 0.0001, "wheel")
	testing.expect_value(t, game.debug_history_depth(&dm), 3)

	apply_expect(t, &dm, &sim, game.Undo{}, "undo failed")
	expect_near(t, game.simulation_object_box(&sim, id).center.y, start_y, 0.0001, "undo wheel")
	apply_expect(t, &dm, &sim, game.Undo{}, "undo failed")
	expect_near(t, game.simulation_object_yaw(&sim, id) * 180.0 / 3.14159265, 15.0, 0.25, "undo turn")
	apply_expect(t, &dm, &sim, game.Undo{}, "undo failed")
	expect_near(t, game.simulation_object_yaw(&sim, id), 0.0, 0.001, "undo all")
	testing.expect_value(t, game.debug_history_depth(&dm), 0)
}

@(test)
duplicate_offsets_selects_pops_and_restores_without_a_pop :: proc(t: ^testing.T) {
	sim, dm := object_editor_setup(t)
	defer game.debug_mode_destroy(&dm)
	defer game.simulation_destroy(&sim)

	source := place_block(t, &sim, &dm, {4, 0.5, 9})
	step_world(&sim, 30)
	source_center := game.simulation_object_box(&sim, source).center
	testing.expect_value(t, game.debug_history_depth(&dm), 1)

	apply_expect(t, &dm, &sim, game.Duplicate_Selected{}, "duplicate failed")
	copy := dm.selected_object_id
	testing.expect(t, copy != game.INVALID_OBJECT_ID, "duplicate selected nothing")
	testing.expect_value(t, game.simulation_object_count(&sim), game.INITIAL_OBJECT_COUNT + 2)
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

	apply_expect(t, &dm, &sim, game.Undo{}, "undo failed")
	testing.expect_value(t, game.simulation_object_count(&sim), game.INITIAL_OBJECT_COUNT + 1)
	testing.expect_value(t, game.simulation_object_box(&sim, source).center, source_center)
	testing.expect_value(t, game.debug_history_depth(&dm), 1)

	step_world(&sim, 30)
	apply_expect(t, &dm, &sim, game.Redo{}, "redo failed")
	testing.expect_value(t, game.simulation_object_count(&sim), game.INITIAL_OBJECT_COUNT + 2)
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
	apply_expect(t, &dm, &sim, game.Select_Object{id = id}, "select failed")
	apply_expect(t, &dm, &sim, game.Delete_Selected{}, "delete failed")
	testing.expect_value(t, game.simulation_object_count(&sim), game.INITIAL_OBJECT_COUNT - 1)
	testing.expect_value(t, dm.selection, game.Debug_Selection.None)
	testing.expect_value(t, game.debug_history_depth(&dm), 1)

	apply_expect(t, &dm, &sim, game.Undo{}, "undo failed")
	testing.expect_value(t, game.simulation_object_count(&sim), game.INITIAL_OBJECT_COUNT)
	testing.expect_value(t, game.simulation_object_box(&sim, id).center, placement.center)
	testing.expect_value(t, game.simulation_object_scale(&sim, id), 1.0)
	testing.expect_value(t, dm.selection, game.Debug_Selection.None)

	apply_expect(t, &dm, &sim, game.Redo{}, "redo failed")
	testing.expect_value(t, game.simulation_object_count(&sim), game.INITIAL_OBJECT_COUNT - 1)
	testing.expect_value(t, game.debug_history_depth(&dm), 1)
}

@(test)
body_conversion_recreates_at_the_transform_and_undoes :: proc(t: ^testing.T) {
	sim, dm := object_editor_setup(t)
	defer game.debug_mode_destroy(&dm)
	defer game.simulation_destroy(&sim)

	id := first_object_id(&sim)
	placement := game.simulation_object_box(&sim, id)
	apply_expect(t, &dm, &sim, game.Select_Object{id = id}, "select failed")
	old_body := game.simulation_object_body(&sim, id)
	b3.Body_SetLinearVelocity(old_body, {3.0, 4.0, 5.0})

	apply_expect(t, &dm, &sim, game.Flip_Body{}, "flip failed")
	body := game.simulation_object_body(&sim, id)
	testing.expect_value(t, b3.Body_GetType(body), b3.BodyType.staticBody)
	testing.expect(t, !b3.Body_IsValid(old_body), "the old body survived")
	testing.expect_value(t, b3.Body_GetLinearVelocity(body), b3.Vec3_zero)
	testing.expect_value(t, game.simulation_object_box(&sim, id).center, placement.center)
	testing.expect_value(t, game.debug_history_depth(&dm), 1)

	apply_expect(t, &dm, &sim, game.Set_Body{mode = .Static}, "same-mode convert failed")
	testing.expect_value(t, game.debug_history_depth(&dm), 1)

	apply_expect(t, &dm, &sim, game.Undo{}, "undo failed")
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

	apply_expect(t, &dm, &sim, game.Place_Object {
		prefab = .Pillar,
		body_mode = .Static,
		center = {0, 1.5, 10},
		yaw_rad = 0,
	}, "pillar did not place")
	pillar := dm.selected_object_id
	apply_expect(t, &dm, &sim, game.Select_Object{id = 0}, "clear failed")
	object_editor_select(&dm, &sim)
	testing.expect_value(t, dm.selected_object_id, pillar)

	before := game.simulation_object_box(&sim, pillar).center
	edit_step(&dm, &sim, {game.Drag_Move{look_delta = {10.0, 0.0}}})
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
	edit_step(&dm, &sim, {game.Primary_Release{}})
	id := first_object_id(&sim)
	before := game.simulation_object_box(&sim, id)

	edit_step(&dm, &sim, {game.Duplicate_Selected{}})
	testing.expect_value(t, game.simulation_object_count(&sim), game.INITIAL_OBJECT_COUNT + 1)
	testing.expect_value(t, game.debug_history_depth(&dm), 1)
	testing.expect(t, dm.selected_object_id != id, "duplicate did not select the copy")

	edit_step(&dm, &sim, {game.Undo{}})
	testing.expect_value(t, game.simulation_object_count(&sim), game.INITIAL_OBJECT_COUNT)
	testing.expect_value(t, game.debug_history_depth(&dm), 0)
	testing.expect_value(t, game.debug_history_redo_depth(&dm), 1)

	edit_step(&dm, &sim, {game.Redo{}})
	testing.expect_value(t, game.simulation_object_count(&sim), game.INITIAL_OBJECT_COUNT + 1)
	testing.expect_value(t, game.debug_history_depth(&dm), 1)

	apply_expect(t, &dm, &sim, game.Select_Object{id = id}, "select failed")
	apply_expect(t, &dm, &sim, game.Palette_Open{}, "open failed")
	apply_expect(t, &dm, &sim, game.Flip_Body{}, "flip failed")
	testing.expect_value(t, dm.palette.body_mode, game.Body_Mode.Static)
	selected, _ := game.simulation_object_find(&sim, id)
	testing.expect_value(t, selected.body_mode, game.Body_Mode.Dynamic)

	apply_expect(t, &dm, &sim, game.Palette_Close{}, "close failed")
	apply_expect(t, &dm, &sim, game.Flip_Body{}, "flip failed")
	object, _ := game.simulation_object_find(&sim, id)
	testing.expect_value(t, object.body_mode, game.Body_Mode.Static)
	testing.expect_value(t, game.simulation_object_box(&sim, id).center, before.center)
}
