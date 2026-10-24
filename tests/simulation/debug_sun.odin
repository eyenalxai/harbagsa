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
	dm.camera = {
		position = {0.0, 10.0, 0.0},
		yaw      = 0.0,
		pitch    = -0.6,
	}
	return sim, dm
}

@(private)
sun_input :: proc(dm: ^game.Debug_Mode, sim: ^game.Simulation, input: game.Debug_Input) {
	game.debug_mode_update(dm, sim, input, DT)
}

@(private)
enter_sun :: proc(dm: ^game.Debug_Mode, sim: ^game.Simulation) {
	sun_input(dm, sim, {sun_placement_pressed = true})
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
sun_dome_projection_keeps_the_radius :: proc(t: ^testing.T) {
	point := game.sun_dome_point({10.0, 20.0, -5.0})
	testing.expect(t, point.y > game.SUN_DOME_MIN_HEIGHT, "dome point sat on the horizon")
	expect_near(
		t,
		b3.Length(point - game.SUN_DOME_CENTER),
		game.SUN_DOME_RADIUS,
		0.001,
		"dome radius",
	)

	fallback := game.sun_dome_point(game.SUN_DOME_CENTER)
	testing.expect(t, fallback == game.DEFAULT_SUN_POSITION, "degenerate aim lost the sun")
}

@(test)
sun_dome_clamps_the_minimum_height :: proc(t: ^testing.T) {
	point := game.sun_dome_point({5.0, -100.0, 5.0})
	expect_near(
		t,
		point.y,
		game.SUN_DOME_CENTER.y + game.SUN_DOME_MIN_HEIGHT,
		0.0001,
		"sun height clamp",
	)
}

@(test)
sun_direction_runs_from_the_position_to_the_centre :: proc(t: ^testing.T) {
	expect_direction_near(
		t,
		game.sun_direction_from_position({0.0, 50.0, 0.0}),
		{0.0, -1.0, 0.0},
		0.0001,
	)
	expect_direction_near(
		t,
		game.sun_direction_from_position({0.0, 40.0, -30.0}),
		b3.Normalize({0.0, -40.0, 30.0}),
		0.0001,
	)
}

@(test)
sun_key_enters_the_placement_mode :: proc(t: ^testing.T) {
	sim, dm := create_sun_test(t)
	defer game.simulation_destroy(&sim)

	enter_sun(&dm, &sim)
	testing.expect(t, dm.sun.active, "L did not enter sun placement")
	testing.expect(t, !dm.palette.open, "sun placement left the palette open")
	testing.expect(t, !dm.placement.armed, "sun placement left the tool armed")
	testing.expect(t, dm.sun.position.y >= game.SUN_DOME_MIN_HEIGHT, "sun fell below the horizon")
	testing.expect(t, game.debug_mode_sun_direction(&dm).y < 0.0, "light did not point down")

	game.debug_sun_exit(&dm)
	dm.dragging = .Object
	game.debug_sun_enter(&dm, &sim)
	testing.expect_value(t, dm.dragging, game.Debug_Drag.None)
	game.debug_sun_exit(&dm)
}

@(test)
sun_lighting_follows_the_camera :: proc(t: ^testing.T) {
	sim, dm := create_sun_test(t)
	defer game.simulation_destroy(&sim)

	enter_sun(&dm, &sim)
	first := dm.sun.position
	first_direction := game.debug_mode_sun_direction(&dm)

	dm.camera.yaw = math.PI / 2.0
	sun_input(&dm, &sim, {captured = true})

	testing.expect(t, dm.sun.position != first, "the sun did not follow the camera")
	testing.expect(
		t,
		game.debug_mode_sun_direction(&dm) != first_direction,
		"the light direction did not follow the camera",
	)
}

@(test)
sun_click_commits_the_aimed_position :: proc(t: ^testing.T) {
	sim, dm := create_sun_test(t)
	defer game.simulation_destroy(&sim)

	enter_sun(&dm, &sim)
	dm.camera.yaw = 0.8
	sun_input(&dm, &sim, {primary_pressed = true, captured = true})

	expected := game.sun_dome_point(game.debug_aim_point(&dm, &sim, game.SUN_AIM_DISTANCE))
	testing.expect(t, !dm.sun.active, "the click did not leave sun placement")
	for component, index in dm.sun.position {
		expect_near(t, component, expected[index], 0.0001, "committed sun position")
	}
}

@(test)
sun_secondary_cancels_and_restores :: proc(t: ^testing.T) {
	sim, dm := create_sun_test(t)
	defer game.simulation_destroy(&sim)

	before := dm.sun.position
	enter_sun(&dm, &sim)
	dm.camera.yaw = 1.2
	sun_input(&dm, &sim, {captured = true})
	testing.expect(t, dm.sun.position != before, "aiming did not move the sun")

	sun_input(&dm, &sim, {secondary_pressed = true})
	testing.expect(t, !dm.sun.active, "right click kept sun placement active")
	testing.expect_value(t, dm.sun.position, before)
}

@(test)
sun_key_leaves_and_keeps_the_current_position :: proc(t: ^testing.T) {
	sim, dm := create_sun_test(t)
	defer game.simulation_destroy(&sim)

	enter_sun(&dm, &sim)
	dm.camera.yaw = -0.7
	sun_input(&dm, &sim, {captured = true})
	aimed := dm.sun.position

	enter_sun(&dm, &sim)
	testing.expect(t, !dm.sun.active, "L did not leave sun placement")
	testing.expect_value(t, dm.sun.position, aimed)
}

@(test)
sun_reset_restores_the_default_position :: proc(t: ^testing.T) {
	sim, dm := create_sun_test(t)
	defer game.simulation_destroy(&sim)

	enter_sun(&dm, &sim)
	game.debug_sun_set_position(&dm, {0.0, 50.0, 0.0})

	game.debug_mode_reset_scene(&dm, &sim)

	testing.expect_value(t, dm.sun.position, game.DEFAULT_SUN_POSITION)
	testing.expect(t, !dm.sun.active, "scene reset left sun placement active")
}

@(test)
sun_mode_is_exclusive_with_the_palette_and_placement :: proc(t: ^testing.T) {
	sim, dm := create_sun_test(t)
	defer game.simulation_destroy(&sim)

	enter_sun(&dm, &sim)
	game.debug_palette_open(&dm)
	testing.expect(t, !dm.sun.active, "the palette did not cancel sun placement")
	testing.expect(t, dm.palette.open, "the palette did not open")

	enter_sun(&dm, &sim)
	testing.expect(t, !dm.palette.open, "sun placement did not close the palette")
	testing.expect(t, dm.sun.active, "sun placement did not open")

	game.debug_palette_open(&dm)
	testing.expect(t, game.debug_palette_select(&dm, 4), "platform select failed")
	testing.expect(t, game.debug_palette_pick(&dm, &sim), "pick failed")
	testing.expect(t, dm.placement.armed, "pick did not arm the tool")

	enter_sun(&dm, &sim)
	testing.expect(t, !dm.placement.armed, "sun placement left the tool armed")
	testing.expect(t, dm.sun.active, "sun placement did not open")
}
