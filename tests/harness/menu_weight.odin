#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package harness_test

import "core:testing"

import "src:harness"

@(test)
menu_set_command_sets_and_reports_the_type_weight :: proc(t: ^testing.T) {
	session, _ := harness.session_create(context.allocator)
	defer harness.session_destroy(&session)
	reply := execute(t, &session, `{"cmd": "menu", "open": true, "select": 3}`)
	harness.reply_destroy(&reply, context.allocator)

	reply = execute(t, &session, `{"cmd": "menu", "set": 900}`)
	harness.reply_destroy(&reply, context.allocator)
	testing.expect_value(t, session.sim.settings.type_weight, 900)

	state := harness.session_state(&session)
	defer harness.state_destroy(&state, context.allocator)
	testing.expect_value(t, state.settings.type_weight, 900)

	_, parse_error := harness.command_parse_string(`{"cmd": "menu", "set": 50}`, context.allocator)
	testing.expect(t, parse_error != "", "a weight below the axis was accepted")
}
