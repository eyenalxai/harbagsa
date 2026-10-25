#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package harness_test

import "core:testing"

import "src:harness"

@(test)
every_command_kind_has_one_registry_row :: proc(t: ^testing.T) {
	testing.expect_value(t, len(harness.COMMANDS), int(harness.Command_Kind.Quit) + 1)
	for kind in harness.Command_Kind {
		row := harness.command_row_by_kind(kind)
		testing.expect_value(t, row.kind, kind)
		testing.expect_value(t, harness.command_name(kind), row.name)
		found, present := harness.command_row_by_name(row.name)
		testing.expect(t, present, "a row name is missing from the name lookup")
		testing.expect_value(t, found.kind, kind)
	}
}

@(test)
command_names_are_unique :: proc(t: ^testing.T) {
	for row, index in harness.COMMANDS {
		for other in harness.COMMANDS[index + 1:] {
			testing.expectf(t, row.name != other.name, "duplicate command name %q", row.name)
		}
	}
}

@(test)
a_capture_without_rendering_is_skipped :: proc(t: ^testing.T) {
	session, error := harness.session_create(context.allocator)
	testing.expectf(t, error == "", "session create failed: %s", error)
	defer harness.session_destroy(&session)
	session.render.enabled = false

	reply := execute(t, &session, `{"cmd": "capture", "name": "skipped"}`)
	defer harness.reply_destroy(&reply, context.allocator)
	testing.expect(t, reply.ok, "a no-render capture failed")
	testing.expect_value(t, len(session.capture.captures), 0)
}
