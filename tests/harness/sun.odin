#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package harness_test

import "core:math"
import "core:testing"

import "src:game"
import "src:harness"

@(test)
sun_command_sets_azimuth_elevation_and_diameter :: proc(t: ^testing.T) {
	session, error := harness.session_create(context.allocator)
	testing.expectf(t, error == "", "session create failed: %s", error)
	defer harness.session_destroy(&session)
	if error != "" {
		return
	}

	reply := execute(t, &session, `{"cmd": "sun", "azimuth": 0, "elevation": 15, "diameter": 0.53}`)
	testing.expect(t, reply.ok, "the sun command failed")
	harness.reply_destroy(&reply, context.allocator)

	direction := game.debug_mode_sun_direction(&session.debug)
	expected := [3]f32{
		0,
		-f32(math.sin(15.0 * math.PI / 180.0)),
		-f32(math.cos(15.0 * math.PI / 180.0)),
	}
	for axis in 0 ..< 3 {
		testing.expectf(
			t,
			abs(direction[axis] - expected[axis]) < 1e-5,
			"axis %d: got %v, want %v",
			axis,
			direction[axis],
			expected[axis],
		)
	}

	state := harness.session_state(&session)
	testing.expectf(t, abs(state.sun.elevation - 15) < 1e-3, "elevation %v", state.sun.elevation)
	testing.expectf(t, abs(state.sun.azimuth) < 1e-3, "azimuth %v", state.sun.azimuth)
	testing.expectf(
		t,
		abs(state.sun.angular_diameter - 0.53) < 1e-3,
		"diameter %v",
		state.sun.angular_diameter,
	)
	harness.state_destroy(&state, context.allocator)

	reply = execute(t, &session, `{"cmd": "check", "field": "sun.angular_diameter", "op": "lt", "value": 0.54}`)
	testing.expect(t, reply.ok, "sun.angular_diameter was not checkable")
	harness.reply_destroy(&reply, context.allocator)
}

@(test)
sun_command_keeps_omitted_fields :: proc(t: ^testing.T) {
	session, error := harness.session_create(context.allocator)
	testing.expectf(t, error == "", "session create failed: %s", error)
	defer harness.session_destroy(&session)
	if error != "" {
		return
	}

	reply := execute(t, &session, `{"cmd": "sun", "azimuth": 90, "elevation": 30}`)
	testing.expect(t, reply.ok, "the first sun command failed")
	harness.reply_destroy(&reply, context.allocator)
	reply = execute(t, &session, `{"cmd": "sun", "diameter": 1.0}`)
	testing.expect(t, reply.ok, "the diameter-only sun command failed")
	harness.reply_destroy(&reply, context.allocator)

	state := harness.session_state(&session)
	testing.expectf(t, abs(state.sun.azimuth - 90) < 1e-3, "azimuth changed: %v", state.sun.azimuth)
	testing.expectf(t, abs(state.sun.elevation - 30) < 1e-3, "elevation changed: %v", state.sun.elevation)
	testing.expectf(t, abs(state.sun.angular_diameter - 1.0) < 1e-3, "diameter %v", state.sun.angular_diameter)
	harness.state_destroy(&state, context.allocator)
}

@(test)
sun_command_reset_restores_the_default_sun :: proc(t: ^testing.T) {
	session, error := harness.session_create(context.allocator)
	testing.expectf(t, error == "", "session create failed: %s", error)
	defer harness.session_destroy(&session)
	if error != "" {
		return
	}

	reply := execute(t, &session, `{"cmd": "sun", "azimuth": 0, "elevation": 5, "diameter": 3}`)
	harness.reply_destroy(&reply, context.allocator)
	reply = execute(t, &session, `{"cmd": "reset"}`)
	harness.reply_destroy(&reply, context.allocator)

	state := harness.session_state(&session)
	testing.expectf(
		t,
		abs(state.sun.angular_diameter - math.to_degrees(f32(game.SUN_ANGULAR_DIAMETER))) < 1e-3,
		"diameter %v",
		state.sun.angular_diameter,
	)
	harness.state_destroy(&state, context.allocator)

	direction := game.debug_mode_sun_direction(&session.debug)
	default_direction := game.DEFAULT_SUN_DIRECTION
	default_length := f32(
		math.sqrt(
			default_direction.x * default_direction.x +
			default_direction.y * default_direction.y +
			default_direction.z * default_direction.z,
		),
	)
	for axis in 0 ..< 3 {
		expected := default_direction[axis] / default_length
		testing.expectf(
			t,
			abs(direction[axis] - expected) < 1e-6,
			"axis %d: got %v, want %v",
			axis,
			direction[axis],
			expected,
		)
	}
}

@(test)
sun_command_rejects_bad_input :: proc(t: ^testing.T) {
	cases := []string {
		`{"cmd": "sun"}`,
		`{"cmd": "sun", "height": 10}`,
		`{"cmd": "sun", "azimuth": "left"}`,
		`{"cmd": "sun", "elevation": 91}`,
		`{"cmd": "sun", "elevation": -91}`,
		`{"cmd": "sun", "diameter": 0}`,
		`{"cmd": "sun", "diameter": -1}`,
		`{"cmd": "sun", "diameter": 45}`,
	}
	for line in cases {
		_, parse_error := harness.command_parse_string(line, context.allocator)
		testing.expectf(t, parse_error != "", "%s must fail", line)
	}
}
