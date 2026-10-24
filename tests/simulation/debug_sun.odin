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
create_sun_test :: proc(t: ^testing.T) -> (game.Simulation, game.Debug_Mode) {
	sim := create(t)
	dm := game.debug_mode_create()
	dm.active = true
	dm.camera.position = {0.0, 50.0, 0.0}
	dm.camera.pitch = 1.0
	return sim, dm
}

@(test)
sun_angle_round_trip :: proc(t: ^testing.T) {
	directions := [5][3]f32 {
		game.DEFAULT_SUN_DIRECTION,
		{1.0, -1.0, 0.0},
		{0.0, -1.0, 1.0},
		{-2.0, -3.0, 4.0},
		{0.5, -0.1, -0.5},
	}

	for direction in directions {
		azimuth, elevation := game.sun_angles_from_direction(direction)
		round_trip := game.sun_direction_from_angles(azimuth, elevation)
		expect_direction_near(t, round_trip, b3.Normalize(direction), 0.001)
	}
}

@(test)
sun_key_toggles_selection :: proc(t: ^testing.T) {
	sim, dm := create_sun_test(t)
	defer game.simulation_destroy(&sim)

	game.debug_mode_update(&dm, &sim, {sun_pressed = true}, DT)
	testing.expect_value(t, dm.selection, game.Debug_Selection.Sun)
	testing.expect_value(t, dm.selected_crate, -1)
	testing.expect_value(t, dm.dragging, game.Debug_Drag.None)

	game.debug_mode_update(&dm, &sim, {sun_pressed = true}, DT)
	testing.expect_value(t, dm.selection, game.Debug_Selection.None)
	testing.expect_value(t, dm.dragging, game.Debug_Drag.None)
}

@(test)
sun_drag_changes_angles :: proc(t: ^testing.T) {
	sim, dm := create_sun_test(t)
	defer game.simulation_destroy(&sim)

	game.debug_mode_update(&dm, &sim, {sun_pressed = true}, DT)
	azimuth := dm.sun_azimuth
	elevation := dm.sun_elevation

	game.debug_mode_update(&dm, &sim, {primary_pressed = true, captured = true}, DT)
	testing.expect_value(t, dm.dragging, game.Debug_Drag.Sun)

	game.debug_mode_update(
		&dm,
		&sim,
		{look_delta = {100.0, 50.0}, captured = true},
		DT,
	)

	testing.expect(t, dm.sun_azimuth != azimuth, "azimuth did not change")
	testing.expect(t, dm.sun_elevation != elevation, "elevation did not change")
	testing.expect(
		t,
		dm.sun_direction != game.DEFAULT_SUN_DIRECTION,
		"sun direction did not change",
	)
}

@(test)
sun_elevation_clamps :: proc(t: ^testing.T) {
	sim, dm := create_sun_test(t)
	defer game.simulation_destroy(&sim)

	game.debug_mode_update(&dm, &sim, {sun_pressed = true}, DT)
	game.debug_mode_update(&dm, &sim, {primary_pressed = true, captured = true}, DT)

	game.debug_mode_update(&dm, &sim, {look_delta = {0.0, -1000.0}, captured = true}, DT)
	testing.expect(t, dm.sun_elevation <= game.SUN_ELEVATION_MAX, "elevation rose above the upper clamp")
	testing.expect(t, dm.sun_elevation >= game.SUN_ELEVATION_MIN, "elevation fell below the lower clamp")
	expect_near(t, dm.sun_elevation, game.SUN_ELEVATION_MAX, 0.0001, "upper elevation clamp")

	game.debug_mode_update(&dm, &sim, {look_delta = {0.0, 1000.0}, captured = true}, DT)
	testing.expect(t, dm.sun_elevation <= game.SUN_ELEVATION_MAX, "elevation rose above the upper clamp")
	testing.expect(t, dm.sun_elevation >= game.SUN_ELEVATION_MIN, "elevation fell below the lower clamp")
	expect_near(t, dm.sun_elevation, game.SUN_ELEVATION_MIN, 0.0001, "lower elevation clamp")
}

@(test)
sun_click_deselects_and_drag_keeps_selection :: proc(t: ^testing.T) {
	sim, dm := create_sun_test(t)
	defer game.simulation_destroy(&sim)

	game.debug_mode_update(&dm, &sim, {sun_pressed = true}, DT)
	game.debug_mode_update(&dm, &sim, {primary_pressed = true, captured = true}, DT)
	game.debug_mode_update(&dm, &sim, {primary_released = true, captured = true}, DT)
	testing.expect_value(t, dm.selection, game.Debug_Selection.None)
	testing.expect_value(t, dm.dragging, game.Debug_Drag.None)

	game.debug_mode_update(&dm, &sim, {sun_pressed = true}, DT)
	game.debug_mode_update(&dm, &sim, {primary_pressed = true, captured = true}, DT)
	game.debug_mode_update(&dm, &sim, {look_delta = {5.0, 0.0}, captured = true}, DT)
	game.debug_mode_update(&dm, &sim, {primary_released = true, captured = true}, DT)
	testing.expect_value(t, dm.selection, game.Debug_Selection.Sun)
	testing.expect_value(t, dm.dragging, game.Debug_Drag.None)
}

@(test)
sun_crate_hit_takes_selection :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	dm := game.debug_mode_create()
	dm.active = true
	eye := game.SPAWN_POSITION + b3.Vec3{0.0, game.PLAYER_STANDING_EYE, 0.0}
	crate := game.simulation_crate_box(&sim, 0).center
	dm.camera.position = eye
	dm.camera.yaw = 0.0
	dm.camera.pitch = math.atan2(crate.y - eye.y, eye.z - crate.z)

	game.debug_mode_update(&dm, &sim, {sun_pressed = true}, DT)
	testing.expect_value(t, dm.selection, game.Debug_Selection.Sun)

	game.debug_mode_update(&dm, &sim, {primary_pressed = true, captured = true}, DT)
	testing.expect_value(t, dm.selection, game.Debug_Selection.Crate)
}

@(test)
sun_press_and_release_in_one_frame_deselects :: proc(t: ^testing.T) {
	sim, dm := create_sun_test(t)
	defer game.simulation_destroy(&sim)

	game.debug_mode_update(&dm, &sim, {sun_pressed = true}, DT)
	game.debug_mode_update(
		&dm,
		&sim,
		{primary_pressed = true, primary_released = true, captured = true},
		DT,
	)

	testing.expect_value(t, dm.selection, game.Debug_Selection.None)
	testing.expect_value(t, dm.dragging, game.Debug_Drag.None)
}

@(test)
sun_click_motion_uses_displacement :: proc(t: ^testing.T) {
	sim, dm := create_sun_test(t)
	defer game.simulation_destroy(&sim)

	game.debug_mode_update(&dm, &sim, {sun_pressed = true}, DT)
	game.debug_mode_update(&dm, &sim, {primary_pressed = true, captured = true}, DT)
	game.debug_mode_update(&dm, &sim, {look_delta = {2.0, 2.0}, captured = true}, DT)
	game.debug_mode_update(&dm, &sim, {primary_released = true, captured = true}, DT)

	testing.expect_value(t, dm.selection, game.Debug_Selection.None)
	testing.expect_value(t, dm.dragging, game.Debug_Drag.None)
}
