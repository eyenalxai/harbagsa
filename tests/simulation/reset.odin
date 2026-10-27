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
	sim.player.jump_buffer = 0.1
	game.simulation_reset(&sim)

	testing.expect(t, sim.player.position == game.SPAWN_POSITION, "position is not spawn")
	testing.expect(t, sim.player.previous_position == game.SPAWN_POSITION, "previous position is not spawn")
	testing.expect(t, sim.player.velocity == b3.Vec3_zero, "velocity is not zero")
	testing.expect(t, sim.player.yaw == 0.0, "yaw is not zero")
	testing.expect(t, sim.player.camera_yaw == 0.0, "camera yaw is not zero")
	testing.expect_value(t, sim.player.camera_pitch, game.CAMERA_DEFAULT_PITCH)
	testing.expect(t, !sim.player.grounded, "grounded state was not cleared")
	testing.expect_value(t, sim.player.gait, game.Gait.Walk)
	testing.expect(t, !sim.player.sprint_toggled, "sprint selection was not cleared")
	testing.expect_value(t, sim.player.jump_buffer, f32(0.0))
	testing.expect_value(t, game.spider_planted_count(&sim.player), game.LEG_COUNT)
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
	testing.expect(t, sim.player.camera_yaw == 0.0, "camera yaw is not zero")
	testing.expect_value(t, sim.player.camera_pitch, game.CAMERA_DEFAULT_PITCH)
}

@(test)
snapshot_exposes_interpolation_state :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	step(&sim, game.Input_Snapshot{move_forward = 1.0}, 30)
	snapshot := game.simulation_snapshot(&sim)

	testing.expect(t, snapshot.position == sim.player.position, "snapshot position is stale")
	testing.expect(t, snapshot.previous_position == sim.player.previous_position, "snapshot previous position is stale")
	testing.expect(t, snapshot.position.z < snapshot.previous_position.z, "player did not move between snapshots")
	testing.expect(t, snapshot.body_yaw == sim.player.yaw, "snapshot body yaw is stale")
	testing.expect(t, snapshot.camera_yaw == sim.player.camera_yaw, "snapshot camera yaw is stale")
	testing.expect(t, snapshot.camera_pitch == sim.player.camera_pitch, "snapshot camera pitch is stale")
	testing.expect(t, snapshot.grounded == sim.player.grounded, "snapshot grounded state is stale")
	testing.expect_value(t, len(snapshot.legs), game.LEG_COUNT)
}

@(test)
object_rotation_is_exposed_for_the_renderer :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	step(&sim, game.Input_Snapshot{move_forward = 1.0}, 120)
	id := game.simulation_objects(&sim)[0].id
	q := game.simulation_object_box(&sim, id).rotation
	length_sq := q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w
	testing.expectf(t, abs(length_sq - 1.0) < 0.01, "object rotation is not normalized: %v", length_sq)
}
