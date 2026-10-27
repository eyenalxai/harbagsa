#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package harness_test

import "core:testing"

import "src:game"
import "src:harness"

@(test)
editor_place_reports_the_spawn_pop :: proc(t: ^testing.T) {
	session := editor_session(t)
	defer harness.session_destroy(&session)
	reply := execute(
		t,
		&session,
		`{"cmd": "editor", "place": {"prefab": "Block", "position": [4, 0.5, 9], "body": "static"}}`,
	)
	harness.reply_destroy(&reply, context.allocator)

	state := harness.session_state(&session)
	object := state.objects[game.INITIAL_OBJECT_COUNT]
	testing.expect_value(t, object.scale, 0.01)
	testing.expect_value(t, object.spawn_age, 0.0)
	testing.expect_value(t, object.position.y, 0.5)
	for initial in state.objects[:game.INITIAL_OBJECT_COUNT] {
		testing.expect_value(t, initial.scale, 1.0)
		testing.expect_value(t, initial.spawn_age, 0.0)
	}
	harness.state_destroy(&state, context.allocator)

	reply = execute(t, &session, `{"cmd": "step", "frames": 10}`)
	harness.reply_destroy(&reply, context.allocator)
	state = harness.session_state(&session)
	testing.expect(t, state.objects[game.INITIAL_OBJECT_COUNT].scale > 1.05, "no overshoot")
	harness.state_destroy(&state, context.allocator)

	reply = execute(t, &session, `{"cmd": "step", "frames": 7}`)
	harness.reply_destroy(&reply, context.allocator)
	state = harness.session_state(&session)
	object = state.objects[game.INITIAL_OBJECT_COUNT]
	testing.expect_value(t, object.scale, 1.0)
	testing.expect(t, object.spawn_age >= game.SPAWN_POP_DURATION, "the pop did not finish")
	harness.state_destroy(&state, context.allocator)
}

@(test)
spawn_pop_phase_stays_out_of_the_digest :: proc(t: ^testing.T) {
	first, first_error := harness.session_create(context.allocator)
	testing.expectf(t, first_error == "", "first session failed: %s", first_error)
	defer harness.session_destroy(&first)
	second, second_error := harness.session_create(context.allocator)
	testing.expectf(t, second_error == "", "second session failed: %s", second_error)
	defer harness.session_destroy(&second)

	spawn := game.Object_Spawn {
		prefab    = .Block,
		body_mode = .Static,
		center    = {4, 0.5, 9},
		yaw_rad   = 0,
	}
	popped := game.simulation_create_object(&first.sim, spawn)
	restored := game.simulation_restore_object(&second.sim, spawn)
	testing.expect_value(t, popped, restored)

	first_state := harness.session_state(&first)
	defer harness.state_destroy(&first_state, context.allocator)
	second_state := harness.session_state(&second)
	defer harness.state_destroy(&second_state, context.allocator)

	testing.expect_value(t, first_state.objects[game.INITIAL_OBJECT_COUNT].scale, 0.01)
	testing.expect_value(t, second_state.objects[game.INITIAL_OBJECT_COUNT].scale, 1.0)
	testing.expect_value(t, first_state.digest, second_state.digest)
}
