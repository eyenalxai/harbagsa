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
		scenario, parse_error := harness.scenario_parse(string(data), context.allocator)
		testing.expectf(t, parse_error == "", "the snapshot is not a runnable scenario: %s", parse_error)
		harness.scenario_destroy(&scenario, context.allocator)
	}

	state := harness.session_state(&session)
	defer harness.state_destroy(&state, context.allocator)
	testing.expect_value(t, state.notice.text, REPRO_NOTICE)
	_ = os.remove(REPRO_PATH)
}

@(test)
repro_keeps_a_renderer_debug_override :: proc(t: ^testing.T) {
	_ = os.remove(REPRO_PATH)
	session, error := harness.session_create(context.allocator)
	testing.expectf(t, error == "", "session create failed: %s", error)
	defer harness.session_destroy(&session)
	if error != "" {
		return
	}
	session.render.debug = full_renderer_debug()

	reply := execute(t, &session, REPRO_LINE)
	defer harness.reply_destroy(&reply, context.allocator)
	testing.expectf(t, reply.ok, "repro failed: %s", reply.error)
	data, read_error := os.read_entire_file(REPRO_PATH, context.allocator)
	defer delete(data, context.allocator)
	testing.expectf(t, read_error == nil, "the snapshot was not written: %v", read_error)
	if read_error != nil {
		return
	}
	text := string(data)
	testing.expectf(t, strings.contains(text, `"clip_height": 3`), "the snapshot lost clip height: %s", text)
	testing.expectf(
		t,
		strings.contains(text, `"renderer_debug": true`),
		"the snapshot lost the renderer debug gate",
	)
	scenario, parse_error := harness.scenario_parse(text, context.allocator)
	defer harness.scenario_destroy(&scenario, context.allocator)
	testing.expectf(t, parse_error == "", "the snapshot did not parse: %s", parse_error)
	testing.expect(t, scenario.requires.renderer_debug, "the parsed snapshot lost the gate")
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
repro_resolves_a_relative_path_under_the_output_dir :: proc(t: ^testing.T) {
	dir := "/tmp/opencode/harbagsa-repro-output"
	_ = os.remove_all(dir)
	_ = os.make_directory_all(dir)
	defer os.remove_all(dir)

	session, error := harness.session_create(context.allocator)
	testing.expectf(t, error == "", "session create failed: %s", error)
	defer harness.session_destroy(&session)
	session.output_dir = dir

	reply := execute(t, &session, `{"cmd": "repro", "path": "live.json"}`)
	defer harness.reply_destroy(&reply, context.allocator)
	testing.expectf(t, reply.ok, "relative repro failed: %s", reply.error)
	testing.expectf(
		t,
		strings.has_prefix(reply.written, dir),
		"the reply lost the output directory: %s",
		reply.written,
	)
	testing.expect(t, os.is_file("/tmp/opencode/harbagsa-repro-output/live.json"), "the repro was not written under the output directory")
	testing.expect_value(t, game.hud_notice_text(&session.hud), "Scene snapshot · live.json")
}

@(test)
repro_needs_a_path :: proc(t: ^testing.T) {
	_, error := harness.command_parse_string(`{"cmd": "repro"}`, context.allocator)
	defer delete(error, context.allocator)
	testing.expect(t, error != "", "repro without a path parsed")
}
