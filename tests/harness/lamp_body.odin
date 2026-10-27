#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package harness_test

import "core:strings"
import "core:testing"

import "src:harness"

@(test)
place_command_normalizes_a_static_lamp :: proc(t: ^testing.T) {
	session, error := harness.session_create(context.allocator)
	testing.expectf(t, error == "", "session create failed: %s", error)
	defer harness.session_destroy(&session)

	reply := execute(
		t,
		&session,
		`{"cmd":"place","prefab":"Lamp","position":[0,1,8],"body":"static","name":"static-request"}`,
	)
	testing.expectf(t, reply.ok, "lamp place failed: %s", reply.error)
	harness.reply_destroy(&reply, context.allocator)

	state := harness.session_state(&session)
	defer harness.state_destroy(&state, context.allocator)
	for object in state.objects {
		if object.name == "static-request" {
			testing.expect_value(t, object.body, "dynamic")
			return
		}
	}
	testing.expect(t, false, "the placed lamp is missing")
}

@(test)
scene_command_normalizes_a_static_lamp :: proc(t: ^testing.T) {
	session, error := harness.session_create(context.allocator)
	testing.expectf(t, error == "", "session create failed: %s", error)
	defer harness.session_destroy(&session)

	reply := execute(
		t,
		&session,
		`{"cmd":"scene","objects":[{"id":1,"prefab":"Lamp","body":"static","position":[0,1,8],"rotation":[0,0,0,1]}]}`,
	)
	testing.expectf(t, reply.ok, "scene load failed: %s", reply.error)
	harness.reply_destroy(&reply, context.allocator)

	state := harness.session_state(&session)
	defer harness.state_destroy(&state, context.allocator)
	testing.expect_value(t, len(state.objects), 1)
	testing.expect_value(t, state.objects[0].body, "dynamic")
	testing.expect(t, state.objects[0].light.active, "the scene lamp has no light")
}

@(test)
editor_refuses_a_static_lamp_conversion :: proc(t: ^testing.T) {
	session := editor_session(t)
	defer harness.session_destroy(&session)

	reply := execute(
		t,
		&session,
		`{"cmd":"place","prefab":"Lamp","position":[0,1,8],"name":"edit-lamp"}`,
	)
	testing.expectf(t, reply.ok, "lamp place failed: %s", reply.error)
	harness.reply_destroy(&reply, context.allocator)

	reply = execute(
		t,
		&session,
		`{"cmd":"editor","select_object":"edit-lamp","body":"static"}`,
	)
	testing.expect(t, !reply.ok, "the editor converted a lamp to static")
	testing.expect(
		t,
		strings.contains(reply.error, "dynamic"),
		"the refusal does not name the dynamic rule",
	)
	harness.reply_destroy(&reply, context.allocator)

	state := harness.session_state(&session)
	defer harness.state_destroy(&state, context.allocator)
	testing.expect_value(t, state.objects[len(state.objects) - 1].body, "dynamic")
}
