#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package simulation

import "core:testing"

import game "src:game"

@(test)
object_names_are_unique_and_survive_a_snapshot :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	id := game.simulation_create_object(
		&sim,
		{
			name = "alpha",
			prefab = .Block,
			body_mode = .Static,
			center = {0, 0.5, 5},
		},
	)
	testing.expect(t, id != game.INVALID_OBJECT_ID, "named placement failed")
	testing.expect_value(t, game.simulation_object_name(&sim, id), "alpha")
	object, found := game.simulation_object_find_by_name(&sim, "alpha")
	testing.expect(t, found, "the name did not resolve")
	if found {
		testing.expect_value(t, object.id, id)
	}

	duplicate := game.simulation_create_object(
		&sim,
		{
			name = "alpha",
			prefab = .Block,
			body_mode = .Static,
			center = {2, 0.5, 5},
		},
	)
	testing.expect_value(t, duplicate, game.INVALID_OBJECT_ID)
	testing.expect_value(t, game.simulation_object_count(&sim), game.INITIAL_OBJECT_COUNT + 1)

	snapshot := game.object_snapshot_capture(&sim, context.allocator)
	defer game.object_snapshot_destroy(&snapshot, context.allocator)
	testing.expect(
		t,
		game.simulation_apply_snapshot(&sim, snapshot),
		"the snapshot restore failed",
	)
	testing.expect_value(t, game.simulation_object_name(&sim, id), "alpha")

	testing.expect(t, game.simulation_remove_object(&sim, id), "remove failed")
	_, still_there := game.simulation_object_find_by_name(&sim, "alpha")
	testing.expect(t, !still_there, "the name outlived the object")
}

@(test)
object_name_rules :: proc(t: ^testing.T) {
	testing.expect(t, game.object_name_valid(""))
	testing.expect(t, game.object_name_valid("west-a"))
	testing.expect(t, !game.object_name_valid("west a"))
	testing.expect(t, !game.object_name_valid("123"))
	testing.expect(t, !game.object_name_valid("count"))
	testing.expect(t, !game.object_name_valid("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"))
}
