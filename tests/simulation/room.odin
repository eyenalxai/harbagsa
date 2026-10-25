#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package simulation

import "core:math"
import "core:testing"

import b3 "libs:box3d"
import game "src:game"

@(private)
place_at_room_approach :: proc(sim: ^game.Simulation, z: f32) {
	approach_x: f32 = game.ARENA_ROOM_X - game.ARENA_ROOM_HALF_SIZE - 2.0
	game.player_place(
		&sim.player,
		b3.Vec3{approach_x, game.SPAWN_POSITION.y, z},
		-math.PI * 0.5,
		0.0,
	)
}

@(private)
walk_until :: proc(
	sim: ^game.Simulation,
	yaw: f32,
	done: proc(position: b3.Vec3) -> bool,
) -> bool {
	sim.player.yaw = yaw
	for _ in 0 ..< 240 {
		game.simulation_step(sim, game.Input_Snapshot{move_forward = 1.0}, DT)
		if done(sim.player.position) {
			return true
		}
	}
	return false
}

@(private)
past_connector_1 :: proc(position: b3.Vec3) -> bool {
	return position.x > game.ARENA_ROOM_CONNECTOR_1_LOW_X + 0.3
}

@(private)
past_wall_a :: proc(position: b3.Vec3) -> bool {
	return position.z < game.ARENA_ROOM_LANE_2_HIGH_Z - 0.3
}

@(private)
past_connector_2 :: proc(position: b3.Vec3) -> bool {
	return position.x < game.ARENA_ROOM_CONNECTOR_2_HIGH_X - 0.3
}

@(private)
past_wall_b :: proc(position: b3.Vec3) -> bool {
	return position.z < game.ARENA_ROOM_LANE_3_HIGH_Z - 0.3
}

@(private)
past_exit :: proc(position: b3.Vec3) -> bool {
	return position.x > game.ARENA_ROOM_CHAMBER_LOW_X + 0.3
}

@(test)
room_doorway_admits_player :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	place_at_room_approach(&sim, game.ARENA_ROOM_DOOR_Z)
	step(&sim, game.Input_Snapshot{move_forward = 1.0}, 120)

	testing.expectf(
		t,
		sim.player.position.x > game.ARENA_ROOM_INNER_LOW_X + 2.0,
		"player did not pass through the doorway: x=%v",
		sim.player.position.x,
	)
	testing.expectf(
		t,
		sim.player.position.x < game.ARENA_ROOM_CONNECTOR_1_HIGH_X,
		"player crossed the tunnel's east wall: x=%v",
		sim.player.position.x,
	)
	expect_near(t, sim.player.position.z, game.ARENA_ROOM_DOOR_Z, 0.1, "doorway drift")
	testing.expect(t, sim.player.grounded, "player lost the floor inside the tunnel")
}

@(test)
room_wall_blocks_beside_the_doorway :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	beside_door_z: f32 = game.ARENA_ROOM_DOOR_Z - 2.0
	place_at_room_approach(&sim, beside_door_z)
	step(&sim, game.Input_Snapshot{move_forward = 1.0}, 120)

	testing.expectf(
		t,
		sim.player.position.x < game.ARENA_ROOM_INNER_LOW_X,
		"player entered through the wall beside the doorway: x=%v",
		sim.player.position.x,
	)
	testing.expectf(
		t,
		sim.player.position.x > game.ARENA_ROOM_INNER_LOW_X - 1.0,
		"player stopped short of the wall: x=%v",
		sim.player.position.x,
	)
	expect_near(t, sim.player.position.z, beside_door_z, 0.1, "wall slide")
}

@(test)
room_tunnel_reaches_the_chamber :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	place_at_room_approach(&sim, game.ARENA_ROOM_DOOR_Z)
	testing.expect(t, walk_until(&sim, -math.PI * 0.5, past_connector_1), "east leg failed")
	testing.expect(t, walk_until(&sim, 0.0, past_wall_a), "south leg failed")
	testing.expect(t, walk_until(&sim, math.PI * 0.5, past_connector_2), "west leg failed")
	testing.expect(t, walk_until(&sim, 0.0, past_wall_b), "second south leg failed")
	testing.expect(t, walk_until(&sim, -math.PI * 0.5, past_exit), "east exit failed")

	testing.expectf(
		t,
		sim.player.position.x > game.ARENA_ROOM_CHAMBER_LOW_X,
		"player did not reach the chamber: x=%v",
		sim.player.position.x,
	)
	testing.expectf(
		t,
		sim.player.position.z > game.ARENA_ROOM_LANE_3_LOW_Z &&
		sim.player.position.z < game.ARENA_ROOM_LANE_3_HIGH_Z,
		"player left the exit lane: z=%v",
		sim.player.position.z,
	)
	testing.expect(t, sim.player.grounded, "player lost the floor in the chamber")
}
