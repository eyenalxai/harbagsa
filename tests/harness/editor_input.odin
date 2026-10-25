#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package harness_test

import "core:testing"

import "src:harness"

@(test)
editor_pointer_and_relative_fields_drive_one_edit_set :: proc(t: ^testing.T) {
	session := editor_session(t)
	defer harness.session_destroy(&session)

	reply := execute(
		t,
		&session,
		`{"cmd": "editor", "camera": {"position": [0, 1.7, 14], "yaw_deg": 0, "pitch_deg": -11.4592}}`,
	)
	harness.reply_destroy(&reply, context.allocator)
	reply = execute(t, &session, `{"cmd": "editor", "primary": true}`)
	harness.reply_destroy(&reply, context.allocator)
	before := harness.session_state(&session)
	defer harness.state_destroy(&before, context.allocator)
	testing.expect_value(t, before.debug.selection, "object")

	reply = execute(t, &session, `{"cmd": "editor", "drag_move": [10, 0]}`)
	testing.expectf(t, reply.ok, "drag_move failed: %s", reply.error)
	harness.reply_destroy(&reply, context.allocator)

	dragged := harness.session_state(&session)
	testing.expect(t, dragged.debug.inspector.position.x > before.debug.inspector.position.x, "the drag did not move the object")
	testing.expect_value(t, dragged.debug.history.depth, 1)
	harness.state_destroy(&dragged, context.allocator)

	reply = execute(t, &session, `{"cmd": "editor", "drag_release": true, "wheel": 2}`)
	testing.expectf(t, reply.ok, "wheel failed: %s", reply.error)
	harness.reply_destroy(&reply, context.allocator)
	raised := harness.session_state(&session)
	testing.expect(t, raised.debug.inspector.position.y > before.debug.inspector.position.y, "the wheel did not raise the object")
	testing.expect_value(t, raised.debug.history.depth, 2)
	harness.state_destroy(&raised, context.allocator)

	reply = execute(t, &session, `{"cmd": "editor", "turn": 1}`)
	testing.expectf(t, reply.ok, "turn failed: %s", reply.error)
	harness.reply_destroy(&reply, context.allocator)
	reply = execute(t, &session, `{"cmd": "editor", "turn": -1, "large": true}`)
	testing.expectf(t, reply.ok, "large turn failed: %s", reply.error)
	harness.reply_destroy(&reply, context.allocator)
	turned := harness.session_state(&session)
	testing.expect(t, abs(turned.debug.inspector.yaw_deg + 30.0) < 0.25, "the relative turns did not compose")
	harness.state_destroy(&turned, context.allocator)

	reply = execute(t, &session, `{"cmd": "editor", "open": true, "select": 0}`)
	harness.reply_destroy(&reply, context.allocator)
	reply = execute(t, &session, `{"cmd": "editor", "palette_step": -1}`)
	testing.expectf(t, reply.ok, "palette_step failed: %s", reply.error)
	harness.reply_destroy(&reply, context.allocator)
	reply = execute(t, &session, `{"cmd": "editor", "palette_number": 5, "snap_toggle": true}`)
	testing.expectf(t, reply.ok, "palette_number failed: %s", reply.error)
	harness.reply_destroy(&reply, context.allocator)

	palette := harness.session_state(&session)
	testing.expect_value(t, palette.debug.palette.selected, 4)
	testing.expect(t, palette.debug.placement.snap, "snap_toggle did not reach the state")
	harness.state_destroy(&palette, context.allocator)

	reply = execute(t, &session, `{"cmd": "editor", "open": false, "secondary": true}`)
	testing.expectf(t, reply.ok, "secondary failed: %s", reply.error)
	harness.reply_destroy(&reply, context.allocator)
	cleared := harness.session_state(&session)
	testing.expect_value(t, cleared.debug.selection, "none")
	testing.expect_value(t, cleared.debug.selected_id, u32(0))
	harness.state_destroy(&cleared, context.allocator)

	command, parse_error := harness.command_parse_string(
		`{"cmd": "editor", "palette_number": 0}`,
		context.allocator,
	)
	if parse_error == "" {
		harness.command_destroy(&command, context.allocator)
	}
	testing.expect(t, parse_error != "", "palette_number 0 was accepted")
	if parse_error != "" {
		delete(parse_error, context.allocator)
	}
}
