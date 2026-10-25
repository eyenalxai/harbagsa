#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package harness_test

import "core:math"
import "core:testing"

import "src:harness"

@(test)
camera_look_at_removes_the_hand_computed_angles :: proc(t: ^testing.T) {
	command, error := harness.command_parse_string(
		`{"cmd":"camera","position":[0,1.7,0],"look_at":[0,1.7,-5]}`,
		context.allocator,
	)
	defer harness.command_destroy(&command, context.allocator)
	testing.expectf(t, error == "", "camera parse failed: %s", error)
	if error != "" {
		return
	}
	testing.expect(t, command.camera.has_angles, "the camera has no angles")
	testing.expect(t, abs(command.camera.yaw_rad) < 1e-5, "looking down -z has a nonzero yaw")
	testing.expect(t, abs(command.camera.pitch_rad) < 1e-5, "looking level has a nonzero pitch")
}

@(test)
camera_look_at_uses_the_forward_convention :: proc(t: ^testing.T) {
	command, error := harness.command_parse_string(
		`{"cmd":"camera","position":[0,0,0],"look_at":[5,0,0]}`,
		context.allocator,
	)
	defer harness.command_destroy(&command, context.allocator)
	testing.expectf(t, error == "", "camera parse failed: %s", error)
	if error != "" {
		return
	}
	testing.expectf(
		t,
		abs(command.camera.yaw_rad + math.PI / 2) < 1e-4,
		"looking along +x should be yaw -pi/2, got %v",
		command.camera.yaw_rad,
	)
}

@(test)
camera_rejects_look_at_with_angles :: proc(t: ^testing.T) {
	_, error := harness.command_parse_string(
		`{"cmd":"camera","position":[0,0,0],"look_at":[0,0,-1],"yaw_deg":0,"pitch_deg":0}`,
		context.allocator,
	)
	testing.expectf(t, error != "", "look_at with yaw and pitch was accepted")
	if error != "" {
		delete(error, context.allocator)
	}
}

@(test)
camera_rejects_a_look_at_at_the_position :: proc(t: ^testing.T) {
	_, error := harness.command_parse_string(
		`{"cmd":"camera","position":[1,2,3],"look_at":[1,2,3]}`,
		context.allocator,
	)
	testing.expectf(t, error != "", "a look_at equal to the position was accepted")
	if error != "" {
		delete(error, context.allocator)
	}
}

@(test)
camera_fov_is_in_degrees_and_bounded :: proc(t: ^testing.T) {
	command, error := harness.command_parse_string(
		`{"cmd":"camera","position":[0,0,0],"yaw_deg":0,"pitch_deg":0,"fov_deg":75}`,
		context.allocator,
	)
	defer harness.command_destroy(&command, context.allocator)
	testing.expectf(t, error == "", "camera parse failed: %s", error)
	testing.expect(t, command.camera.has_fov, "the fov was not recorded")
	testing.expect_value(t, command.camera.fov_deg, f32(75))
	bad_fovs := []string{
		`{"cmd":"camera","position":[0,0,0],"yaw_deg":0,"pitch_deg":0,"fov_deg":0}`,
		`{"cmd":"camera","position":[0,0,0],"yaw_deg":0,"pitch_deg":0,"fov_deg":171}`,
	}
	for line in bad_fovs {
		_, bad := harness.command_parse_string(line, context.allocator)
		testing.expectf(t, bad != "", "out-of-range fov accepted: %s", line)
		if bad != "" {
			delete(bad, context.allocator)
		}
	}
}

@(test)
camera_state_reports_the_override_and_the_player :: proc(t: ^testing.T) {
	session, error := harness.session_create(context.allocator)
	testing.expectf(t, error == "", "session create failed: %s", error)
	defer harness.session_destroy(&session)
	if error != "" {
		return
	}
	reply := execute(t, &session, `{"cmd":"camera","position":[1,2,3],"look_at":[1,2,4],"fov_deg":60}`)
	defer harness.reply_destroy(&reply, context.allocator)
	state := harness.session_state(&session)
	defer harness.state_destroy(&state, context.allocator)
	testing.expect(t, state.camera.overridden, "the camera override is not reported")
	testing.expectf(t, abs(state.camera.fov_deg - 60) < 1e-4, "fov is %v", state.camera.fov_deg)
	testing.expect_value(t, state.camera.position.x, f32(1))
	testing.expect(
		t,
		abs(abs(state.camera.yaw_deg) - 180) < 1e-3,
		"looking along +z should be yaw +-180",
	)

	clear := execute(t, &session, `{"cmd":"camera","clear":true}`)
	harness.reply_destroy(&clear, context.allocator)
	cleared := harness.session_state(&session)
	defer harness.state_destroy(&cleared, context.allocator)
	testing.expect(t, !cleared.camera.overridden, "the cleared camera still reports an override")
	testing.expect_value(t, cleared.camera.fov_deg, f32(90))
	testing.expect_value(t, cleared.camera.source, "player")
}

@(test)
camera_state_reports_the_debug_view :: proc(t: ^testing.T) {
	session, error := harness.session_create(context.allocator)
	testing.expectf(t, error == "", "session create failed: %s", error)
	defer harness.session_destroy(&session)
	if error != "" {
		return
	}
	reply := execute(t, &session, `{"cmd":"debug_mode","active":true}`)
	harness.reply_destroy(&reply, context.allocator)
	reply = execute(
		t,
		&session,
		`{"cmd":"editor","camera":{"position":[4,3,-2],"yaw_deg":28.6479,"pitch_deg":-14.3239}}`,
	)
	harness.reply_destroy(&reply, context.allocator)

	state := harness.session_state(&session)
	defer harness.state_destroy(&state, context.allocator)
	testing.expect_value(t, state.camera.source, "debug")
	testing.expect(t, state.camera.overridden, "the debug view is not reported as an override")
	testing.expect_value(t, state.camera.position.x, f32(4))
	testing.expect_value(t, state.camera.position.y, f32(3))
	testing.expect_value(t, state.camera.position.z, f32(-2))
	testing.expect_value(t, state.camera.yaw_deg, f32(28.6479))
	testing.expect_value(t, state.camera.pitch_deg, f32(-14.3239))
	testing.expectf(t, abs(state.camera.fov_deg - 90) < 1e-4, "debug fov is %v", state.camera.fov_deg)

	reply = execute(t, &session, `{"cmd":"camera","position":[1,2,3],"yaw_deg":0,"pitch_deg":0}`)
	harness.reply_destroy(&reply, context.allocator)
	overridden := harness.session_state(&session)
	defer harness.state_destroy(&overridden, context.allocator)
	testing.expect_value(t, overridden.camera.source, "override")
	testing.expect_value(t, overridden.camera.position.x, f32(1))

	reply = execute(t, &session, `{"cmd":"camera","clear":true}`)
	harness.reply_destroy(&reply, context.allocator)
	reply = execute(t, &session, `{"cmd":"debug_mode","active":false}`)
	harness.reply_destroy(&reply, context.allocator)
	restored := harness.session_state(&session)
	defer harness.state_destroy(&restored, context.allocator)
	testing.expect_value(t, restored.camera.source, "player")
	testing.expect(t, !restored.camera.overridden, "leaving debug mode still reports an override")
}
