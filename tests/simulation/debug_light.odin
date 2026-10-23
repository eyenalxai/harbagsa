#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package simulation

import "core:math"
import "core:testing"

import b3 "libs:box3d"
import game "src:game"

@(private)
expect_direction_near :: proc(t: ^testing.T, actual, expected: [3]f32, tolerance: f32) {
	for component, index in actual {
		testing.expectf(
			t,
			abs(component - expected[index]) <= tolerance,
			"component %d: got %v, want %v",
			index,
			component,
			expected[index],
		)
	}
}

@(private)
create_light_test :: proc(t: ^testing.T) -> (game.Simulation, game.Debug_Mode) {
	sim := create(t)
	dm := game.debug_mode_create()
	dm.active = true
	dm.camera.position = {0.0, 50.0, 0.0}
	dm.camera.pitch = 1.0
	return sim, dm
}

@(test)
light_angle_round_trip :: proc(t: ^testing.T) {
	directions := [5][3]f32 {
		game.DEFAULT_LIGHT_DIRECTION,
		{1.0, -1.0, 0.0},
		{0.0, -1.0, 1.0},
		{-2.0, -3.0, 4.0},
		{0.5, -0.1, -0.5},
	}

	for direction in directions {
		azimuth, elevation := game.light_angles_from_direction(direction)
		round_trip := game.light_direction_from_angles(azimuth, elevation)
		expect_direction_near(t, round_trip, b3.Normalize(direction), 0.001)
	}
}

@(test)
light_key_toggles_selection :: proc(t: ^testing.T) {
	sim, dm := create_light_test(t)
	defer game.simulation_destroy(&sim)

	game.debug_mode_update(&dm, &sim, {light_pressed = true}, DT)
	testing.expect_value(t, dm.selection, game.Debug_Selection.Light)
	testing.expect_value(t, dm.selected_crate, -1)
	testing.expect_value(t, dm.dragging, game.Debug_Drag.None)

	game.debug_mode_update(&dm, &sim, {light_pressed = true}, DT)
	testing.expect_value(t, dm.selection, game.Debug_Selection.None)
	testing.expect_value(t, dm.dragging, game.Debug_Drag.None)
}

@(test)
light_drag_changes_angles :: proc(t: ^testing.T) {
	sim, dm := create_light_test(t)
	defer game.simulation_destroy(&sim)

	game.debug_mode_update(&dm, &sim, {light_pressed = true}, DT)
	azimuth := dm.light_azimuth
	elevation := dm.light_elevation

	game.debug_mode_update(&dm, &sim, {primary_pressed = true, captured = true}, DT)
	testing.expect_value(t, dm.dragging, game.Debug_Drag.Light)

	game.debug_mode_update(
		&dm,
		&sim,
		{look_delta = {100.0, 50.0}, captured = true},
		DT,
	)

	testing.expect(t, dm.light_azimuth != azimuth, "azimuth did not change")
	testing.expect(t, dm.light_elevation != elevation, "elevation did not change")
	testing.expect(
		t,
		dm.light_direction != game.DEFAULT_LIGHT_DIRECTION,
		"light direction did not change",
	)
}

@(test)
light_elevation_clamps :: proc(t: ^testing.T) {
	sim, dm := create_light_test(t)
	defer game.simulation_destroy(&sim)

	game.debug_mode_update(&dm, &sim, {light_pressed = true}, DT)
	game.debug_mode_update(&dm, &sim, {primary_pressed = true, captured = true}, DT)

	game.debug_mode_update(&dm, &sim, {look_delta = {0.0, -1000.0}, captured = true}, DT)
	testing.expect(t, dm.light_elevation <= -0.05, "elevation rose above the upper clamp")
	testing.expect(t, dm.light_elevation >= -1.5, "elevation fell below the lower clamp")
	expect_near(t, dm.light_elevation, -0.05, 0.0001, "upper elevation clamp")

	game.debug_mode_update(&dm, &sim, {look_delta = {0.0, 1000.0}, captured = true}, DT)
	testing.expect(t, dm.light_elevation <= -0.05, "elevation rose above the upper clamp")
	testing.expect(t, dm.light_elevation >= -1.5, "elevation fell below the lower clamp")
	expect_near(t, dm.light_elevation, -1.5, 0.0001, "lower elevation clamp")
}

@(test)
light_click_deselects_and_drag_keeps_selection :: proc(t: ^testing.T) {
	sim, dm := create_light_test(t)
	defer game.simulation_destroy(&sim)

	game.debug_mode_update(&dm, &sim, {light_pressed = true}, DT)
	game.debug_mode_update(&dm, &sim, {primary_pressed = true, captured = true}, DT)
	game.debug_mode_update(&dm, &sim, {primary_released = true, captured = true}, DT)
	testing.expect_value(t, dm.selection, game.Debug_Selection.None)
	testing.expect_value(t, dm.dragging, game.Debug_Drag.None)

	game.debug_mode_update(&dm, &sim, {light_pressed = true}, DT)
	game.debug_mode_update(&dm, &sim, {primary_pressed = true, captured = true}, DT)
	game.debug_mode_update(&dm, &sim, {look_delta = {5.0, 0.0}, captured = true}, DT)
	game.debug_mode_update(&dm, &sim, {primary_released = true, captured = true}, DT)
	testing.expect_value(t, dm.selection, game.Debug_Selection.Light)
	testing.expect_value(t, dm.dragging, game.Debug_Drag.None)
}

@(test)
light_crate_hit_takes_selection :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	dm := game.debug_mode_create()
	dm.active = true
	eye := game.SPAWN_POSITION + b3.Vec3{0.0, game.PLAYER_EYE_HEIGHT, 0.0}
	crate := game.simulation_crate_box(&sim, 0).center
	dm.camera.position = eye
	dm.camera.yaw = 0.0
	dm.camera.pitch = math.atan2(crate.y - eye.y, eye.z - crate.z)

	game.debug_mode_update(&dm, &sim, {light_pressed = true}, DT)
	testing.expect_value(t, dm.selection, game.Debug_Selection.Light)

	game.debug_mode_update(&dm, &sim, {primary_pressed = true, captured = true}, DT)
	testing.expect_value(t, dm.selection, game.Debug_Selection.Crate)
}
