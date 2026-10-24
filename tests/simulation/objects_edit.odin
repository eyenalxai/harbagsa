#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package simulation

import "core:testing"

import b3 "libs:box3d"
import game "src:game"

@(test)
remove_object_destroys_body_and_shifts_list :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	objects := game.simulation_objects(&sim)
	id := objects[0].id
	body := game.simulation_object_body(&sim, id)
	next_id := objects[1].id
	next_center := game.simulation_object_box(&sim, next_id).center

	testing.expect(t, game.simulation_remove_object(&sim, id), "remove failed")
	testing.expect(t, !b3.Body_IsValid(body), "removed object body is still valid")
	testing.expect_value(t, game.simulation_object_count(&sim), game.INITIAL_CRATE_COUNT - 1)
	testing.expect_value(t, game.simulation_objects(&sim)[0].id, next_id)
	testing.expect_value(t, game.simulation_object_box(&sim, next_id).center, next_center)
	testing.expect(t, !game.simulation_remove_object(&sim, id), "second remove succeeded")
	testing.expect(t, !game.simulation_remove_object(&sim, 99), "unknown id remove succeeded")
}

@(test)
move_object_sets_position_and_stops_velocity :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	id := game.simulation_objects(&sim)[0].id
	body := game.simulation_object_body(&sim, id)
	b3.Body_SetLinearVelocity(body, {3, 4, 5})
	b3.Body_SetAngularVelocity(body, {1, 2, 3})

	target := b3.Vec3{1.0, 2.0, 3.0}
	testing.expect(t, game.simulation_move_object(&sim, id, target), "move failed")

	testing.expect_value(t, game.simulation_object_box(&sim, id).center, target)
	testing.expect_value(t, b3.Body_GetLinearVelocity(body), b3.Vec3_zero)
	testing.expect_value(t, b3.Body_GetAngularVelocity(body), b3.Vec3_zero)
	testing.expect(t, b3.Body_IsAwake(body), "moved object is asleep")
}

@(test)
object_yaw_round_trips :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	id := game.simulation_create_object(
		&sim,
		{prefab = .Ramp, body_mode = .Static, center = {0, 5, 0}, yaw = 0},
	)
	testing.expect(t, id != game.INVALID_OBJECT_ID, "ramp did not create")
	expect_near(t, game.simulation_object_yaw(&sim, id), 0.0, 0.0001, "initial yaw")

	testing.expect(t, game.simulation_set_object_yaw(&sim, id, 1.1), "set yaw failed")
	expect_near(t, game.simulation_object_yaw(&sim, id), 1.1, 0.01, "ramp yaw")

	q := game.simulation_object_box(&sim, id).rotation
	length_sq := q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w
	expect_near(t, length_sq, 1.0, 0.0001, "ramp rotation length")
}

@(test)
convert_object_recreates_the_body :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	id := game.simulation_create_object(
		&sim,
		{prefab = .Crate, body_mode = .Dynamic, center = {3, 5, 3}, yaw = 0.3},
	)
	body := game.simulation_object_body(&sim, id)
	b3.Body_SetLinearVelocity(body, {3, 4, 5})

	testing.expect(t, game.simulation_convert_object(&sim, id, .Static), "static convert failed")
	static_body := game.simulation_object_body(&sim, id)
	testing.expect_value(t, b3.Body_GetType(static_body), b3.BodyType.staticBody)
	testing.expect_value(t, game.simulation_object_box(&sim, id).center, b3.Vec3{3, 5, 3})
	testing.expect_value(t, b3.Body_GetLinearVelocity(static_body), b3.Vec3_zero)

	testing.expect(t, game.simulation_convert_object(&sim, id, .Dynamic), "dynamic convert failed")
	dynamic_body := game.simulation_object_body(&sim, id)
	testing.expect_value(t, b3.Body_GetType(dynamic_body), b3.BodyType.dynamicBody)
	testing.expect_value(t, game.simulation_object_box(&sim, id).center, b3.Vec3{3, 5, 3})
	object, _ := game.simulation_object_find(&sim, id)
	testing.expect_value(t, object.body_mode, game.Body_Mode.Dynamic)
}

@(test)
reset_scene_restores_starting_objects_and_player :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	_ = game.simulation_remove_object(&sim, game.simulation_objects(&sim)[0].id)
	_ = game.simulation_create_object(
		&sim,
		{prefab = .Block, body_mode = .Static, center = {5, 5, 5}, yaw = 0},
	)
	sim.player.position = {1, 2, 3}

	game.simulation_reset_scene(&sim)

	objects := game.simulation_objects(&sim)
	colors := game.INITIAL_CRATE_COLORS
	testing.expect_value(t, len(objects), game.INITIAL_CRATE_COUNT)
	for position, index in game.INITIAL_CRATE_POSITIONS {
		object := objects[index]
		testing.expect_value(t, object.id, game.Object_Id(index + 1))
		testing.expect_value(t, game.simulation_object_box(&sim, object.id).center, position)
		testing.expect_value(
			t,
			game.simulation_object_box(&sim, object.id).color,
			colors[index],
		)
	}
	testing.expect_value(t, sim.player.position, game.SPAWN_POSITION)
}

@(test)
object_id_lookup_finds_the_body_owner :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	objects := game.simulation_objects(&sim)
	testing.expect_value(
		t,
		game.simulation_object_id_for_body(&sim, objects[1].body),
		objects[1].id,
	)
	testing.expect_value(t, game.simulation_object_id_for_body(&sim, {}), game.INVALID_OBJECT_ID)
}
