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

@(test)
room_doorway_admits_player :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	east_inner_x: f32 = game.ARENA_ROOM_X + game.ARENA_ROOM_HALF_SIZE - game.ARENA_ROOM_WALL_THICKNESS
	place_at_room_approach(&sim, game.ARENA_ROOM_Z)
	step(&sim, game.Input_Snapshot{move_forward = 1.0}, 120)

	testing.expectf(
		t,
		sim.player.position.x > game.ARENA_ROOM_X,
		"player did not pass through the doorway: x=%v",
		sim.player.position.x,
	)
	testing.expectf(
		t,
		sim.player.position.x < east_inner_x,
		"player crossed the east wall: x=%v",
		sim.player.position.x,
	)
	expect_near(t, sim.player.position.z, game.ARENA_ROOM_Z, 0.1, "doorway drift")
	testing.expect(t, sim.player.grounded, "player lost the floor inside the room")
}

@(test)
room_wall_blocks_beside_the_doorway :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	beside_door_z: f32 = game.ARENA_ROOM_Z - game.ARENA_ROOM_DOOR_WIDTH
	place_at_room_approach(&sim, beside_door_z)
	step(&sim, game.Input_Snapshot{move_forward = 1.0}, 120)

	testing.expectf(
		t,
		sim.player.position.x < game.ARENA_ROOM_X - game.ARENA_ROOM_HALF_SIZE,
		"player entered through the wall beside the doorway: x=%v",
		sim.player.position.x,
	)
	testing.expectf(
		t,
		sim.player.position.x > game.ARENA_ROOM_X - game.ARENA_ROOM_HALF_SIZE - 1.0,
		"player stopped short of the wall: x=%v",
		sim.player.position.x,
	)
	expect_near(t, sim.player.position.z, beside_door_z, 0.1, "wall slide")
}
