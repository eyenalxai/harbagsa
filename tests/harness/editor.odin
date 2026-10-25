#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package harness_test

import "core:os"
import "core:strings"
import "core:testing"

import "src:game"
import "src:harness"

EDITOR_RECORD_PATH :: "/tmp/opencode/harbagsa-editor-record-test.json"

@(private)
editor_session :: proc(t: ^testing.T) -> harness.Session {
	session, error := harness.session_create(context.allocator)
	testing.expectf(t, error == "", "session create failed: %s", error)
	if error != "" {
		return session
	}
	reply := execute(t, &session, `{"cmd": "debug_mode", "active": true}`)
	harness.reply_destroy(&reply, context.allocator)
	return session
}

@(test)
editor_camera_aims_at_a_point :: proc(t: ^testing.T) {
	command, error := harness.command_parse_string(
		`{"cmd":"editor","camera":{"position":[0,1.7,14],"look_at":[0,1.7,4]}}`,
		context.allocator,
	)
	defer harness.command_destroy(&command, context.allocator)
	testing.expectf(t, error == "", "editor look_at parse failed: %s", error)
	if error != "" {
		return
	}
	testing.expect(t, abs(command.editor.camera.yaw_rad) < 1e-5, "looking down -z has a nonzero yaw")
	testing.expect(t, abs(command.editor.camera.pitch_rad) < 1e-5, "looking level has a nonzero pitch")

	bad := []string{
		`{"cmd":"editor","camera":{"position":[0,0,0],"look_at":[0,0,-1],"yaw_deg":0,"pitch_deg":0}}`,
		`{"cmd":"editor","camera":{"position":[0,0,0],"look_at":[0,0,0]}}`,
	}
	for line in bad {
		_, bad_error := harness.command_parse_string(line, context.allocator)
		testing.expectf(t, bad_error != "", "bad editor camera was accepted: %s", line)
		if bad_error != "" {
			delete(bad_error, context.allocator)
		}
	}
}

@(test)
editor_primary_places_the_ghost_at_the_aim :: proc(t: ^testing.T) {
	session := editor_session(t)
	defer harness.session_destroy(&session)

	reply := execute(
		t,
		&session,
		`{"cmd":"editor","camera":{"position":[0,1.7,14],"look_at":[0,1.0,0]}}`,
	)
	harness.reply_destroy(&reply, context.allocator)
	reply = execute(t, &session, `{"cmd":"editor","select":3,"pick":true}`)
	harness.reply_destroy(&reply, context.allocator)
	reply = execute(t, &session, `{"cmd":"step","frames":1}`)
	harness.reply_destroy(&reply, context.allocator)

	aimed := harness.session_state(&session)
	ghost := aimed.debug.placement.position
	harness.state_destroy(&aimed, context.allocator)

	reply = execute(t, &session, `{"cmd":"editor","primary":true}`)
	harness.reply_destroy(&reply, context.allocator)
	placed := harness.session_state(&session)
	defer harness.state_destroy(&placed, context.allocator)
	testing.expect(t, placed.debug.selected_id != 0, "primary selected nothing")
	if placed.debug.selected_id == 0 || len(placed.objects) == 0 {
		return
	}
	object := placed.objects[len(placed.objects) - 1]
	testing.expect_value(t, object.prefab, "Block")
	testing.expectf(
		t,
		abs(object.position.x - ghost.x) < 1e-3 &&
		abs(object.position.y - ghost.y) < 1e-3 &&
		abs(object.position.z - ghost.z) < 1e-3,
		"the click placed %v, not the ghost %v",
		object.position,
		ghost,
	)
}

@(test)
editor_opens_selects_and_picks_a_prefab :: proc(t: ^testing.T) {
	session := editor_session(t)
	defer harness.session_destroy(&session)

	reply := execute(
		t,
		&session,
		`{"cmd": "editor", "camera": {"position": [0, 1.7, 14], "yaw_deg": 0, "pitch_deg": -51.5662}}`,
	)
	harness.reply_destroy(&reply, context.allocator)
	reply = execute(t, &session, `{"cmd": "editor", "open": true, "select": 4}`)
	harness.reply_destroy(&reply, context.allocator)
	reply = execute(t, &session, `{"cmd": "editor", "pick": true}`)
	harness.reply_destroy(&reply, context.allocator)

	state := harness.session_state(&session)
	defer harness.state_destroy(&state, context.allocator)
	testing.expect(t, !state.debug.palette.open, "pick left the palette open")
	testing.expect(t, state.debug.placement.armed, "pick did not arm the placement")
	testing.expect_value(t, state.debug.placement.prefab, "Platform")
	testing.expect_value(t, state.debug.palette.body, "static")
	testing.expect(t, state.debug.placement.position.y > 0, "ghost has no height")
}

@(test)
editor_height_yaw_and_snap_reach_the_state_and_checks :: proc(t: ^testing.T) {
	session := editor_session(t)
	defer harness.session_destroy(&session)
	_ = execute(t, &session, `{"cmd": "editor", "open": true, "select": 4, "pick": true}`)

	reply := execute(t, &session, `{"cmd": "editor", "height": 0.5, "yaw_deg": 45, "snap": true}`)
	harness.reply_destroy(&reply, context.allocator)

	state := harness.session_state(&session)
	defer harness.state_destroy(&state, context.allocator)
	testing.expect_value(t, state.debug.placement.height, 0.5)
	testing.expect_value(t, state.debug.placement.yaw_deg, 45.0)
	testing.expect(t, state.debug.placement.snap, "snap was dropped")

	reply = execute(t, &session, `{"cmd": "check", "field": "debug.placement.height", "op": "eq", "value": 0.5}`)
	testing.expectf(t, reply.ok, "height check failed: %s", reply.error)
	harness.reply_destroy(&reply, context.allocator)
	reply = execute(t, &session, `{"cmd": "check", "field": "debug.placement.yaw_deg", "op": "eq", "value": 45}`)
	testing.expectf(t, reply.ok, "yaw check failed: %s", reply.error)
	harness.reply_destroy(&reply, context.allocator)
	reply = execute(t, &session, `{"cmd": "check", "field": "debug.palette.body", "op": "eq", "value": "static"}`)
	testing.expectf(t, reply.ok, "body check failed: %s", reply.error)
	harness.reply_destroy(&reply, context.allocator)
	reply = execute(t, &session, `{"cmd": "check", "field": "debug.placement.snap", "op": "eq", "value": true}`)
	testing.expectf(t, reply.ok, "snap check failed: %s", reply.error)
	harness.reply_destroy(&reply, context.allocator)
}

@(test)
editor_place_creates_the_exact_transform :: proc(t: ^testing.T) {
	session := editor_session(t)
	defer harness.session_destroy(&session)

	reply := execute(
		t,
		&session,
		`{"cmd": "editor", "place": {"prefab": "Block", "position": [0, 2, 5], "yaw_deg": 30, "body": "static"}}`,
	)
	testing.expectf(t, reply.ok, "place failed: %s", reply.error)
	harness.reply_destroy(&reply, context.allocator)

	state := harness.session_state(&session)
	defer harness.state_destroy(&state, context.allocator)
	testing.expect_value(t, len(state.objects), game.INITIAL_CRATE_COUNT + 1)
	object := state.objects[game.INITIAL_CRATE_COUNT]
	testing.expect_value(t, object.prefab, "Block")
	testing.expect_value(t, object.body, "static")
	testing.expect_value(t, object.position.x, 0.0)
	testing.expect_value(t, object.position.y, 2.0)
	testing.expect_value(t, object.position.z, 5.0)
	testing.expect(t, object.rotation.w < 1.0, "place yaw did not rotate the object")
	testing.expect_value(t, state.debug.selection, "object")
	testing.expect_value(t, state.debug.selected_id, u32(game.INITIAL_CRATE_COUNT + 1))
}

@(test)
editor_cancel_clears_the_armed_tool :: proc(t: ^testing.T) {
	session := editor_session(t)
	defer harness.session_destroy(&session)
	_ = execute(t, &session, `{"cmd": "editor", "open": true, "select": 4, "pick": true}`)

	reply := execute(t, &session, `{"cmd": "editor", "cancel": true}`)
	harness.reply_destroy(&reply, context.allocator)

	state := harness.session_state(&session)
	defer harness.state_destroy(&state, context.allocator)
	testing.expect(t, !state.debug.placement.armed, "cancel kept the tool armed")
	testing.expect_value(t, len(state.objects), game.INITIAL_CRATE_COUNT)
}

@(test)
editor_needs_debug_mode :: proc(t: ^testing.T) {
	session, error := harness.session_create(context.allocator)
	testing.expectf(t, error == "", "session create failed: %s", error)
	defer harness.session_destroy(&session)

	reply := execute(t, &session, `{"cmd": "editor", "open": true}`)
	defer harness.reply_destroy(&reply, context.allocator)
	testing.expect(t, !reply.ok, "editor ran without debug mode")
	testing.expect(t, strings.contains(reply.error, "debug mode"), "missing debug mode error")
}

@(test)
debug_step_steps_the_world_not_the_player :: proc(t: ^testing.T) {
	session := editor_session(t)
	defer harness.session_destroy(&session)
	_ = execute(t, &session, `{"cmd": "input", "forward": 1}`)

	reply := execute(t, &session, `{"cmd": "step", "frames": 60}`)
	harness.reply_destroy(&reply, context.allocator)
	testing.expect_value(t, session.frame, 60)
	testing.expect(
		t,
		session.sim.player.position == game.SPAWN_POSITION,
		"the player moved while debug mode was active",
	)
}

@(test)
editor_rejects_bad_fields :: proc(t: ^testing.T) {
	lines := []string {
		`{"cmd": "editor"}`,
		`{"cmd": "editor", "select": 11}`,
		`{"cmd": "editor", "body": "heavy"}`,
		`{"cmd": "editor", "height": -1}`,
		`{"cmd": "editor", "camera": {"position": [0, 0, 0]}}`,
		`{"cmd": "editor", "place": {"position": [0, 0, 0]}}`,
		`{"cmd": "editor", "place": {"prefab": "Block"}}`,
		`{"cmd": "editor", "speed": 1}`,
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

@(test)
editor_commands_record_and_replay :: proc(t: ^testing.T) {
	_ = os.remove(EDITOR_RECORD_PATH)
	session := editor_session(t)
	defer harness.session_destroy(&session)

	record_line := strings.concatenate(
		{`{"cmd": "record", "path": "`, EDITOR_RECORD_PATH, `"}`},
		context.temp_allocator,
	)
	reply := execute(t, &session, record_line)
	harness.reply_destroy(&reply, context.allocator)
	reply = execute(
		t,
		&session,
		`{"cmd": "editor", "camera": {"position": [0, 1.7, 14], "yaw_deg": 0, "pitch_deg": -51.5662}}`,
	)
	harness.reply_destroy(&reply, context.allocator)
	reply = execute(t, &session, `{"cmd": "editor", "open": true, "select": 3, "pick": true, "height": 0.5}`)
	harness.reply_destroy(&reply, context.allocator)
	reply = execute(
		t,
		&session,
		`{"cmd": "editor", "place": {"prefab": "Block", "position": [0, 2, 5], "yaw_deg": 30}}`,
	)
	harness.reply_destroy(&reply, context.allocator)

	before := harness.session_state(&session)
	defer harness.state_destroy(&before, context.allocator)
	reply = execute(t, &session, `{"cmd": "record"}`)
	harness.reply_destroy(&reply, context.allocator)

	replay_line := strings.concatenate(
		{`{"cmd": "replay", "path": "`, EDITOR_RECORD_PATH, `"}`},
		context.temp_allocator,
	)
	reply = execute(t, &session, replay_line)
	testing.expectf(t, reply.ok, "replay failed: %s", reply.error)
	harness.reply_destroy(&reply, context.allocator)

	after := harness.session_state(&session)
	defer harness.state_destroy(&after, context.allocator)
	testing.expect_value(t, after.digest, before.digest)
	testing.expect_value(t, after.debug.placement.armed, before.debug.placement.armed)
	testing.expect_value(t, after.debug.placement.prefab, before.debug.placement.prefab)
	testing.expect_value(t, after.debug.placement.height, before.debug.placement.height)
	testing.expect_value(t, after.debug.placement.yaw_deg, before.debug.placement.yaw_deg)
}
