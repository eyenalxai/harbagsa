#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package harness_test

import "core:os"
import "core:strings"
import "core:testing"

import "src:harness"

RECORD_TEST_PATH :: "/tmp/opencode/harbagsa-record-actions.json"

@(test)
record_actions_omits_the_initial_scene :: proc(t: ^testing.T) {
	session, error := harness.session_create(context.allocator)
	testing.expectf(t, error == "", "session create failed: %s", error)
	defer harness.session_destroy(&session)
	line := strings.concatenate(
		{`{"cmd":"record","path":"`, RECORD_TEST_PATH, `","actions":true}`},
		context.temp_allocator,
	)
	reply := execute(t, &session, line)
	harness.reply_destroy(&reply, context.allocator)
	reply = execute(t, &session, `{"cmd":"record"}`)
	harness.reply_destroy(&reply, context.allocator)
	defer os.remove(RECORD_TEST_PATH)

	data, read_error := os.read_entire_file(RECORD_TEST_PATH, context.allocator)
	defer delete(data, context.allocator)
	testing.expectf(t, read_error == nil, "cannot read the recording: %v", read_error)
	if read_error != nil {
		return
	}
	text := string(data)
	testing.expect(t, strings.contains(text, `"reset"`), "the reset is missing")
	testing.expect(t, !strings.contains(text, `"scene"`), "the action recording kept the scene")
}

@(test)
record_keeps_the_initial_scene_by_default :: proc(t: ^testing.T) {
	session, error := harness.session_create(context.allocator)
	testing.expectf(t, error == "", "session create failed: %s", error)
	defer harness.session_destroy(&session)
	line := strings.concatenate(
		{`{"cmd":"record","path":"`, RECORD_TEST_PATH, `"}`},
		context.temp_allocator,
	)
	reply := execute(t, &session, line)
	harness.reply_destroy(&reply, context.allocator)
	reply = execute(t, &session, `{"cmd":"record"}`)
	harness.reply_destroy(&reply, context.allocator)
	defer os.remove(RECORD_TEST_PATH)

	data, read_error := os.read_entire_file(RECORD_TEST_PATH, context.allocator)
	defer delete(data, context.allocator)
	testing.expectf(t, read_error == nil, "cannot read the recording: %v", read_error)
	if read_error == nil {
		testing.expect(t, strings.contains(string(data), `"scene"`), "the default recording lost the scene")
	}
}
