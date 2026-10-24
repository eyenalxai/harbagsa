#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package harness_test

import "core:os"
import "core:strings"
import "core:testing"

import b3 "libs:box3d"
import "src:game"
import "src:harness"

CRATES_RECORD_PATH :: "/tmp/opencode/harbagsa-crates-record-test.json"
CRATES_RECORD_LINE :: `{"cmd": "record", "path": "/tmp/opencode/harbagsa-crates-record-test.json"}`

@(test)
crates_command_parses_each_action :: proc(t: ^testing.T) {
	lines := []string{
		`{"cmd": "crates", "reset": true}`,
		`{"cmd": "crates", "clear": true}`,
		`{"cmd": "crates", "add": {"position": [0, 0.5, 6]}}`,
		`{"cmd": "crates", "add": {"origin": [0, 0.5, 6], "count": 60, "columns": 10, "spacing": [1.0, 0.0, 1.0]}}`,
		`{"cmd": "crates", "remove": {"index": 3}}`,
	}
	for line in lines {
		command, error := harness.command_parse_string(line, context.allocator)
		testing.expectf(t, error == "", "parse failed for %s: %s", line, error)
		harness.command_destroy(&command, context.allocator)
	}
}

@(test)
crates_command_rejects_bad_input :: proc(t: ^testing.T) {
	lines := []string{
		`{"cmd": "crates"}`,
		`{"cmd": "crates", "reset": false}`,
		`{"cmd": "crates", "reset": true, "clear": true}`,
		`{"cmd": "crates", "add": {"position": [0, 0.5, 6], "count": 2}}`,
		`{"cmd": "crates", "add": {"origin": [0, 0.5, 6], "count": 0, "columns": 1, "spacing": [1, 0, 1]}}`,
		`{"cmd": "crates", "add": {"origin": [0, 0.5, 6], "count": 65, "columns": 1, "spacing": [1, 0, 1]}}`,
		`{"cmd": "crates", "add": {"origin": [0, 0.5, 6], "count": 4, "columns": 5, "spacing": [1, 0, 1]}}`,
		`{"cmd": "crates", "remove": {"index": -1}}`,
		`{"cmd": "crates", "remove": {"index": 64}}`,
	}
	for line in lines {
		_, error := harness.command_parse_string(line, context.allocator)
		testing.expectf(t, error != "", "accepted %s", line)
		if error != "" {
			delete(error, context.allocator)
		}
	}
}

@(test)
crates_add_clear_and_remove_change_the_count :: proc(t: ^testing.T) {
	session, _ := harness.session_create(context.allocator)
	defer harness.session_destroy(&session)

	reply := execute(t, &session, `{"cmd": "crates", "clear": true}`)
	harness.reply_destroy(&reply, context.allocator)
	testing.expect_value(t, game.simulation_crate_count(&session.sim), 0)

	reply = execute(t, &session, `{"cmd": "crates", "add": {"position": [0, 0.5, 6]}}`)
	harness.reply_destroy(&reply, context.allocator)
	testing.expect_value(t, game.simulation_crate_count(&session.sim), 1)
	testing.expect(t, game.simulation_crate_box(&session.sim, 0).center == b3.Vec3{0, 0.5, 6}, "single crate position")

	reply = execute(
		t,
		&session,
		`{"cmd": "crates", "add": {"origin": [0, 0.5, 6], "count": 3, "columns": 2, "spacing": [1.0, 0.0, 2.0]}}`,
	)
	harness.reply_destroy(&reply, context.allocator)
	testing.expect_value(t, game.simulation_crate_count(&session.sim), 4)
	testing.expect(t, game.simulation_crate_box(&session.sim, 1).center == b3.Vec3{0, 0.5, 6}, "grid origin")
	testing.expect(t, game.simulation_crate_box(&session.sim, 2).center == b3.Vec3{1, 0.5, 6}, "grid column")
	testing.expect(t, game.simulation_crate_box(&session.sim, 3).center == b3.Vec3{0, 0.5, 8}, "grid row")

	reply = execute(t, &session, `{"cmd": "crates", "remove": {"index": 0}}`)
	harness.reply_destroy(&reply, context.allocator)
	testing.expect_value(t, game.simulation_crate_count(&session.sim), 3)
	testing.expect(t, game.simulation_crate_box(&session.sim, 0).center == b3.Vec3{0, 0.5, 6}, "remove shifted the list")

	reply = execute(t, &session, `{"cmd": "crates", "remove": {"index": 3}}`)
	harness.reply_destroy(&reply, context.allocator)
	testing.expect_value(t, game.simulation_crate_count(&session.sim), 3)

	reply = execute(t, &session, `{"cmd": "crates", "reset": true}`)
	harness.reply_destroy(&reply, context.allocator)
	testing.expect_value(t, game.simulation_crate_count(&session.sim), game.INITIAL_CRATE_COUNT)
}

@(test)
crates_add_rejects_capacity_without_a_partial_add :: proc(t: ^testing.T) {
	session, _ := harness.session_create(context.allocator)
	defer harness.session_destroy(&session)
	before := game.simulation_crate_count(&session.sim)

	reply := execute(
		t,
		&session,
		`{"cmd": "crates", "add": {"origin": [0, 0.5, 6], "count": 62, "columns": 10, "spacing": [1, 0, 1]}}`,
	)
	harness.reply_destroy(&reply, context.allocator)
	testing.expect_value(t, game.simulation_crate_count(&session.sim), before)
}

@(test)
crates_command_records_and_replays :: proc(t: ^testing.T) {
	_ = os.remove(CRATES_RECORD_PATH)
	session, _ := harness.session_create(context.allocator)
	defer harness.session_destroy(&session)

	reply := execute(t, &session, CRATES_RECORD_LINE)
	harness.reply_destroy(&reply, context.allocator)
	reply = execute(t, &session, `{"cmd": "crates", "add": {"position": [0, 0.5, 6]}}`)
	harness.reply_destroy(&reply, context.allocator)
	reply = execute(t, &session, `{"cmd": "step", "frames": 2}`)
	harness.reply_destroy(&reply, context.allocator)
	before := game.simulation_crate_count(&session.sim)
	reply = execute(t, &session, `{"cmd": "record"}`)
	harness.reply_destroy(&reply, context.allocator)

	replay_line := strings.concatenate(
		{`{"cmd": "replay", "path": "`, CRATES_RECORD_PATH, `"}`},
		context.temp_allocator,
	)
	reply = execute(t, &session, replay_line)
	defer harness.reply_destroy(&reply, context.allocator)
	testing.expectf(t, reply.ok, "replay failed: %s", reply.error)
	testing.expect_value(t, game.simulation_crate_count(&session.sim), before)
}
