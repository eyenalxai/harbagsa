#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package frame_test

import "core:testing"

import b3 "libs:box3d"
import "src:frame"
import "src:game"
import "src:renderer"

create_state :: proc(t: ^testing.T) -> (game.Simulation, game.Debug_Mode, game.HUD_State, frame.Scratch) {
	sim := game.simulation_create()
	testing.expect(t, game.simulation_is_valid(&sim), "simulation world is invalid")
	return sim, game.debug_mode_create(), {}, {}
}

@(test)
build_combines_arena_and_crates :: proc(t: ^testing.T) {
	sim, debug, hud, scratch := create_state(t)
	defer game.simulation_destroy(&sim)
	scene := frame.build(&sim, &debug, {}, nil, &hud, &scratch)
	expected := len(game.arena_static_boxes()) + game.simulation_crate_count(&sim)
	testing.expect_value(t, len(scene.boxes), expected)
	testing.expect_value(t, len(scene.debug_lines), 0)
	testing.expect(t, !scene.hud.enabled, "headless defaults must leave the HUD off")
}

@(test)
hud_can_be_enabled :: proc(t: ^testing.T) {
	sim, debug, hud, scratch := create_state(t)
	defer game.simulation_destroy(&sim)
	scene := frame.build(
		&sim,
		&debug,
		{alpha = 1.0, captured = true, hud = true},
		nil,
		&hud,
		&scratch,
	)
	testing.expect(t, scene.hud.enabled, "HUD flag was dropped")
	testing.expect_value(t, len(scene.hud.status_lines), game.HUD_STATUS_LINE_COUNT)
}

@(test)
camera_interpolates_between_snapshots :: proc(t: ^testing.T) {
	sim, debug, hud, scratch := create_state(t)
	defer game.simulation_destroy(&sim)
	game.simulation_step(&sim, game.Input_Snapshot{move_forward = 1.0}, game.SIMULATION_STEP)
	snapshot := game.simulation_snapshot(&sim)

	before := frame.build(&sim, &debug, {alpha = 0.0}, nil, &hud, &scratch)
	after := frame.build(&sim, &debug, {alpha = 1.0}, nil, &hud, &scratch)
	mid := frame.build(&sim, &debug, {alpha = 0.5}, nil, &hud, &scratch)

	expect_eye(t, before.camera.position, snapshot.previous_eye_position, "alpha 0 is not the previous eye")
	expect_eye(t, after.camera.position, snapshot.eye_position, "alpha 1 is not the current eye")
	expected := snapshot.previous_eye_position +
	            (snapshot.eye_position - snapshot.previous_eye_position) * 0.5
	expect_eye(t, mid.camera.position, expected, "alpha 0.5 is not the midpoint")
}

@(test)
camera_override_wins_over_the_player :: proc(t: ^testing.T) {
	sim, debug, hud, scratch := create_state(t)
	defer game.simulation_destroy(&sim)
	override := renderer_camera()
	scene := frame.build(&sim, &debug, {alpha = 1.0}, &override, &hud, &scratch)
	testing.expect(t, scene.camera.position == override.position, "override position was ignored")
	testing.expect(t, scene.camera.yaw == override.yaw, "override yaw was ignored")
	testing.expect(t, scene.camera.pitch == override.pitch, "override pitch was ignored")
}

@(test)
debug_view_collects_world_lines :: proc(t: ^testing.T) {
	sim, debug, hud, scratch := create_state(t)
	defer game.simulation_destroy(&sim)
	game.simulation_step(&sim, {}, game.SIMULATION_STEP)
	scene := frame.build(&sim, &debug, {alpha = 1.0, debug_view = true}, nil, &hud, &scratch)
	testing.expect(t, len(scene.debug_lines) > 0, "debug view produced no lines")
}

@(private)
expect_eye :: proc(t: ^testing.T, actual: [3]f32, expected: b3.Vec3, message: string) {
	testing.expectf(
		t,
		actual[0] == expected.x && actual[1] == expected.y && actual[2] == expected.z,
		"%s: got %v, want %v",
		message,
		actual,
		expected,
	)
}

@(private)
renderer_camera :: proc() -> renderer.Camera {
	return {
		position = {3, 4, 5},
		yaw = 0.5,
		pitch = -0.25,
		fov_x = frame.PLAYER_FOV_X,
	}
}
