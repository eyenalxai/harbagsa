#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package simulation

import "core:testing"

import b3 "libs:box3d"
import game "src:game"
import "src:geometry"

@(private)
step_world :: proc(sim: ^game.Simulation, count: int) {
	for _ in 0 ..< count {
		game.simulation_step_world(sim, DT)
	}
}

@(private)
lowest_corner_y :: proc(box: geometry.Box) -> f32 {
	corners := game.oriented_box_corners(
		box.center,
		box.half_extents,
		transmute(b3.Quat)box.rotation,
	)
	lowest := corners[0].y
	for corner in corners {
		lowest = min(lowest, corner.y)
	}
	return lowest
}

@(test)
spawn_pop_curve_has_the_floor_overshoot_and_duration :: proc(t: ^testing.T) {
	expect_near(t, game.SPAWN_POP_DURATION, 0.28, 0.0001, "duration")
	expect_near(t, game.SPAWN_POP_MIN_SCALE, 0.01, 0.0001, "floor constant")
	testing.expect_value(t, game.spawn_pop_scale(0.0), game.SPAWN_POP_MIN_SCALE)
	testing.expect_value(t, game.spawn_pop_scale(-1.0), game.SPAWN_POP_MIN_SCALE)

	peak_age := f32(0.6) * game.SPAWN_POP_DURATION
	expect_near(t, game.spawn_pop_scale(peak_age), 1.08, 0.001, "peak overshoot")
	testing.expect(
		t,
		game.spawn_pop_scale(0.5 * game.SPAWN_POP_DURATION) < 1.08,
		"the curve passed the peak before the peak age",
	)

	testing.expect_value(t, game.spawn_pop_scale(game.SPAWN_POP_DURATION), 1.0)
	testing.expect_value(t, game.spawn_pop_scale(10.0 * game.SPAWN_POP_DURATION), 1.0)

	for step in 0 ..= 280 {
		age := f32(step) * 0.001
		scale := game.spawn_pop_scale(age)
		testing.expectf(
			t,
			scale >= game.SPAWN_POP_MIN_SCALE && scale <= 1.081,
			"scale %v at age %v is outside the curve",
			scale,
			age,
		)
	}
}

@(test)
simulation_time_advances_once_per_world_step :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)
	testing.expect_value(t, sim.time, 0.0)

	step(&sim, {}, 3)
	expect_near(t, sim.time, 3.0 * DT, 0.0001, "player step time")

	step_world(&sim, 2)
	expect_near(t, sim.time, 5.0 * DT, 0.0001, "world step time")

	step(&sim, game.Input_Snapshot{reset_pressed = true}, 1)
	expect_near(t, sim.time, 5.0 * DT, 0.0001, "reset step time")

	game.simulation_step(&sim, {}, 0.0)
	expect_near(t, sim.time, 5.0 * DT, 0.0001, "skipped step time")
}

@(test)
new_objects_pop_while_initial_crates_stay_settled :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	for object in game.simulation_objects(&sim) {
		testing.expect_value(t, game.simulation_object_scale(&sim, object.id), 1.0)
		testing.expect_value(t, game.simulation_object_spawn_age(&sim, object.id), 0.0)
	}

	id := game.simulation_create_object(
		&sim,
		{prefab = .Block, body_mode = .Static, center = {20, 0.5, 20}, yaw_rad = 0},
	)
	testing.expect(t, id != game.INVALID_OBJECT_ID, "block did not create")
	expect_near(t, game.simulation_object_scale(&sim, id), 0.01, 0.0001, "start scale")
	expect_near(t, game.simulation_object_spawn_age(&sim, id), 0.0, 0.0001, "start age")

	step_world(&sim, 10)
	scale := game.simulation_object_scale(&sim, id)
	testing.expectf(t, scale > 1.05 && scale < 1.09, "peak scale is %v", scale)
	expect_near(t, game.simulation_object_spawn_age(&sim, id), 10.0 * DT, 0.0001, "peak age")

	step_world(&sim, 7)
	testing.expect_value(t, game.simulation_object_scale(&sim, id), 1.0)
	expect_near(t, game.simulation_object_spawn_age(&sim, id), 17.0 * DT, 0.0001, "settled age")

	for object in game.simulation_objects(&sim)[:game.INITIAL_CRATE_COUNT] {
		testing.expect_value(t, game.simulation_object_scale(&sim, object.id), 1.0)
		testing.expect_value(t, game.simulation_object_spawn_age(&sim, object.id), 0.0)
	}
}

@(test)
restored_objects_do_not_pop :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)
	step_world(&sim, 30)

	id := game.simulation_restore_object(
		&sim,
		{prefab = .Wall, body_mode = .Static, center = {20, 1.5, 20}, yaw_rad = 0.4},
	)
	testing.expect(t, id != game.INVALID_OBJECT_ID, "wall did not restore")
	testing.expect_value(t, game.simulation_object_scale(&sim, id), 1.0)
	testing.expect_value(t, game.simulation_object_spawn_age(&sim, id), 0.0)

	step_world(&sim, 5)
	testing.expect_value(t, game.simulation_object_scale(&sim, id), 1.0)
	testing.expect_value(t, game.simulation_object_spawn_age(&sim, id), 0.0)

	game.simulation_reset_objects(&sim)
	for object in game.simulation_objects(&sim) {
		testing.expect_value(t, game.simulation_object_scale(&sim, object.id), 1.0)
		testing.expect_value(t, game.simulation_object_spawn_age(&sim, object.id), 0.0)
	}
}

@(test)
spawn_pop_keeps_the_aabb_bottom_fixed :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	id := game.simulation_create_object(
		&sim,
		{prefab = .Ramp, body_mode = .Static, center = {20, 5, 20}, yaw_rad = 0.3},
	)
	base := game.simulation_object_box(&sim, id)
	anchor := lowest_corner_y(base)

	for frame in 0 ..= 20 {
		if frame > 0 {
			step_world(&sim, 1)
		}
		visual := game.simulation_object_visual_box(&sim, id)
		expect_near(
			t,
			lowest_corner_y(visual),
			anchor,
			0.0001,
			"aabb bottom",
		)
	}
}

@(test)
pop_scales_the_visual_box_only :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	id := game.simulation_create_object(
		&sim,
		{prefab = .Block, body_mode = .Static, center = {20, 1.5, 20}, yaw_rad = 0},
	)
	full := game.simulation_object_box(&sim, id)
	visual := game.simulation_object_visual_box(&sim, id)

	testing.expect_value(t, full.half_extents, game.prefab(.Block).half_extents)
	testing.expect_value(t, full.center, b3.Vec3{20, 1.5, 20})
	expect_near(
		t,
		visual.half_extents.y,
		full.half_extents.y * game.SPAWN_POP_MIN_SCALE,
		0.0001,
		"visual half height",
	)
	expect_near(
		t,
		visual.center.y,
		full.center.y - (1.0 - game.SPAWN_POP_MIN_SCALE) * full.half_extents.y,
		0.0001,
		"visual center",
	)
}

@(test)
the_ghost_box_is_not_scaled :: proc(t: ^testing.T) {
	sim, dm := placement_setup(t)
	defer game.simulation_destroy(&sim)
	placement_arm(t, &dm, &sim, .Block)

	box, ok := game.debug_ghost_box(&dm)
	testing.expect(t, ok, "the armed ghost has no box")
	testing.expect_value(t, box.half_extents, game.prefab(.Block).half_extents)
}

@(test)
spawn_pop_is_deterministic :: proc(t: ^testing.T) {
	first := create(t)
	defer game.simulation_destroy(&first)
	second := create(t)
	defer game.simulation_destroy(&second)

	spawn := game.Object_Spawn {
		prefab    = .Ramp,
		body_mode = .Static,
		center    = {20, 5, 20},
		yaw_rad   = 0.3,
	}
	first_id := game.simulation_create_object(&first, spawn)
	second_id := game.simulation_create_object(&second, spawn)

	for frame in 0 ..= 18 {
		if frame > 0 {
			step_world(&first, 1)
			step_world(&second, 1)
		}
		testing.expect_value(
			t,
			game.simulation_object_scale(&first, first_id),
			game.simulation_object_scale(&second, second_id),
		)
		first_box := game.simulation_object_visual_box(&first, first_id)
		second_box := game.simulation_object_visual_box(&second, second_id)
		testing.expect_value(t, first_box.center, second_box.center)
		testing.expect_value(t, first_box.half_extents, second_box.half_extents)
	}
}
