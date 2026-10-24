#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package harness_test

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
		`{"cmd": "editor", "camera": {"position": [0, 1.7, 14], "yaw": 0, "pitch": 0.5}}`,
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

	reply := execute(t, &session, `{"cmd": "editor", "sun": {"position": [0, 50, 0]}}`)
	testing.expectf(t, reply.ok, "sun position failed: %s", reply.error)
	harness.reply_destroy(&reply, context.allocator)

	after := harness.session_state(&session)
	defer harness.state_destroy(&after, context.allocator)
	testing.expect_value(t, after.debug.sun.position.y, 50.0)
	testing.expect(t, abs(after.debug.sun.azimuth) < 0.001, "the azimuth did not follow the position")
	testing.expect(
		t,
		abs(after.debug.sun.elevation + 90.0) < 0.001,
		"the elevation did not follow the position",
	)
	testing.expect(t, after.digest != before.digest, "the sun position did not reach the digest")

	reply = execute(t, &session, `{"cmd": "check", "field": "debug.sun.elevation", "op": "lt", "value": -89}`)
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
	testing.expect_value(t, state.debug.sun.position.x, 10.0)
	harness.state_destroy(&state, context.allocator)

	reply = execute(t, &session, `{"cmd": "editor", "sun": {"active": true, "position": [0, 50, 0]}}`)
	harness.reply_destroy(&reply, context.allocator)
	reply = execute(t, &session, `{"cmd": "editor", "sun": {"cancel": true}}`)
	harness.reply_destroy(&reply, context.allocator)

	restored := harness.session_state(&session)
	defer harness.state_destroy(&restored, context.allocator)
	testing.expect(t, !restored.debug.sun.active, "cancel kept sun placement active")
	testing.expect_value(t, restored.debug.sun.position.x, 10.0)
	testing.expect_value(t, restored.debug.sun.position.y, 40.0)
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
