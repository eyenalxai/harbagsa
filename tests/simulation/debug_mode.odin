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

	camera := dm.camera
	expected_eye := before.position + b3.Vec3{0.0, game.PLAYER_STANDING_EYE, 0.0}
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
	player_before := sim.player
	step_distance: f32 = game.DEBUG_FLY_SPEED * 0.1

	start := dm.camera.position
	game.debug_mode_update(&dm, &sim, game.Debug_Input{captured = true, move_forward = 1.0}, 0.1)
	expect_near(t, dm.camera.position.z, start.z - step_distance, 0.001, "forward speed")
	expect_near(t, dm.camera.position.x, start.x, 0.001, "forward drift x")
	expect_near(t, dm.camera.position.y, start.y, 0.001, "forward drift y")

	start = dm.camera.position
	game.debug_mode_update(&dm, &sim, game.Debug_Input{captured = true, move_right = 1.0}, 0.1)
	expect_near(t, dm.camera.position.x, start.x + step_distance, 0.001, "strafe speed")
	expect_near(t, dm.camera.position.y, start.y, 0.001, "strafe drift y")

	start = dm.camera.position
	game.debug_mode_update(&dm, &sim, game.Debug_Input{captured = true, move_up = 1.0}, 0.1)
	expect_near(t, dm.camera.position.y, start.y + step_distance, 0.001, "fly up speed")

	start = dm.camera.position
	game.debug_mode_update(&dm, &sim, game.Debug_Input{captured = true, move_up = -1.0}, 0.1)
	expect_near(t, dm.camera.position.y, start.y - step_distance, 0.001, "fly down speed")

	start = dm.camera.position
	game.debug_mode_update(
		&dm,
		&sim,
		game.Debug_Input{captured = true, move_forward = 1.0, move_up = 1.0},
		0.1,
	)
	expect_near(t, b3.Length(dm.camera.position - start), step_distance, 0.001, "diagonal speed")

	testing.expect_value(t, sim.player.position, player_before.position)
	testing.expect_value(t, sim.player.velocity, player_before.velocity)
}

@(test)
debug_mode_sun_direction_is_normalized :: proc(t: ^testing.T) {
	dm := game.debug_mode_create()
	dm.sun.position = {0.0, 100.0, 0.0}

	direction := game.debug_mode_sun_direction(&dm)
	length := math.sqrt(
		direction.x * direction.x + direction.y * direction.y + direction.z * direction.z,
	)
	expect_near(t, length, 1.0, 0.0001, "sun direction length")
}

@(test)
debug_mode_sun_angles_follow_direction :: proc(t: ^testing.T) {
	dm := game.debug_mode_create()
	dm.sun.position = {0.0, 50.0, 0.0}

	azimuth, elevation := game.debug_mode_sun_angles(&dm)
	expect_near(t, azimuth, 0.0, 0.0001, "azimuth")
	expect_near(t, elevation, f32(math.atan2(1.0, 0.1)), 0.0001, "elevation")
}

@(test)
debug_mode_sun_angles_are_positive_above_the_horizon :: proc(t: ^testing.T) {
	dm := game.debug_mode_create()
	azimuth, elevation := game.debug_mode_sun_angles(&dm)
	testing.expectf(t, elevation > 0, "the default sun reads below the horizon: %v", elevation)

	round_trip := game.sun_direction_from_angles(azimuth, elevation)
	expected := b3.Normalize(game.sun_direction_from_light(game.DEFAULT_SUN_DIRECTION))
	expect_direction_near(t, round_trip, expected, 0.001)
}

@(test)
reset_player_moves_the_debug_camera_to_spawn :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	dm := game.debug_mode_create()
	game.debug_mode_toggle(&dm, &sim)
	dm.camera.position = {5, 5, 5}

	game.debug_mode_reset_player(&dm, &sim)

	expected := game.SPAWN_POSITION + b3.Vec3{0.0, game.PLAYER_STANDING_EYE, 0.0}
	testing.expect_value(t, dm.camera.position, expected)
	testing.expect_value(t, sim.player.position, game.SPAWN_POSITION)
}

@(test)
reset_scene_restores_objects_sun_and_player :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	dm := game.debug_mode_create()
	game.debug_mode_toggle(&dm, &sim)

	_ = game.simulation_remove_object(&sim, game.simulation_objects(&sim)[0].id)
	_ = game.simulation_create_object(
		&sim,
		{prefab = .Crate, body_mode = .Dynamic, center = {5, 5, 5}, yaw = 0.0},
	)
	dm.sun.position = {0.0, 50.0, 0.0}
	dm.sun.active = true
	dm.sun.saved_position = {0.0, 40.0, 0.0}
	dm.selection = .Object
	dm.selected_object_id = game.simulation_objects(&sim)[0].id
	dm.dragging = .Object
	dm.camera.position = {5, 5, 5}

	game.debug_mode_reset_scene(&dm, &sim)

	testing.expect_value(t, game.simulation_object_count(&sim), game.INITIAL_CRATE_COUNT)
	testing.expect_value(t, dm.sun.position, game.DEFAULT_SUN_POSITION)
	testing.expect(t, !dm.sun.active, "scene reset left sun placement active")
	testing.expect_value(t, dm.selection, game.Debug_Selection.None)
	testing.expect_value(t, dm.selected_object_id, game.INVALID_OBJECT_ID)
	testing.expect_value(t, dm.dragging, game.Debug_Drag.None)
	testing.expect_value(t, sim.player.position, game.SPAWN_POSITION)
	expected_eye := game.SPAWN_POSITION + b3.Vec3{0.0, game.PLAYER_STANDING_EYE, 0.0}
	testing.expect_value(t, dm.camera.position, expected_eye)
}
