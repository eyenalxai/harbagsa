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
	dm.active = true
	defer game.debug_mode_destroy(&dm)

	for index in 0 ..< 70 {
		apply_expect(t, &dm, &sim, game.Place_Object {
			prefab = .Block,
			body_mode = .Static,
			center = {f32(index) * 2.0, 0.5, -20.0},
			yaw_rad = 0,
		}, "place failed")
	}
	testing.expect_value(t, game.simulation_object_count(&sim), game.INITIAL_OBJECT_COUNT + 70)
	testing.expect_value(t, game.debug_history_depth(&dm), game.HISTORY_LIMIT)

	apply_expect(t, &dm, &sim, game.Undo{}, "undo failed")
	testing.expect_value(t, game.debug_history_depth(&dm), game.HISTORY_LIMIT - 1)
	testing.expect_value(t, game.debug_history_redo_depth(&dm), 1)
	apply_expect(t, &dm, &sim, game.Redo{}, "redo failed")
	testing.expect_value(t, game.debug_history_depth(&dm), game.HISTORY_LIMIT)
	testing.expect_value(t, game.debug_history_redo_depth(&dm), 0)

	apply_expect(t, &dm, &sim, game.Place_Object {
		prefab = .Block,
		body_mode = .Static,
		center = {40, 0.5, -20},
		yaw_rad = 0,
	}, "place failed")
	testing.expect_value(t, game.debug_history_depth(&dm), game.HISTORY_LIMIT)
	testing.expect_value(t, game.debug_history_redo_depth(&dm), 0)
}

@(test)
place_and_duplicate_grow_the_scene_past_the_old_cap :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)
	dm := game.debug_mode_create(context.allocator)
	dm.active = true
	defer game.debug_mode_destroy(&dm)

	for _ in 0 ..< 300 {
		_ = game.simulation_create_object(
			&sim,
			{prefab = .Block, body_mode = .Static, center = {0, -5, 0}, yaw_rad = 0},
		)
	}
	before := game.simulation_object_count(&sim)
	id := game.simulation_objects(&sim)[0].id
	apply_expect(t, &dm, &sim, game.Select_Object{id = id}, "select failed")

	apply_expect(t, &dm, &sim, game.Duplicate_Selected{}, "duplicate failed")
	testing.expect_value(t, game.simulation_object_count(&sim), before + 1)
	apply_expect(t, &dm, &sim, game.Place_Object {
		prefab = .Block,
		body_mode = .Static,
		center = {0, 1, 0},
		yaw_rad = 0,
	}, "place failed")
	testing.expect_value(t, game.simulation_object_count(&sim), before + 2)
	testing.expect_value(t, game.debug_history_depth(&dm), 2)
}

@(test)
undo_restores_colors_modes_and_transforms :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)
	dm := game.debug_mode_create(context.allocator)
	dm.active = true
	defer game.debug_mode_destroy(&dm)

	ids: [game.INITIAL_OBJECT_COUNT]game.Object_Id
	centers: [game.INITIAL_OBJECT_COUNT]b3.Vec3
	colors: [game.INITIAL_OBJECT_COUNT][4]f32
	for object, index in game.simulation_objects(&sim) {
		ids[index] = object.id
		box := game.simulation_object_box(&sim, object.id)
		centers[index] = box.center
		colors[index] = box.color
	}

	apply_expect(t, &dm, &sim, game.Select_Object{id = ids[0]}, "select failed")
	apply_expect(t, &dm, &sim, game.Move_Selected{center = {1, 2, 3}}, "move failed")
	apply_expect(t, &dm, &sim, game.Set_Body{mode = .Static}, "body failed")
	apply_expect(t, &dm, &sim, game.Undo{}, "undo body failed")
	apply_expect(t, &dm, &sim, game.Undo{}, "undo move failed")

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
	dm.active = true
	defer game.debug_mode_destroy(&dm)
	place_block(t, &sim, &dm, {4, 0.5, 9})
	testing.expect_value(t, game.debug_history_depth(&dm), 1)

	game.debug_mode_reset_scene(&dm, &sim)
	testing.expect_value(t, game.debug_history_depth(&dm), 0)
	testing.expect_value(t, game.debug_history_redo_depth(&dm), 0)
	testing.expect_value(t, game.simulation_object_count(&sim), game.INITIAL_OBJECT_COUNT)
}
