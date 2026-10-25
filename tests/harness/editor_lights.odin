#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package harness_test

import "core:strings"
import "core:testing"

import "src:game"
import "src:harness"

@(test)
editor_light_fields_tune_the_next_placement_and_reach_the_state :: proc(t: ^testing.T) {
	session := editor_session(t)
	defer harness.session_destroy(&session)

	reply := execute(
		t,
		&session,
		`{"cmd": "editor", "open": true, "select": 8, "camera": {"position": [0, 1.7, 14], "yaw_deg": 0, "pitch_deg": -34.3775}}`,
	)
	harness.reply_destroy(&reply, context.allocator)
	reply = execute(
		t,
		&session,
		`{"cmd": "editor", "light_color": "cool", "light_intensity": 2.4, "light_range": 12}`,
	)
	testing.expectf(t, reply.ok, "light fields failed: %s", reply.error)
	harness.reply_destroy(&reply, context.allocator)

	state := harness.session_state(&session)
	testing.expect(t, state.debug.placement.light.active, "the placement light is inactive")
	testing.expect_value(t, state.debug.placement.light.color, "cool")
	testing.expect_value(t, state.debug.placement.light.intensity, 2.4)
	testing.expect_value(t, state.debug.placement.light.range, 12.0)
	harness.state_destroy(&state, context.allocator)

	reply = execute(t, &session, `{"cmd": "editor", "pick": true}`)
	harness.reply_destroy(&reply, context.allocator)
	reply = execute(
		t,
		&session,
		`{"cmd": "editor", "place": {"prefab": "Lamp", "position": [2, 1, 8], "body": "static"}}`,
	)
	testing.expectf(t, reply.ok, "lamp place failed: %s", reply.error)
	harness.reply_destroy(&reply, context.allocator)

	state = harness.session_state(&session)
	defer harness.state_destroy(&state, context.allocator)
	testing.expect_value(t, len(state.objects), game.INITIAL_CRATE_COUNT + 1)
	lamp := state.objects[game.INITIAL_CRATE_COUNT]
	testing.expect_value(t, lamp.prefab, "Lamp")
	testing.expect(t, lamp.light.active, "the placed lamp has no light")
	testing.expect_value(t, lamp.light.color, "cool")
	testing.expect_value(t, lamp.light.intensity, 2.4)
	testing.expect_value(t, lamp.light.range, 12.0)
	testing.expect_value(t, state.debug.lights.active, 1)
	testing.expect_value(t, state.debug.lights.lamps, 1)

	checks := []struct {
		path:  string,
		value: string,
	} {
		{"objects.4.light.color", `"cool"`},
		{"objects.4.light.intensity", `2.4`},
		{"objects.4.light.range", `12`},
		{"debug.placement.light.color", `"cool"`},
		{"debug.lights.active", `1`},
		{"debug.lights.lamps", `1`},
	}
	for check in checks {
		line := strings.concatenate(
			{`{"cmd": "check", "field": "`, check.path, `", "op": "eq", "value": `, check.value, `}`},
			context.temp_allocator,
		)
		reply = execute(t, &session, line)
		testing.expectf(t, reply.ok, "check %s failed: %s", check.path, reply.error)
		harness.reply_destroy(&reply, context.allocator)
	}
}

@(test)
editor_light_fields_edit_the_selected_lamp_and_undo :: proc(t: ^testing.T) {
	session := editor_session(t)
	defer harness.session_destroy(&session)

	reply := execute(
		t,
		&session,
		`{"cmd": "editor", "place": {"prefab": "Beacon", "position": [1, 0.2, 7], "body": "static"}}`,
	)
	testing.expectf(t, reply.ok, "beacon place failed: %s", reply.error)
	harness.reply_destroy(&reply, context.allocator)

	reply = execute(
		t,
		&session,
		`{"cmd": "editor", "select_object": 4, "light_color": "green", "light_intensity": 3.4}`,
	)
	testing.expectf(t, reply.ok, "lamp edit failed: %s", reply.error)
	harness.reply_destroy(&reply, context.allocator)

	state := harness.session_state(&session)
	testing.expect_value(t, state.debug.inspector.light.color, "green")
	testing.expect_value(t, state.debug.inspector.light.intensity, 3.4)
	testing.expect_value(t, state.debug.lights.active, 1)
	testing.expect_value(t, state.debug.history.depth, 3)
	harness.state_destroy(&state, context.allocator)

	reply = execute(t, &session, `{"cmd": "editor", "undo": true}`)
	harness.reply_destroy(&reply, context.allocator)
	state = harness.session_state(&session)
	testing.expect_value(t, state.debug.inspector.light.color, "green")
	testing.expect_value(t, state.debug.inspector.light.intensity, 2.0)
	harness.state_destroy(&state, context.allocator)

	reply = execute(t, &session, `{"cmd": "editor", "undo": true}`)
	harness.reply_destroy(&reply, context.allocator)
	state = harness.session_state(&session)
	testing.expect_value(t, state.debug.inspector.light.color, "red")
	harness.state_destroy(&state, context.allocator)
}

@(test)
editor_light_fields_reject_a_non_lamp_target :: proc(t: ^testing.T) {
	session := editor_session(t)
	defer harness.session_destroy(&session)

	reply := execute(t, &session, `{"cmd": "editor", "select_object": 1}`)
	harness.reply_destroy(&reply, context.allocator)
	reply = execute(t, &session, `{"cmd": "editor", "light_color": "blue"}`)
	testing.expect(t, !reply.ok, "a crate accepted a light colour")
	testing.expect(t, strings.contains(reply.error, "lamp"), "the error does not name the lamp")
	harness.reply_destroy(&reply, context.allocator)

	reply = execute(t, &session, `{"cmd": "editor", "open": true, "select": 3}`)
	harness.reply_destroy(&reply, context.allocator)
	reply = execute(t, &session, `{"cmd": "editor", "light_range": 9}`)
	testing.expect(t, !reply.ok, "a block placement accepted a light range")
	harness.reply_destroy(&reply, context.allocator)
}

@(test)
editor_light_fields_reject_bad_values :: proc(t: ^testing.T) {
	lines := []string {
		`{"cmd": "editor", "light_color": "pink"}`,
		`{"cmd": "editor", "light_color": 1}`,
		`{"cmd": "editor", "light_intensity": 0.1}`,
		`{"cmd": "editor", "light_intensity": 4.1}`,
		`{"cmd": "editor", "light_intensity": "bright"}`,
		`{"cmd": "editor", "light_range": 1}`,
		`{"cmd": "editor", "light_range": 21}`,
		`{"cmd": "editor", "light_range": "far"}`,
	}
	for line in lines {
		command, error := harness.command_parse_string(line, context.allocator)
		if error == "" {
			harness.command_destroy(&command, context.allocator)
		}
		testing.expectf(t, error != "", "accepted %s", line)
		if error != "" {
			delete(error, context.allocator)
		}
	}
}
