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
	session.renderer_report = renderer.Renderer_Report {
		active             = true,
		frame_count        = 12,
		taa_enabled        = true,
		jitter_index       = 4,
		history_valid      = true,
		convergence_frames = 12,
		history_read       = 0,
		history_weight     = 12.0 / 13.0,
		reset_count        = 2,
		last_reset         = .Teleport,
		shadow_phase       = 12,
	}
	state := harness.session_state(&session)
	defer harness.state_destroy(&state, context.allocator)
	testing.expect(t, state.renderer.active, "active renderer was dropped")
	testing.expect_value(t, state.renderer.frame_count, u32(12))
	testing.expect_value(t, state.renderer.last_reset, "teleport")
	testing.expect(t, state.renderer.taa_enabled, "TAA flag was dropped")

	command := harness.Check_Command {
		field = "renderer.convergence_frames",
		op    = .Ge,
		value = {kind = .Number, number = 8},
	}
	result := harness.check_evaluate(command, state, {}, nil, context.allocator)
	defer harness.check_result_destroy(&result, context.allocator)
	testing.expect(t, result.ok, "renderer check did not pass")

	missing := harness.Check_Command {
		field = "renderer.speed",
		op    = .Ge,
		value = {kind = .Number, number = 0},
	}
	bad := harness.check_evaluate(missing, state, {}, nil, context.allocator)
	defer harness.check_result_destroy(&bad, context.allocator)
	testing.expect(t, bad.error != "", "unknown renderer field was accepted")
}
