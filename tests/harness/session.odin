#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package harness_test

import "core:math"
import "core:os"
import "core:strings"
import "core:testing"

import "src:game"
import "src:harness"

RECORD_PATH :: "/tmp/opencode/harbagsa-record-test.json"
RECORD_LINE :: `{"cmd": "record", "path": "/tmp/opencode/harbagsa-record-test.json"}`
REPLAY_LINE :: `{"cmd": "replay", "path": "/tmp/opencode/harbagsa-record-test.json"}`

execute :: proc(t: ^testing.T, session: ^harness.Session, line: string) -> harness.Reply {
	command, error := harness.command_parse_string(line, context.allocator)
	testing.expectf(t, error == "", "command parse failed for %s: %s", line, error)
	if error != "" {
		return {}
	}
	reply := harness.session_execute(session, command, line)
	harness.command_destroy(&command, context.allocator)
	return reply
}

// A rejection test asserts the error without turning the expected rejection
// into a runner failure. The caller owns the returned string.
execute_expect_error :: proc(t: ^testing.T, session: ^harness.Session, line: string) -> string {
	command, parse_error := harness.command_parse_string(line, context.allocator)
	defer harness.command_destroy(&command, context.allocator)
	if parse_error != "" {
		return parse_error
	}
	reply := harness.session_execute(session, command, line)
	defer harness.reply_destroy(&reply, context.allocator)
	testing.expectf(t, !reply.ok, "command was accepted: %s", line)
	if reply.error == "" {
		return ""
	}
	return strings.clone(reply.error, context.allocator)
}

fake_render :: proc(
	ctx: rawptr,
	session: ^harness.Session,
	requests: []harness.Capture_Request,
) -> (
	[]harness.Capture_Result,
	string,
) {
	counter := cast(^int)ctx
	counter^ += 1
	if len(requests) == 0 {
		return nil, ""
	}
	results := make([]harness.Capture_Result, len(requests), context.allocator)
	for request, index in requests {
		results[index] = {
			name = strings.clone(request.name, context.allocator),
			path = strings.clone("/tmp/opencode/fake-capture.png", context.allocator),
			frame = session.frame,
			width = 1,
			height = 1,
			target = "color",
			format = "png",
			target_format = "R8G8B8A8_SRGB",
			hash = strings.clone("fake", context.allocator),
		}
	}
	return results, ""
}

@(test)
session_steps_and_reports_state :: proc(t: ^testing.T) {
	session, error := harness.session_create(context.allocator)
	testing.expectf(t, error == "", "session create failed: %s", error)
	defer harness.session_destroy(&session)
	if error != "" {
		return
	}

	reply := execute(t, &session, `{"cmd": "step", "frames": 60}`)
	harness.reply_destroy(&reply, context.allocator)
	testing.expect_value(t, session.frame, 60)

	state_reply := execute(t, &session, `{"cmd": "state"}`)
	defer harness.reply_destroy(&state_reply, context.allocator)
	testing.expect(t, state_reply.ok, "state command failed")
	testing.expect(t, state_reply.state != nil, "state reply has no state")
	if state_reply.state != nil {
		testing.expect_value(t, state_reply.state.frame, 60)
		testing.expect_value(t, len(state_reply.state.objects), game.INITIAL_OBJECT_COUNT)
		object := state_reply.state.objects[0]
		testing.expect_value(t, object.id, 1)
		testing.expect_value(t, object.prefab, "Crate")
		testing.expect_value(t, object.body, "dynamic")
		testing.expect_value(t, object.scale, 1.0)
		testing.expect_value(t, object.spawn_age, 0.0)
		testing.expect(t, state_reply.state.digest != "", "state digest is empty")
	}
}

@(test)
settle_renders_every_step_without_capturing :: proc(t: ^testing.T) {
	session, _ := harness.session_create(context.allocator)
	defer harness.session_destroy(&session)
	calls: int
	backend := harness.Backend {
		ready  = true,
		ctx    = &calls,
		render = fake_render,
	}
	harness.session_set_backend(&session, &backend, false)

	reply := execute(t, &session, `{"cmd": "settle", "frames": 5}`)
	defer harness.reply_destroy(&reply, context.allocator)
	testing.expect(t, reply.ok, "settle failed")
	testing.expect_value(t, session.frame, 5)
	testing.expect_value(t, calls, 5)
	testing.expect_value(t, len(session.capture.captures), 0)
}

@(test)
settle_steps_without_a_backend :: proc(t: ^testing.T) {
	session, _ := harness.session_create(context.allocator)
	defer harness.session_destroy(&session)

	reply := execute(t, &session, `{"cmd": "settle", "frames": 3}`)
	defer harness.reply_destroy(&reply, context.allocator)
	testing.expect(t, reply.ok, "settle without a backend failed")
	testing.expect_value(t, session.frame, 3)
	testing.expect_value(t, len(session.capture.captures), 0)
}

@(test)
look_uses_the_real_sensitivity :: proc(t: ^testing.T) {
	session, _ := harness.session_create(context.allocator)
	defer harness.session_destroy(&session)
	reply := execute(t, &session, `{"cmd": "look", "dx": 100, "dy": 10}`)
	defer harness.reply_destroy(&reply, context.allocator)
	expected_yaw := -f32(100.0) * game.YAW_SENSITIVITY
	expected_pitch := -f32(10.0) * game.PITCH_SENSITIVITY
	testing.expectf(t, abs(session.sim.player.yaw - expected_yaw) < 0.0001, "yaw %v", session.sim.player.yaw)
	testing.expectf(
		t,
		abs(session.sim.player.pitch - expected_pitch) < 0.0001,
		"pitch %v",
		session.sim.player.pitch,
	)
}

@(test)
face_sets_the_view_directly :: proc(t: ^testing.T) {
	session, _ := harness.session_create(context.allocator)
	defer harness.session_destroy(&session)
	reply := execute(t, &session, `{"cmd": "face", "yaw_deg": 71.6197, "pitch_deg": -28.6479}`)
	defer harness.reply_destroy(&reply, context.allocator)
	testing.expect(t, abs(session.sim.player.yaw - math.to_radians(f32(71.6197))) < 0.0001, "yaw not set")
	testing.expect(t, abs(session.sim.player.pitch - math.to_radians(f32(-28.6479))) < 0.0001, "pitch not set")
}

@(test)
reset_returns_objects_to_spawn :: proc(t: ^testing.T) {
	session, _ := harness.session_create(context.allocator)
	defer harness.session_destroy(&session)
	execute(t, &session, `{"cmd": "input", "forward": 1}`)
	step_reply := execute(t, &session, `{"cmd": "step", "frames": 60}`)
	harness.reply_destroy(&step_reply, context.allocator)
	reset_reply := execute(t, &session, `{"cmd": "reset"}`)
	harness.reply_destroy(&reset_reply, context.allocator)
	testing.expect(t, session.sim.player.position == game.SPAWN_POSITION, "player did not reset")
	id := game.simulation_objects(&session.sim)[0].id
	box := game.simulation_object_box(&session.sim, id)
	testing.expect(t, box.center == game.INITIAL_CRATE_POSITIONS[0], "object did not reset")
}

@(test)
failed_check_is_recorded_and_reported :: proc(t: ^testing.T) {
	session, _ := harness.session_create(context.allocator)
	defer harness.session_destroy(&session)
	reply := execute(t, &session, `{"cmd": "check", "field": "player.position.z", "op": "gt", "value": 100}`)
	defer harness.reply_destroy(&reply, context.allocator)
	testing.expect(t, !reply.ok, "failing check reported success")
	testing.expect_value(t, len(session.checks), 1)
	testing.expect_value(t, len(session.failures), 1)
}

@(test)
future_capture_queues_until_its_frame :: proc(t: ^testing.T) {
	session, _ := harness.session_create(context.allocator)
	defer harness.session_destroy(&session)
	calls: int
	backend := harness.Backend {
		ready  = true,
		ctx    = &calls,
		render = fake_render,
	}
	harness.session_set_backend(&session, &backend, false)

	first := execute(t, &session, `{"cmd": "capture", "name": "later", "frame": 10}`)
	harness.reply_destroy(&first, context.allocator)
	testing.expect_value(t, len(session.capture.captures), 0)
	testing.expect_value(t, len(session.capture.pending), 1)

	step_reply := execute(t, &session, `{"cmd": "step", "frames": 10}`)
	harness.reply_destroy(&step_reply, context.allocator)
	testing.expect_value(t, calls, 1)
	testing.expect_value(t, len(session.capture.captures), 1)
	testing.expect_value(t, session.capture.captures[0].frame, 10)
}

@(test)
past_capture_is_rejected :: proc(t: ^testing.T) {
	session, _ := harness.session_create(context.allocator)
	defer harness.session_destroy(&session)
	step_reply := execute(t, &session, `{"cmd": "step", "frames": 5}`)
	harness.reply_destroy(&step_reply, context.allocator)
	reply := execute(t, &session, `{"cmd": "capture", "frame": 0}`)
	defer harness.reply_destroy(&reply, context.allocator)
	testing.expect(t, !reply.ok, "past capture was accepted")
}

@(test)
view_perf_flag_reaches_the_session :: proc(t: ^testing.T) {
	session, _ := harness.session_create(context.allocator)
	defer harness.session_destroy(&session)
	reply := execute(t, &session, `{"cmd": "view", "perf": true}`)
	defer harness.reply_destroy(&reply, context.allocator)
	testing.expectf(t, reply.ok, "view failed: %s", reply.error)
	testing.expect(t, session.view.perf, "perf flag was dropped")
}

@(test)
record_then_replay_round_trips :: proc(t: ^testing.T) {
	_ = os.remove(RECORD_PATH)
	session, _ := harness.session_create(context.allocator)
	defer harness.session_destroy(&session)

	view_reply := execute(t, &session, `{"cmd": "view", "hud": false}`)
	harness.reply_destroy(&view_reply, context.allocator)
	record_reply := execute(t, &session, RECORD_LINE)
	harness.reply_destroy(&record_reply, context.allocator)
	input_reply := execute(t, &session, `{"cmd": "input", "forward": 1}`)
	harness.reply_destroy(&input_reply, context.allocator)
	step_reply := execute(t, &session, `{"cmd": "step", "frames": 30}`)
	harness.reply_destroy(&step_reply, context.allocator)
	before := harness.session_state(&session)
	defer harness.state_destroy(&before, context.allocator)
	stop_reply := execute(t, &session, `{"cmd": "record"}`)
	harness.reply_destroy(&stop_reply, context.allocator)

	replay_reply := execute(t, &session, REPLAY_LINE)
	defer harness.reply_destroy(&replay_reply, context.allocator)
	testing.expectf(t, replay_reply.ok, "replay failed: %s", replay_reply.error)
	after := harness.session_state(&session)
	defer harness.state_destroy(&after, context.allocator)
	testing.expect_value(t, after.digest, before.digest)
}

@(test)
digest_is_deterministic :: proc(t: ^testing.T) {
	first, _ := harness.session_create(context.allocator)
	defer harness.session_destroy(&first)
	second, _ := harness.session_create(context.allocator)
	defer harness.session_destroy(&second)
	sessions := [2]^harness.Session{&first, &second}
	for session in sessions {
		input := execute(t, session, `{"cmd": "input", "forward": 1}`)
		harness.reply_destroy(&input, context.allocator)
		step := execute(t, session, `{"cmd": "step", "frames": 45}`)
		harness.reply_destroy(&step, context.allocator)
	}
	first_state := harness.session_state(&first)
	defer harness.state_destroy(&first_state, context.allocator)
	second_state := harness.session_state(&second)
	defer harness.state_destroy(&second_state, context.allocator)
	testing.expect_value(t, first_state.digest, second_state.digest)
	testing.expect(t, math.abs(first_state.player.position.z - second_state.player.position.z) == 0, "state diverged")
}

@(test)
object_edit_changes_the_state_digest :: proc(t: ^testing.T) {
	session, _ := harness.session_create(context.allocator)
	defer harness.session_destroy(&session)
	before := harness.session_state(&session)
	defer harness.state_destroy(&before, context.allocator)

	id := game.simulation_objects(&session.sim)[0].id
	testing.expect(t, game.simulation_move_object(&session.sim, id, {0, 2, 0}), "move failed")
	after := harness.session_state(&session)
	defer harness.state_destroy(&after, context.allocator)
	testing.expect(t, after.digest != before.digest, "object transform did not change the digest")
}
