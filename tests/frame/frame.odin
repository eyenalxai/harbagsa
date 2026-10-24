#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package frame_test

import "core:strings"
import "core:testing"

import b3 "libs:box3d"
import "src:frame"
import "src:game"
import "src:perf"
import "src:renderer"
import "src:ui"

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
	testing.expect_value(t, len(scene.hud.view.rows), game.HUD_ROW_COUNT)
	testing.expect_value(t, scene.hud.view.rows[0].kind, ui.Row_Kind.Header)
	testing.expect_value(t, scene.hud.view.rows[0].label, "Standing · Walk")
}

@(test)
perf_pass_line_joins_the_hud :: proc(t: ^testing.T) {
	sim, debug, hud, scratch := create_state(t)
	defer game.simulation_destroy(&sim)
	hud.perf.visible = true
	stats := perf.Stats {
		count    = 1,
		interval = {mean = 16.6667, p95 = 17.1},
		cpu      = {mean = 0.42},
	}
	stats.gpu.available = true
	stats.gpu.passes[.Tlas] = perf.Distribution{mean = 0.08}
	stats.gpu.passes[.Depth] = perf.Distribution{mean = 0.42}
	stats.gpu.passes[.Scene] = perf.Distribution{mean = 2.70}
	stats.gpu.passes[.Taa] = perf.Distribution{mean = 0.22}
	stats.gpu.passes[.Overlay] = perf.Distribution{mean = 0.10}
	stats.gpu.total = perf.Distribution{mean = 3.52}
	stats.gpu.top = .Scene
	hud.perf.stats = stats
	scene := frame.build(
		&sim,
		&debug,
		{alpha = 1.0, captured = true, hud = true},
		nil,
		&hud,
		&scratch,
	)
	testing.expect_value(t, len(scene.hud.view.rows), game.HUD_ROW_COUNT + 2)
	perf_row := scene.hud.view.rows[game.HUD_ROW_COUNT]
	pass_row := scene.hud.view.rows[game.HUD_ROW_COUNT + 1]
	testing.expect_value(t, perf_row.label, "Perf")
	testing.expect_value(t, pass_row.label, "Passes")
	testing.expect(t, strings.contains(perf_row.value, "gpu"), "summary has no GPU total")
	testing.expect(t, strings.contains(pass_row.value, "scene"), "pass line is missing")
}

@(test)
perf_line_joins_the_hud :: proc(t: ^testing.T) {
	sim, debug, hud, scratch := create_state(t)
	defer game.simulation_destroy(&sim)
	hud.perf.visible = true
	hud.perf.stats = perf.Stats {
		count    = 1,
		interval = {mean = 16.6667, p95 = 17.1},
		cpu      = {mean = 0.42},
	}
	scene := frame.build(
		&sim,
		&debug,
		{alpha = 1.0, captured = true, hud = true},
		nil,
		&hud,
		&scratch,
	)
	testing.expect_value(t, len(scene.hud.view.rows), game.HUD_ROW_COUNT + 1)
	line := scene.hud.view.rows[game.HUD_ROW_COUNT].value
	testing.expect(t, len(line) > len("perf --"), "perf line has no numbers")
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
