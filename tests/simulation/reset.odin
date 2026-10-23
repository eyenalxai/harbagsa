#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package simulation

import "core:testing"
import b3 "libs:box3d"
import game "src:game"

@(test)
reset_returns_player_to_spawn :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	game.simulation_look(&sim, {10.0, 5.0})
	step(&sim, game.Input_Snapshot{move_forward = 1.0}, 30)
	step(&sim, game.Input_Snapshot{reset_pressed = true}, 1)

	testing.expect(t, sim.player.position == game.SPAWN_POSITION, "position is not spawn")
	testing.expect(t, sim.player.previous_position == game.SPAWN_POSITION, "previous position is not spawn")
	testing.expect(t, sim.player.velocity == b3.Vec3_zero, "velocity is not zero")
	testing.expect(t, sim.player.yaw == 0.0, "yaw is not zero")
	testing.expect(t, sim.player.pitch == 0.0, "pitch is not zero")
	testing.expect(t, !sim.player.grounded, "grounded state was not cleared")
}

@(test)
falling_below_arena_resets_player :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	sim.player.position = {0.0, game.FALL_RESET_Y - 1.0, 0.0}
	sim.player.velocity = {1.0, -20.0, 2.0}
	step(&sim, {}, 1)

	testing.expect(t, sim.player.position == game.SPAWN_POSITION, "position is not spawn")
	testing.expect(t, sim.player.previous_position == game.SPAWN_POSITION, "previous position is not spawn")
	testing.expect(t, sim.player.velocity == b3.Vec3_zero, "velocity is not zero")
	testing.expect(t, sim.player.yaw == 0.0, "yaw is not zero")
	testing.expect(t, sim.player.pitch == 0.0, "pitch is not zero")
}

@(test)
snapshot_exposes_interpolation_state :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	step(&sim, game.Input_Snapshot{move_forward = 1.0}, 30)
	snapshot := game.simulation_snapshot(&sim)

	testing.expect(t, snapshot.position == sim.player.position, "snapshot position is stale")
	testing.expect(t, snapshot.previous_position == sim.player.previous_position, "snapshot previous position is stale")
	expect_near(
		t,
		snapshot.eye_position.y,
		snapshot.position.y + game.PLAYER_EYE_HEIGHT,
		0.0001,
		"eye height",
	)
	testing.expect(t, snapshot.position.z < snapshot.previous_position.z, "player did not move between snapshots")
	testing.expect(t, snapshot.yaw == sim.player.yaw, "snapshot yaw is stale")
	testing.expect(t, snapshot.pitch == sim.player.pitch, "snapshot pitch is stale")
	testing.expect(t, snapshot.grounded == sim.player.grounded, "snapshot grounded state is stale")
}

@(test)
crate_rotation_is_exposed_for_the_renderer :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	step(&sim, game.Input_Snapshot{move_forward = 1.0}, 120)
	q := game.simulation_crate_box(&sim, 0).rotation
	length_sq := q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w
	testing.expectf(t, abs(length_sq - 1.0) < 0.01, "crate rotation is not normalized: %v", length_sq)
}
