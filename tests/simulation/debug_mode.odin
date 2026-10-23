#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package simulation

import "core:math"
import "core:testing"
import b3 "libs:box3d"
import game "src:game"

@(test)
debug_mode_toggle_saves_and_restores_player :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	step(&sim, game.Input_Snapshot{move_forward = 1.0}, 30)
	before := sim.player

	dm := game.debug_mode_create()
	game.debug_mode_toggle(&dm, &sim)
	testing.expect(t, dm.active, "debug mode did not open")

	camera := game.debug_mode_camera(&dm)
	expected_eye := before.position + b3.Vec3{0.0, game.PLAYER_EYE_HEIGHT, 0.0}
	testing.expect_value(t, camera.position, expected_eye)
	testing.expect_value(t, camera.yaw, before.yaw)
	testing.expect_value(t, camera.pitch, before.pitch)

	dm.camera.position = {10, 20, 30}
	dm.camera.yaw = 1.0
	dm.camera.pitch = 0.5
	game.debug_mode_toggle(&dm, &sim)

	testing.expect(t, !dm.active, "debug mode did not close")
	testing.expect_value(t, sim.player.position, before.position)
	testing.expect_value(t, sim.player.yaw, before.yaw)
	testing.expect_value(t, sim.player.pitch, before.pitch)
	testing.expect_value(t, sim.player.velocity, b3.Vec3_zero)
}

@(test)
free_fly_moves_horizontally_and_vertically :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	dm := game.debug_mode_create()
	game.debug_mode_toggle(&dm, &sim)
	start := dm.camera.position
	player_before := sim.player

	game.debug_mode_update(
		&dm,
		&sim,
		game.Debug_Input{captured = true, move_forward = 1.0, move_up = 1.0},
		0.1,
	)

	testing.expectf(t, dm.camera.position.z < start.z - 0.5, "fly did not move forward: %v", dm.camera.position)
	testing.expectf(t, dm.camera.position.y > start.y + 0.5, "fly did not move up: %v", dm.camera.position)
	testing.expect_value(t, sim.player.position, player_before.position)
	testing.expect_value(t, sim.player.velocity, player_before.velocity)
}

@(test)
debug_mode_light_direction_is_normalized :: proc(t: ^testing.T) {
	dm := game.debug_mode_create()
	dm.light_direction = {0.0, -2.0, 0.0}

	direction := game.debug_mode_light_direction(&dm)
	length := math.sqrt(
		direction.x * direction.x + direction.y * direction.y + direction.z * direction.z,
	)
	expect_near(t, length, 1.0, 0.0001, "light direction length")
}

@(test)
debug_mode_light_angles_follow_direction :: proc(t: ^testing.T) {
	dm := game.debug_mode_create()
	dm.light_direction = {0.0, -1.0, 0.0}

	azimuth, elevation := game.debug_mode_light_angles(&dm)
	expect_near(t, azimuth, 0.0, 0.0001, "azimuth")
	expect_near(t, elevation, -math.PI / 2.0, 0.0001, "elevation")
}

@(test)
reset_player_moves_the_debug_camera_to_spawn :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	dm := game.debug_mode_create()
	game.debug_mode_toggle(&dm, &sim)
	dm.camera.position = {5, 5, 5}

	game.debug_mode_reset_player(&dm, &sim)

	expected := game.SPAWN_POSITION + b3.Vec3{0.0, game.PLAYER_EYE_HEIGHT, 0.0}
	testing.expect_value(t, dm.camera.position, expected)
	testing.expect_value(t, sim.player.position, game.SPAWN_POSITION)
}

@(test)
reset_scene_restores_crates_light_and_player :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	dm := game.debug_mode_create()
	game.debug_mode_toggle(&dm, &sim)

	_ = game.simulation_remove_crate(&sim, 0)
	_ = game.simulation_add_default_crate(&sim, {5, 5, 5})
	dm.light_direction = {0.0, -1.0, 0.0}
	dm.selection = .Crate
	dm.selected_crate = 0
	dm.dragging = .Crate
	dm.camera.position = {5, 5, 5}

	game.debug_mode_reset_scene(&dm, &sim)

	testing.expect_value(t, game.simulation_crate_count(&sim), game.INITIAL_CRATE_COUNT)
	testing.expect_value(t, dm.light_direction, game.DEFAULT_LIGHT_DIRECTION)
	testing.expect_value(t, dm.selection, game.Debug_Selection.None)
	testing.expect_value(t, dm.selected_crate, -1)
	testing.expect_value(t, dm.dragging, game.Debug_Drag.None)
	testing.expect_value(t, sim.player.position, game.SPAWN_POSITION)
	expected_eye := game.SPAWN_POSITION + b3.Vec3{0.0, game.PLAYER_EYE_HEIGHT, 0.0}
	testing.expect_value(t, dm.camera.position, expected_eye)
}
