#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package harness_test

import "core:os"
import "core:strings"
import "core:testing"

import "src:game"
import "src:harness"

REPRO_PATH :: "/tmp/opencode/harbagsa-repro-test.json"
REPRO_LINE :: `{"cmd": "repro", "path": "/tmp/opencode/harbagsa-repro-test.json"}`
REPRO_NOTICE :: "Scene snapshot · /tmp/opencode/harbagsa-repro-test.json"

@(test)
repro_writes_a_scene_and_sets_the_notice :: proc(t: ^testing.T) {
	_ = os.remove(REPRO_PATH)
	session, error := harness.session_create(context.allocator)
	testing.expectf(t, error == "", "session create failed: %s", error)
	defer harness.session_destroy(&session)

	reply := execute(t, &session, REPRO_LINE)
	defer harness.reply_destroy(&reply, context.allocator)
	testing.expectf(t, reply.ok, "repro failed: %s", reply.error)
	testing.expectf(
		t,
		strings.contains(reply.written, "harbagsa-repro-test.json"),
		"the reply lost the path: %s",
		reply.written,
	)

	data, read_error := os.read_entire_file(REPRO_PATH, context.allocator)
	testing.expectf(t, read_error == nil, "the snapshot was not written: %v", read_error)
	if read_error == nil {
		defer delete(data, context.allocator)
		testing.expect(
			t,
			strings.contains(string(data), `"cmd": "scene"`),
			"the snapshot is not a scene command",
		)
	}

	state := harness.session_state(&session)
	defer harness.state_destroy(&state, context.allocator)
	testing.expect_value(t, state.notice.text, REPRO_NOTICE)
	_ = os.remove(REPRO_PATH)
}

@(test)
the_notice_is_a_check_field :: proc(t: ^testing.T) {
	_ = os.remove(REPRO_PATH)
	session, error := harness.session_create(context.allocator)
	testing.expectf(t, error == "", "session create failed: %s", error)
	defer harness.session_destroy(&session)
	reply := execute(t, &session, REPRO_LINE)
	harness.reply_destroy(&reply, context.allocator)

	check := execute(
		t,
		&session,
		`{"cmd": "check", "field": "notice.text", "op": "eq", "value": "Scene snapshot · /tmp/opencode/harbagsa-repro-test.json"}`,
	)
	defer harness.reply_destroy(&check, context.allocator)
	testing.expectf(t, check.ok, "the notice check failed: %s", check.error)
	_ = os.remove(REPRO_PATH)
}

@(test)
the_notice_stays_out_of_the_digest :: proc(t: ^testing.T) {
	first, first_error := harness.session_create(context.allocator)
	testing.expectf(t, first_error == "", "session create failed: %s", first_error)
	defer harness.session_destroy(&first)
	second, second_error := harness.session_create(context.allocator)
	testing.expectf(t, second_error == "", "session create failed: %s", second_error)
	defer harness.session_destroy(&second)

	reply := execute(t, &second, REPRO_LINE)
	harness.reply_destroy(&reply, context.allocator)
	first_state := harness.session_state(&first)
	defer harness.state_destroy(&first_state, context.allocator)
	second_state := harness.session_state(&second)
	defer harness.state_destroy(&second_state, context.allocator)
	testing.expect_value(t, second_state.digest, first_state.digest)
	_ = os.remove(REPRO_PATH)
}

@(test)
a_failed_write_keeps_the_failure_notice :: proc(t: ^testing.T) {
	session, error := harness.session_create(context.allocator)
	testing.expectf(t, error == "", "session create failed: %s", error)
	defer harness.session_destroy(&session)

	reply := execute(t, &session, `{"cmd": "repro", "path": "/tmp"}`)
	defer harness.reply_destroy(&reply, context.allocator)
	testing.expectf(t, !reply.ok, "a write to a directory reported success: %s", reply.error)
	testing.expect_value(t, game.hud_notice_text(&session.hud), "Scene snapshot failed · /tmp")

	state := harness.session_state(&session)
	defer harness.state_destroy(&state, context.allocator)
	testing.expect_value(t, state.notice.text, "Scene snapshot failed · /tmp")
}

@(test)
repro_needs_a_path :: proc(t: ^testing.T) {
	_, error := harness.command_parse_string(`{"cmd": "repro"}`, context.allocator)
	defer delete(error, context.allocator)
	testing.expect(t, error != "", "repro without a path parsed")
}
