#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package harness_test

import "core:strings"
import "core:testing"

import "src:frame"
import "src:harness"

@(test)
scene_round_trips_a_player_view :: proc(t: ^testing.T) {
	session, error := harness.session_create(context.allocator)
	testing.expectf(t, error == "", "session create failed: %s", error)
	defer harness.session_destroy(&session)
	if error != "" {
		return
	}
	session.sim.settings.type_weight = 640
	before := harness.session_state(&session)
	defer harness.state_destroy(&before, context.allocator)
	digest := strings.clone(before.digest, context.allocator)
	defer delete(digest, context.allocator)

	text := scene_text(t, &session, frame.Options{hud = true, captured = true})
	defer delete(text, context.allocator)
	reply := execute(t, &session, text)
	defer harness.reply_destroy(&reply, context.allocator)
	testing.expectf(t, reply.ok, "scene apply failed: %s", reply.error)

	after := harness.session_state(&session)
	defer harness.state_destroy(&after, context.allocator)
	testing.expect_value(t, after.camera.source, "player")
	testing.expect_value(t, after.settings.type_weight, f32(640))
	testing.expect_value(t, after.digest, digest)
}

@(test)
scene_round_trips_a_debug_scene :: proc(t: ^testing.T) {
	session, error := harness.session_create(context.allocator)
	testing.expectf(t, error == "", "session create failed: %s", error)
	defer harness.session_destroy(&session)
	if error != "" {
		return
	}
	for line in ([]string{
		`{"cmd": "debug_mode", "active": true}`,
		`{"cmd": "editor", "camera": {"position": [2, 3, 12], "yaw_deg": 12, "pitch_deg": -18}}`,
		`{"cmd": "editor", "place": {"prefab": "Lamp", "position": [1.5, 0.25, 8], "yaw_deg": 30, "body": "static"}}`,
		`{"cmd": "sun", "azimuth_deg": 52.1, "elevation_deg": 25, "diameter_deg": 0.53}`,
		`{"cmd": "view", "hud": false, "debug": true, "hint": false, "perf": false}`,
	}) {
		reply := execute(t, &session, line)
		harness.reply_destroy(&reply, context.allocator)
	}
	session.sim.settings.type_weight = 700
	before := harness.session_state(&session)
	defer harness.state_destroy(&before, context.allocator)
	digest := strings.clone(before.digest, context.allocator)
	defer delete(digest, context.allocator)
	object_count := len(before.objects)

	text := scene_text(t, &session, frame.Options{hud = false, debug_view = true, captured = true})
	defer delete(text, context.allocator)
	reply := execute(t, &session, text)
	defer harness.reply_destroy(&reply, context.allocator)
	testing.expectf(t, reply.ok, "scene apply failed: %s", reply.error)

	after := harness.session_state(&session)
	defer harness.state_destroy(&after, context.allocator)
	testing.expect(t, after.debug.active, "the scene left debug mode")
	testing.expect_value(t, after.camera.source, "debug")
	testing.expect_value(t, len(after.objects), object_count)
	testing.expect_value(t, after.objects[object_count - 1].prefab, "Lamp")
	testing.expect_value(t, after.digest, digest)
}

@(test)
scene_rejects_bad_blocks :: proc(t: ^testing.T) {
	cases := []string {
		`{"cmd":"scene"}`,
		`{"cmd":"scene","camera":{"source":"override","position":[0,1,0]}}`,
		`{"cmd":"scene","camera":{"source":"orbit","position":[0,1,0],"yaw_deg":0,"pitch_deg":0}}`,
		`{"cmd":"scene","sun":{"position":[0,50,0]}}`,
		`{"cmd":"scene","objects":[{"id":1,"prefab":"Nope","body":"static","position":[0,0,0],"rotation":[0,0,0,1]}]}`,
		`{"cmd":"scene","settings":{"window_mode":"Windowed"}}`,
		`{"cmd":"scene","view":{"hud":true}}`,
		`{"cmd":"scene","extra":1}`,
	}
	for line in cases {
		_, error := harness.command_parse_string(line, context.allocator)
		testing.expectf(t, error != "", "scene accepted %s", line)
		if error != "" {
			delete(error, context.allocator)
		}
	}
}

@(private)
scene_text :: proc(t: ^testing.T, session: ^harness.Session, options: frame.Options) -> string {
	scene := frame.scene_capture(
		&session.sim,
		&session.debug,
		&session.hud,
		options,
		nil,
		context.temp_allocator,
	)
	defer frame.scene_destroy(&scene, context.temp_allocator)
	text := frame.scene_json(scene, context.temp_allocator)
	testing.expectf(t, text != "", "cannot encode the scene")
	return strings.clone(text, context.allocator)
}
