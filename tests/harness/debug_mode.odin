#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package harness_test

import "core:testing"

import "src:harness"

@(test)
debug_mode_command_toggles_and_is_checkable :: proc(t: ^testing.T) {
	session, error := harness.session_create(context.allocator)
	testing.expectf(t, error == "", "session create failed: %s", error)
	defer harness.session_destroy(&session)
	if error != "" {
		return
	}

	reply := execute(t, &session, `{"cmd": "debug_mode", "active": true}`)
	harness.reply_destroy(&reply, context.allocator)
	testing.expect(t, session.debug.active, "debug mode did not turn on")

	state := harness.session_state(&session)
	testing.expect(t, state.debug.active, "the state did not report debug mode")
	harness.state_destroy(&state, context.allocator)

	reply = execute(t, &session, `{"cmd": "check", "field": "debug.active", "op": "eq", "value": true}`)
	testing.expect(t, reply.ok, "debug.active was not checkable")
	harness.reply_destroy(&reply, context.allocator)
}

@(test)
debug_mode_command_is_idempotent :: proc(t: ^testing.T) {
	session, error := harness.session_create(context.allocator)
	testing.expectf(t, error == "", "session create failed: %s", error)
	defer harness.session_destroy(&session)
	if error != "" {
		return
	}

	for _ in 0 ..< 3 {
		reply := execute(t, &session, `{"cmd": "debug_mode", "active": true}`)
		harness.reply_destroy(&reply, context.allocator)
	}
	testing.expect(t, session.debug.active, "repeating the command turned debug mode off")

	reply := execute(t, &session, `{"cmd": "debug_mode", "active": false}`)
	harness.reply_destroy(&reply, context.allocator)
	testing.expect(t, !session.debug.active, "debug mode did not turn off")
}

@(test)
debug_mode_command_needs_active :: proc(t: ^testing.T) {
	_, parse_error := harness.command_parse_string(`{"cmd": "debug_mode"}`, context.allocator)
	testing.expect(t, parse_error != "", "a missing 'active' must fail")
}
