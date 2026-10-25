#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package harness_test

import "core:math"
import "core:strings"
import "core:testing"

import "src:game"
import "src:harness"

@(test)
settle_until_converged_parses_and_needs_rendering :: proc(t: ^testing.T) {
	command, error := harness.command_parse_string(`{"cmd":"settle","until":"converged"}`, context.allocator)
	testing.expectf(t, error == "", "settle parse failed: %s", error)
	defer harness.command_destroy(&command, context.allocator)
	if error != "" {
		return
	}
	testing.expect(t, command.settle.converged, "the converged form was not parsed")
}

@(test)
settle_rejects_frames_and_until_together :: proc(t: ^testing.T) {
	_, error := harness.command_parse_string(
		`{"cmd":"settle","frames":10,"until":"converged"}`,
		context.allocator,
	)
	testing.expectf(t, error != "", "settle accepted frames and until together")
	if error != "" {
		delete(error, context.allocator)
	}
}

@(test)
settle_until_converged_without_a_renderer_is_an_error :: proc(t: ^testing.T) {
	session, error := harness.session_create(context.allocator)
	testing.expectf(t, error == "", "session create failed: %s", error)
	defer harness.session_destroy(&session)
	if error != "" {
		return
	}
	reply := execute(t, &session, `{"cmd":"settle","until":"converged"}`)
	defer harness.reply_destroy(&reply, context.allocator)
	testing.expect(t, !reply.ok, "a converged settle ran without a renderer")
	testing.expect(
		t,
		strings.contains(reply.error, "rendering"),
		"the error does not name the missing renderer",
	)
}

@(test)
sun_clear_restores_the_default_light :: proc(t: ^testing.T) {
	command, error := harness.command_parse_string(`{"cmd":"sun","clear":true}`, context.allocator)
	testing.expectf(t, error == "", "sun clear parse failed: %s", error)
	defer harness.command_destroy(&command, context.allocator)
	if error != "" {
		return
	}
	testing.expect(t, command.sun.clear, "sun clear was not parsed")

	session, session_error := harness.session_create(context.allocator)
	testing.expectf(t, session_error == "", "session create failed: %s", session_error)
	defer harness.session_destroy(&session)
	if session_error != "" {
		return
	}
	reply := execute(t, &session, `{"cmd":"sun","azimuth_deg":0,"elevation_deg":5,"diameter_deg":3}`)
	harness.reply_destroy(&reply, context.allocator)
	reply = execute(t, &session, `{"cmd":"sun","clear":true}`)
	harness.reply_destroy(&reply, context.allocator)
	state := harness.session_state(&session)
	defer harness.state_destroy(&state, context.allocator)
	default_azimuth, _ := game.sun_angles_from_direction(
		game.sun_direction_from_light(game.DEFAULT_SUN_DIRECTION),
	)
	testing.expectf(
		t,
		abs(state.debug.sun.azimuth_deg - f32(math.to_degrees(default_azimuth))) < 0.001,
		"azimuth is %v",
		state.debug.sun.azimuth_deg,
	)
	testing.expectf(
		t,
		abs(state.debug.sun.angular_diameter_deg - f32(math.to_degrees(game.SUN_ANGULAR_DIAMETER))) < 0.0001,
		"diameter is %v",
		state.debug.sun.angular_diameter_deg,
	)
}

@(test)
sun_clear_rejects_another_field :: proc(t: ^testing.T) {
	_, error := harness.command_parse_string(
		`{"cmd":"sun","clear":true,"azimuth_deg":10}`,
		context.allocator,
	)
	testing.expectf(t, error != "", "sun accepted clear and azimuth together")
	if error != "" {
		delete(error, context.allocator)
	}
}
