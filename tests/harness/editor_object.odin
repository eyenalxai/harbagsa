#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package harness_test

import "core:testing"

import "src:game"
import "src:harness"

@(test)
editor_select_object_exposes_the_inspector :: proc(t: ^testing.T) {
	session := editor_session(t)
	defer harness.session_destroy(&session)

	reply := execute(t, &session, `{"cmd": "editor", "select_object": 2}`)
	testing.expectf(t, reply.ok, "select_object failed: %s", reply.error)
	harness.reply_destroy(&reply, context.allocator)

	state := harness.session_state(&session)
	defer harness.state_destroy(&state, context.allocator)
	testing.expect_value(t, state.debug.selection, "object")
	testing.expect_value(t, state.debug.selected_id, 2)
	testing.expect_value(t, state.debug.inspector.prefab, "Crate")
	testing.expect_value(t, state.debug.inspector.body, "dynamic")
	testing.expect_value(t, state.debug.inspector.size.x, 1.0)
	testing.expect_value(t, state.debug.inspector.size.y, 1.0)
	testing.expect_value(t, state.debug.inspector.position.z, 6.0)
	testing.expect_value(t, state.debug.inspector.yaw_deg, 0.0)
	testing.expect(t, !state.debug.inspector.snap, "snap is on by default")
	testing.expect_value(t, state.debug.history.depth, 0)

	reply = execute(
		t,
		&session,
		`{"cmd": "check", "field": "debug.inspector.size.x", "op": "eq", "value": 1}`,
	)
	testing.expectf(t, reply.ok, "inspector size check failed: %s", reply.error)
	harness.reply_destroy(&reply, context.allocator)
	reply = execute(
		t,
		&session,
		`{"cmd": "check", "field": "debug.selected_id", "op": "eq", "value": 2}`,
	)
	testing.expectf(t, reply.ok, "selected id check failed: %s", reply.error)
	harness.reply_destroy(&reply, context.allocator)

	reply = execute(t, &session, `{"cmd": "editor", "select_object": 0}`)
	harness.reply_destroy(&reply, context.allocator)
	harness.state_destroy(&state, context.allocator)
	state = harness.session_state(&session)
	testing.expect_value(t, state.debug.selection, "none")
	testing.expect_value(t, state.debug.inspector.prefab, "")

	reply = execute(t, &session, `{"cmd": "editor", "select_object": 99}`)
	testing.expect(t, !reply.ok, "an unknown object id was selected")
	harness.reply_destroy(&reply, context.allocator)
}

@(test)
editor_move_rotate_body_and_undo :: proc(t: ^testing.T) {
	session := editor_session(t)
	defer harness.session_destroy(&session)
	initial := harness.session_state(&session)
	defer harness.state_destroy(&initial, context.allocator)

	reply := execute(t, &session, `{"cmd": "editor", "select_object": 1}`)
	harness.reply_destroy(&reply, context.allocator)
	reply = execute(t, &session, `{"cmd": "editor", "move": [1, 0.5, 7], "rotate_deg": 30}`)
	testing.expectf(t, reply.ok, "move and rotate failed: %s", reply.error)
	harness.reply_destroy(&reply, context.allocator)
	reply = execute(t, &session, `{"cmd": "editor", "body": "static"}`)
	testing.expectf(t, reply.ok, "body failed: %s", reply.error)
	harness.reply_destroy(&reply, context.allocator)

	state := harness.session_state(&session)
	testing.expect_value(t, state.debug.inspector.position.x, 1.0)
	testing.expect_value(t, state.debug.inspector.position.z, 7.0)
	testing.expect(t, abs(state.debug.inspector.yaw_deg - 30.0) < 0.25, "rotate did not reach the state")
	testing.expect_value(t, state.debug.inspector.body, "static")
	testing.expect_value(t, state.debug.history.depth, 3)
	harness.state_destroy(&state, context.allocator)

	reply = execute(t, &session, `{"cmd": "check", "field": "debug.inspector.yaw_deg", "op": "gt", "value": 29}`)
	testing.expectf(t, reply.ok, "inspector yaw check failed: %s", reply.error)
	harness.reply_destroy(&reply, context.allocator)
	reply = execute(t, &session, `{"cmd": "check", "field": "debug.history.depth", "op": "eq", "value": 3}`)
	testing.expectf(t, reply.ok, "history depth check failed: %s", reply.error)
	harness.reply_destroy(&reply, context.allocator)

	reply = execute(t, &session, `{"cmd": "editor", "undo": true}`)
	harness.reply_destroy(&reply, context.allocator)
	reply = execute(t, &session, `{"cmd": "editor", "undo": true}`)
	harness.reply_destroy(&reply, context.allocator)
	reply = execute(t, &session, `{"cmd": "editor", "undo": true}`)
	harness.reply_destroy(&reply, context.allocator)

	state = harness.session_state(&session)
	testing.expect_value(t, state.debug.inspector.body, "dynamic")
	testing.expect_value(t, state.debug.inspector.position.x, initial.objects[0].position.x)
	testing.expect(t, abs(state.debug.inspector.yaw_deg) < 0.01, "undo left a yaw")
	testing.expect_value(t, state.debug.history.depth, 0)
	testing.expect_value(t, state.debug.history.redo, 3)
	harness.state_destroy(&state, context.allocator)

	reply = execute(t, &session, `{"cmd": "editor", "redo": true}`)
	harness.reply_destroy(&reply, context.allocator)
	state = harness.session_state(&session)
	testing.expect_value(t, state.debug.inspector.position.x, 1.0)
	testing.expect_value(t, state.debug.history.depth, 1)
	harness.state_destroy(&state, context.allocator)
}

@(test)
editor_duplicate_undo_redo_keeps_the_id_and_skips_the_pop :: proc(t: ^testing.T) {
	session := editor_session(t)
	defer harness.session_destroy(&session)

	reply := execute(t, &session, `{"cmd": "editor", "select_object": 1, "duplicate": true}`)
	testing.expectf(t, reply.ok, "duplicate failed: %s", reply.error)
	harness.reply_destroy(&reply, context.allocator)

	state := harness.session_state(&session)
	testing.expect_value(t, len(state.objects), game.INITIAL_CRATE_COUNT + 1)
	testing.expect_value(t, state.debug.selected_id, game.INITIAL_CRATE_COUNT + 1)
	testing.expect_value(t, state.debug.history.depth, 1)
	testing.expect_value(t, state.objects[game.INITIAL_CRATE_COUNT].scale, game.SPAWN_POP_MIN_SCALE)
	copy_id := state.objects[game.INITIAL_CRATE_COUNT].id
	harness.state_destroy(&state, context.allocator)

	reply = execute(t, &session, `{"cmd": "step", "frames": 20}`)
	harness.reply_destroy(&reply, context.allocator)
	reply = execute(t, &session, `{"cmd": "editor", "undo": true}`)
	harness.reply_destroy(&reply, context.allocator)

	state = harness.session_state(&session)
	testing.expect_value(t, len(state.objects), game.INITIAL_CRATE_COUNT)
	testing.expect_value(t, state.debug.selected_id, 0)
	testing.expect_value(t, state.debug.history.depth, 0)
	testing.expect_value(t, state.debug.history.redo, 1)
	harness.state_destroy(&state, context.allocator)

	reply = execute(t, &session, `{"cmd": "editor", "redo": true}`)
	harness.reply_destroy(&reply, context.allocator)
	state = harness.session_state(&session)
	testing.expect_value(t, len(state.objects), game.INITIAL_CRATE_COUNT + 1)
	testing.expect_value(t, state.objects[game.INITIAL_CRATE_COUNT].id, copy_id)
	testing.expect_value(t, state.objects[game.INITIAL_CRATE_COUNT].scale, 1.0)
	testing.expect_value(t, state.objects[game.INITIAL_CRATE_COUNT].spawn_age, 0.0)
	testing.expect_value(t, state.debug.selected_id, 0)
	testing.expect_value(t, state.debug.history.depth, 1)
	harness.state_destroy(&state, context.allocator)
}

@(test)
editor_body_follows_the_palette_rule_and_delete_undoes :: proc(t: ^testing.T) {
	session := editor_session(t)
	defer harness.session_destroy(&session)

	reply := execute(t, &session, `{"cmd": "editor", "select_object": 1}`)
	harness.reply_destroy(&reply, context.allocator)
	reply = execute(t, &session, `{"cmd": "editor", "body": "static", "snap": true}`)
	harness.reply_destroy(&reply, context.allocator)
	state := harness.session_state(&session)
	testing.expect_value(t, state.debug.inspector.body, "static")
	testing.expect(t, state.debug.inspector.snap, "snap did not reach the inspector")
	testing.expect_value(t, state.debug.history.depth, 1)
	harness.state_destroy(&state, context.allocator)

	reply = execute(t, &session, `{"cmd": "editor", "open": true, "body": "dynamic"}`)
	harness.reply_destroy(&reply, context.allocator)
	state = harness.session_state(&session)
	testing.expect_value(t, state.debug.palette.body, "dynamic")
	testing.expect_value(t, state.debug.inspector.body, "static")
	testing.expect_value(t, state.debug.history.depth, 1)
	harness.state_destroy(&state, context.allocator)

	reply = execute(t, &session, `{"cmd": "editor", "open": false, "delete": true}`)
	testing.expectf(t, reply.ok, "delete failed: %s", reply.error)
	harness.reply_destroy(&reply, context.allocator)
	state = harness.session_state(&session)
	testing.expect_value(t, len(state.objects), game.INITIAL_CRATE_COUNT - 1)
	testing.expect_value(t, state.debug.selected_id, 0)
	harness.state_destroy(&state, context.allocator)

	reply = execute(t, &session, `{"cmd": "editor", "undo": true}`)
	harness.reply_destroy(&reply, context.allocator)
	state = harness.session_state(&session)
	testing.expect_value(t, len(state.objects), game.INITIAL_CRATE_COUNT)
	testing.expect_value(t, state.objects[0].id, 1)
	testing.expect_value(t, state.objects[0].body, "static")
	harness.state_destroy(&state, context.allocator)
}

@(test)
editor_object_fields_reject_bad_values :: proc(t: ^testing.T) {
	lines := []string {
		`{"cmd": "editor", "select_object": -1}`,
		`{"cmd": "editor", "select_object": "one"}`,
		`{"cmd": "editor", "move": [0, 1]}`,
		`{"cmd": "editor", "move": "up"}`,
		`{"cmd": "editor", "rotate": "left"}`,
		`{"cmd": "editor", "delete": 1}`,
		`{"cmd": "editor", "duplicate": "yes"}`,
		`{"cmd": "editor", "undo": 1}`,
		`{"cmd": "editor", "redo": "yes"}`,
	}
	for line in lines {
		_, error := harness.command_parse_string(line, context.allocator)
		testing.expectf(t, error != "", "accepted %s", line)
		if error != "" {
			delete(error, context.allocator)
		}
	}
}
