#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package harness_test

import "core:testing"

import "src:harness"
import "src:renderer"

@(test)
renderer_state_is_reported_without_a_backend :: proc(t: ^testing.T) {
	session, error := harness.session_create(context.allocator)
	testing.expectf(t, error == "", "session create failed: %s", error)
	defer harness.session_destroy(&session)

	state := harness.session_state(&session)
	defer harness.state_destroy(&state, context.allocator)
	testing.expect(t, !state.renderer.active, "inactive renderer reported as active")
	testing.expect_value(t, state.renderer.last_reset, "none")
	testing.expect_value(t, state.render_digest, "")
}

@(test)
renderer_state_reaches_the_state_and_checks :: proc(t: ^testing.T) {
	session, _ := harness.session_create(context.allocator)
	defer harness.session_destroy(&session)
	session.render.report = renderer.Renderer_Report {
		active             = true,
		frame_count        = 12,
		taa_enabled        = true,
		jitter_index       = 4,
		history_valid      = true,
		convergence_frames = 12,
		history_read       = 0,
		history_weight     = 12.0 / 13.0,
		reset_count        = 2,
		last_reset         = "teleport",
		shadow_phase       = 12,
		light_count        = 3,
		debug              = {light_shadows = true},
		atlas_weight       = 900,
		debug_vertex_count = 92,
		debug_vertices = {world = 92},
	}
	state := harness.session_state(&session)
	defer harness.state_destroy(&state, context.allocator)
	testing.expect(t, state.renderer.active, "active renderer was dropped")
	testing.expect_value(t, state.renderer.frame_count, u32(12))
	testing.expect_value(t, state.renderer.last_reset, "teleport")
	testing.expect(t, state.renderer.taa_enabled, "TAA flag was dropped")
	testing.expect_value(t, state.renderer.light_count, 3)
	testing.expect(t, state.renderer.debug.light_shadows, "light shadow default was dropped")
	testing.expect_value(t, state.renderer.atlas_weight, f32(900))
	testing.expect_value(t, state.renderer.debug_vertex_count, 92)
	testing.expect_value(t, state.renderer.debug_vertices.world, 92)

	command := harness.Check_Command {
		field = "renderer.atlas_weight",
		op    = .Eq,
		value = {kind = .Number, number = 900},
	}
	weight_result := harness.check_evaluate(command, state, {}, nil, context.allocator)
	defer harness.check_result_destroy(&weight_result, context.allocator)
	testing.expect(t, weight_result.ok, "applied atlas weight check did not pass")

	world_count := harness.Check_Command {
		field = "renderer.debug_vertices.world",
		op    = .Eq,
		value = {kind = .Number, number = 92},
	}
	world_result := harness.check_evaluate(world_count, state, {}, nil, context.allocator)
	defer harness.check_result_destroy(&world_result, context.allocator)
	testing.expectf(t, world_result.ok, "world vertex count check failed: %s", world_result.error)

	command = harness.Check_Command {
		field = "renderer.convergence_frames",
		op    = .Ge,
		value = {kind = .Number, number = 8},
	}
	convergence_result := harness.check_evaluate(command, state, {}, nil, context.allocator)
	defer harness.check_result_destroy(&convergence_result, context.allocator)
	testing.expect(t, convergence_result.ok, "renderer check did not pass")

	light_command := harness.Check_Command {
		field = "renderer.light_count",
		op    = .Eq,
		value = {kind = .Number, number = 3},
	}
	light_result := harness.check_evaluate(light_command, state, {}, nil, context.allocator)
	defer harness.check_result_destroy(&light_result, context.allocator)
	testing.expect(t, light_result.ok, "light count check did not pass")

	missing := harness.Check_Command {
		field = "renderer.speed",
		op    = .Ge,
		value = {kind = .Number, number = 0},
	}
	bad := harness.check_evaluate(missing, state, {}, nil, context.allocator)
	defer harness.check_result_destroy(&bad, context.allocator)
	testing.expect(t, bad.error != "", "unknown renderer field was accepted")
}
