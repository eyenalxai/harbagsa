#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package harness_test

import "core:math"
import "core:testing"

import "src:game"
import "src:harness"

@(test)
editor_sun_enters_and_aims_at_the_dome :: proc(t: ^testing.T) {
	session := editor_session(t)
	defer harness.session_destroy(&session)
	reply := execute(
		t,
		&session,
		`{"cmd": "editor", "camera": {"position": [0, 1.7, 14], "yaw_deg": 0, "pitch_deg": 28.6479}}`,
	)
	harness.reply_destroy(&reply, context.allocator)
	reply = execute(t, &session, `{"cmd": "editor", "sun": {"active": true}}`)
	testing.expectf(t, reply.ok, "sun enter failed: %s", reply.error)
	harness.reply_destroy(&reply, context.allocator)

	state := harness.session_state(&session)
	defer harness.state_destroy(&state, context.allocator)
	testing.expect(t, state.debug.sun.active, "the state did not report sun placement")
	testing.expect(
		t,
		state.debug.sun.position.y >= game.SUN_DOME_MIN_HEIGHT,
		"the harness sun fell below the horizon",
	)
	testing.expect(t, !state.debug.palette.open, "sun placement left the palette open")

	reply = execute(t, &session, `{"cmd": "check", "field": "debug.sun.active", "op": "eq", "value": true}`)
	testing.expectf(t, reply.ok, "sun active check failed: %s", reply.error)
	harness.reply_destroy(&reply, context.allocator)
}

@(test)
editor_sun_position_drives_the_angles_and_the_digest :: proc(t: ^testing.T) {
	session := editor_session(t)
	defer harness.session_destroy(&session)
	before := harness.session_state(&session)
	defer harness.state_destroy(&before, context.allocator)

	reply := execute(t, &session, `{"cmd": "editor", "sun": {"position": [0, 50, 5]}}`)
	testing.expectf(t, reply.ok, "sun position failed: %s", reply.error)
	harness.reply_destroy(&reply, context.allocator)

	after := harness.session_state(&session)
	defer harness.state_destroy(&after, context.allocator)
	expected := game.sun_dome_point({0, 50, 5})
	testing.expect_value(t, after.debug.sun.position.y, expected.y)
	testing.expect(t, abs(after.debug.sun.azimuth_deg) < 0.001, "the azimuth did not follow the position")
	testing.expect(
		t,
		abs(after.debug.sun.elevation_deg - f32(84.2894)) < 0.01,
		"the elevation did not follow the position",
	)
	testing.expect(t, after.digest != before.digest, "the sun position did not reach the digest")

	reply = execute(t, &session, `{"cmd": "check", "field": "debug.sun.elevation_deg", "op": "gt", "value": 84}`)
	testing.expectf(t, reply.ok, "sun elevation check failed: %s", reply.error)
	harness.reply_destroy(&reply, context.allocator)
}

@(test)
editor_sun_place_commits_and_cancel_restores :: proc(t: ^testing.T) {
	session := editor_session(t)
	defer harness.session_destroy(&session)
	reply := execute(t, &session, `{"cmd": "editor", "sun": {"active": true, "position": [10, 40, 20]}}`)
	harness.reply_destroy(&reply, context.allocator)

	reply = execute(t, &session, `{"cmd": "editor", "sun": {"place": true}}`)
	harness.reply_destroy(&reply, context.allocator)
	state := harness.session_state(&session)
	testing.expect(t, !state.debug.sun.active, "place kept sun placement active")
	expected := game.sun_dome_point({10, 40, 20})
	testing.expect_value(t, state.debug.sun.position.x, expected.x)
	harness.state_destroy(&state, context.allocator)

	reply = execute(t, &session, `{"cmd": "editor", "sun": {"active": true, "position": [0, 50, 0]}}`)
	harness.reply_destroy(&reply, context.allocator)
	reply = execute(t, &session, `{"cmd": "editor", "sun": {"cancel": true}}`)
	harness.reply_destroy(&reply, context.allocator)

	restored := harness.session_state(&session)
	defer harness.state_destroy(&restored, context.allocator)
	testing.expect(t, !restored.debug.sun.active, "cancel kept sun placement active")
	testing.expect_value(t, restored.debug.sun.position.x, expected.x)
	testing.expect_value(t, restored.debug.sun.position.y, expected.y)
}

@(test)
editor_sun_is_exclusive_with_the_palette_and_the_menu :: proc(t: ^testing.T) {
	session := editor_session(t)
	defer harness.session_destroy(&session)
	reply := execute(t, &session, `{"cmd": "editor", "sun": {"active": true}}`)
	harness.reply_destroy(&reply, context.allocator)

	reply = execute(t, &session, `{"cmd": "editor", "open": true}`)
	harness.reply_destroy(&reply, context.allocator)
	state := harness.session_state(&session)
	testing.expect(t, !state.debug.sun.active, "the palette did not cancel sun placement")
	testing.expect(t, state.debug.palette.open, "the palette did not open")
	harness.state_destroy(&state, context.allocator)

	reply = execute(t, &session, `{"cmd": "editor", "sun": {"active": true}}`)
	harness.reply_destroy(&reply, context.allocator)
	reply = execute(t, &session, `{"cmd": "menu", "open": true}`)
	harness.reply_destroy(&reply, context.allocator)
	state = harness.session_state(&session)
	testing.expect(t, !state.debug.sun.active, "the menu did not cancel sun placement")
	harness.state_destroy(&state, context.allocator)
	reply = execute(t, &session, `{"cmd": "menu", "open": false}`)
	harness.reply_destroy(&reply, context.allocator)
}

@(test)
editor_sun_rejects_bad_fields :: proc(t: ^testing.T) {
	lines := []string {
		`{"cmd": "editor", "sun": {}}`,
		`{"cmd": "editor", "sun": {"active": "yes"}}`,
		`{"cmd": "editor", "sun": {"position": [0, 50]}}`,
		`{"cmd": "editor", "sun": {"place": 1}}`,
		`{"cmd": "editor", "sun": {"cancel": 1}}`,
		`{"cmd": "editor", "sun": {"speed": 1}}`,
	}
	for line in lines {
		_, error := harness.command_parse_string(line, context.allocator)
		testing.expectf(t, error != "", "accepted %s", line)
		if error != "" {
			delete(error, context.allocator)
		}
	}
}

@(test)
sun_command_sets_azimuth_elevation_and_diameter :: proc(t: ^testing.T) {
	session, error := harness.session_create(context.allocator)
	testing.expectf(t, error == "", "session create failed: %s", error)
	defer harness.session_destroy(&session)
	if error != "" {
		return
	}

	reply := execute(t, &session, `{"cmd": "sun", "azimuth_deg": 0, "elevation_deg": 15, "diameter_deg": 0.53}`)
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
	testing.expectf(t, abs(state.debug.sun.elevation_deg - 15) < 1e-3, "elevation %v", state.debug.sun.elevation_deg)
	testing.expectf(t, abs(state.debug.sun.azimuth_deg) < 1e-3, "azimuth %v", state.debug.sun.azimuth_deg)
	testing.expectf(
		t,
		abs(state.debug.sun.angular_diameter_deg - 0.53) < 1e-3,
		"diameter %v",
		state.debug.sun.angular_diameter_deg,
	)
	harness.state_destroy(&state, context.allocator)

	reply = execute(t, &session, `{"cmd": "check", "field": "debug.sun.angular_diameter_deg", "op": "lt", "value": 0.54}`)
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

	reply := execute(t, &session, `{"cmd": "sun", "azimuth_deg": 90, "elevation_deg": 30}`)
	testing.expect(t, reply.ok, "the first sun command failed")
	harness.reply_destroy(&reply, context.allocator)
	reply = execute(t, &session, `{"cmd": "sun", "diameter_deg": 1.0}`)
	testing.expect(t, reply.ok, "the diameter-only sun command failed")
	harness.reply_destroy(&reply, context.allocator)

	state := harness.session_state(&session)
	testing.expectf(t, abs(state.debug.sun.azimuth_deg - 90) < 1e-3, "azimuth changed: %v", state.debug.sun.azimuth_deg)
	testing.expectf(t, abs(state.debug.sun.elevation_deg - 30) < 1e-3, "elevation changed: %v", state.debug.sun.elevation_deg)
	testing.expectf(t, abs(state.debug.sun.angular_diameter_deg - 1.0) < 1e-3, "diameter %v", state.debug.sun.angular_diameter_deg)
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

	reply := execute(t, &session, `{"cmd": "sun", "azimuth_deg": 0, "elevation_deg": 5, "diameter_deg": 3}`)
	harness.reply_destroy(&reply, context.allocator)
	reply = execute(t, &session, `{"cmd": "reset"}`)
	harness.reply_destroy(&reply, context.allocator)

	state := harness.session_state(&session)
	testing.expectf(
		t,
		abs(state.debug.sun.angular_diameter_deg - math.to_degrees(f32(game.SUN_ANGULAR_DIAMETER))) < 1e-3,
		"diameter %v",
		state.debug.sun.angular_diameter_deg,
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
		`{"cmd": "sun", "azimuth_deg": "left"}`,
		`{"cmd": "sun", "elevation_deg": 91}`,
		`{"cmd": "sun", "elevation_deg": -91}`,
		`{"cmd": "sun", "diameter_deg": 0}`,
		`{"cmd": "sun", "diameter_deg": -1}`,
		`{"cmd": "sun", "diameter_deg": 45}`,
	}
	for line in cases {
		_, parse_error := harness.command_parse_string(line, context.allocator)
		testing.expectf(t, parse_error != "", "%s must fail", line)
		if parse_error != "" {
			delete(parse_error, context.allocator)
		}
	}
}
