#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package harness_test

import "core:strings"
import "core:testing"

import "src:frame"
import "src:harness"

@(test)
place_remove_and_check_by_name :: proc(t: ^testing.T) {
	session, create_error := harness.session_create(context.allocator)
	if create_error != "" {
		testing.expectf(t, false, "session create failed: %s", create_error)
		return
	}
	defer harness.session_destroy(&session)

	reply := execute(
		t,
		&session,
		`{"cmd": "place", "prefab": "Block", "position": [0, 0.5, 10], "name": "alpha"}`,
	)
	testing.expectf(t, reply.ok, "named place failed: %s", reply.error)
	alpha_id := reply.placed
	harness.reply_destroy(&reply, context.allocator)
	testing.expect(t, alpha_id != 0, "named place returned no id")

	reply = execute(
		t,
		&session,
		`{"cmd": "check", "field": "objects.alpha.position.z", "op": "eq", "value": 10}`,
	)
	testing.expectf(t, reply.ok, "named check failed: %s", reply.error)
	harness.reply_destroy(&reply, context.allocator)

	reply = execute(
		t,
		&session,
		`{"cmd": "place", "prefab": "Block", "position": [2, 0.5, 10], "name": "alpha"}`,
	)
	testing.expect(t, !reply.ok, "a duplicate name was accepted")
	harness.reply_destroy(&reply, context.allocator)

	reply = execute(t, &session, `{"cmd": "remove", "name": "alpha"}`)
	testing.expectf(t, reply.ok, "named remove failed: %s", reply.error)
	harness.reply_destroy(&reply, context.allocator)
	reply = execute(t, &session, `{"cmd": "check", "field": "objects.count", "op": "eq", "value": 6}`)
	testing.expectf(t, reply.ok, "count check failed: %s", reply.error)
	harness.reply_destroy(&reply, context.allocator)
}

@(test)
editor_selects_by_name_and_the_scene_keeps_it :: proc(t: ^testing.T) {
	session, create_error := harness.session_create(context.allocator)
	if create_error != "" {
		testing.expectf(t, false, "session create failed: %s", create_error)
		return
	}
	defer harness.session_destroy(&session)

	reply := execute(t, &session, `{"cmd": "debug_mode", "active": true}`)
	harness.reply_destroy(&reply, context.allocator)
	reply = execute(
		t,
		&session,
		`{"cmd": "place", "prefab": "Wall", "position": [0, 1.5, 12], "name": "named-wall"}`,
	)
	testing.expectf(t, reply.ok, "named place failed: %s", reply.error)
	wall_id := reply.placed
	harness.reply_destroy(&reply, context.allocator)

	reply = execute(t, &session, `{"cmd": "editor", "select_object": "named-wall"}`)
	testing.expectf(t, reply.ok, "select by name failed: %s", reply.error)
	harness.reply_destroy(&reply, context.allocator)
	state := harness.session_state(&session)
	testing.expect_value(t, state.debug.selected_id, wall_id)
	found_name := false
	for object in state.objects {
		if object.name == "named-wall" {
			found_name = true
		}
	}
	testing.expect(t, found_name, "the state lost the object name")
	harness.state_destroy(&state, context.allocator)

	scene := frame.scene_capture(
		&session.sim,
		&session.debug,
		frame.Options{captured = true},
		nil,
		nil,
		context.temp_allocator,
	)
	defer frame.scene_destroy(&scene, context.temp_allocator)
	text := frame.scene_json(scene, context.temp_allocator)
	testing.expectf(t, strings.contains(text, `"name": "named-wall"`), "the scene lost the name: %s", text)
}
