#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package simulation

import "core:testing"

import b3 "libs:box3d"
import game "src:game"

@(test)
history_caps_at_64_and_a_new_edit_clears_redo :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)
	dm := game.debug_mode_create(context.allocator)
	defer game.debug_mode_destroy(&dm)

	for index in 0 ..< 70 {
		_ = game.debug_place_object(
			&dm,
			&sim,
			{
				prefab = .Block,
				body_mode = .Static,
				center = {f32(index) * 2.0, 0.5, -20.0},
				yaw = 0,
			},
		)
	}
	testing.expect_value(t, game.simulation_object_count(&sim), game.INITIAL_CRATE_COUNT + 70)
	testing.expect_value(t, game.debug_history_depth(&dm), game.HISTORY_LIMIT)

	_ = game.debug_undo(&dm, &sim)
	testing.expect_value(t, game.debug_history_depth(&dm), game.HISTORY_LIMIT - 1)
	testing.expect_value(t, game.debug_history_redo_depth(&dm), 1)
	_ = game.debug_redo(&dm, &sim)
	testing.expect_value(t, game.debug_history_depth(&dm), game.HISTORY_LIMIT)
	testing.expect_value(t, game.debug_history_redo_depth(&dm), 0)

	_ = game.debug_place_object(
		&dm,
		&sim,
		{prefab = .Block, body_mode = .Static, center = {40, 0.5, -20}, yaw = 0},
	)
	testing.expect_value(t, game.debug_history_depth(&dm), game.HISTORY_LIMIT)
	testing.expect_value(t, game.debug_history_redo_depth(&dm), 0)
}

@(test)
capacity_blocks_place_and_duplicate_without_history :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)
	dm := game.debug_mode_create(context.allocator)
	defer game.debug_mode_destroy(&dm)

	for game.simulation_object_count(&sim) < game.MAX_PLACED_OBJECTS {
		_ = game.simulation_create_object(
			&sim,
			{prefab = .Block, body_mode = .Static, center = {0, -5, 0}, yaw = 0},
		)
	}
	id := game.simulation_objects(&sim)[0].id
	testing.expect(t, game.debug_select_object(&dm, &sim, id), "select failed")

	testing.expect_value(t, game.debug_duplicate_selected(&dm, &sim), game.INVALID_OBJECT_ID)
	testing.expect_value(
		t,
		game.debug_place_object(
			&dm,
			&sim,
			{prefab = .Block, body_mode = .Static, center = {0, 1, 0}, yaw = 0},
		),
		game.INVALID_OBJECT_ID,
	)
	testing.expect_value(t, game.simulation_object_count(&sim), game.MAX_PLACED_OBJECTS)
	testing.expect_value(t, game.debug_history_depth(&dm), 0)
}

@(test)
undo_restores_colors_modes_and_transforms :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)
	dm := game.debug_mode_create(context.allocator)
	defer game.debug_mode_destroy(&dm)

	ids: [game.INITIAL_CRATE_COUNT]game.Object_Id
	centers: [game.INITIAL_CRATE_COUNT]b3.Vec3
	colors: [game.INITIAL_CRATE_COUNT][4]f32
	for object, index in game.simulation_objects(&sim) {
		ids[index] = object.id
		box := game.simulation_object_box(&sim, object.id)
		centers[index] = box.center
		colors[index] = box.color
	}

	testing.expect(t, game.debug_select_object(&dm, &sim, ids[0]), "select failed")
	testing.expect(t, game.debug_move_selected(&dm, &sim, {1, 2, 3}), "move failed")
	testing.expect(t, game.debug_convert_selected(&dm, &sim, .Static), "body failed")
	testing.expect(t, game.debug_undo(&dm, &sim), "undo body failed")
	testing.expect(t, game.debug_undo(&dm, &sim), "undo move failed")

	for object, index in game.simulation_objects(&sim) {
		testing.expect_value(t, object.id, ids[index])
		box := game.simulation_object_box(&sim, object.id)
		testing.expect_value(t, box.center, centers[index])
		testing.expect_value(t, box.color, colors[index])
		testing.expect_value(t, object.body_mode, game.Body_Mode.Dynamic)
	}
}

@(test)
reset_scene_clears_history :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)
	dm := game.debug_mode_create(context.allocator)
	defer game.debug_mode_destroy(&dm)
	_ = place_block(&sim, &dm, {4, 0.5, 9})
	testing.expect_value(t, game.debug_history_depth(&dm), 1)

	game.debug_mode_reset_scene(&dm, &sim)
	testing.expect_value(t, game.debug_history_depth(&dm), 0)
	testing.expect_value(t, game.debug_history_redo_depth(&dm), 0)
	testing.expect_value(t, game.simulation_object_count(&sim), game.INITIAL_CRATE_COUNT)
}

