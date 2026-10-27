#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package harness_test

import "core:strings"
import "core:testing"

import "src:frame"
import "src:harness"
import "src:renderer"

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
		`{"cmd":"scene","objects":[{"id":1,"prefab":"Nope","body":"static","position":[0,0,0],"rotation":[0,0,0,1]}]}`,
		`{"cmd":"scene","settings":{"window_mode":"Orbit"}}`,
		`{"cmd":"scene","settings":{"display":-1}}`,
		`{"cmd":"scene","view":{"hud":"yes"}}`,
		`{"cmd":"scene","renderer_debug":{"taa":"yes"}}`,
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

@(test)
scene_applies_renderer_debug_overrides :: proc(t: ^testing.T) {
	session, error := harness.session_create(context.allocator)
	testing.expectf(t, error == "", "session create failed: %s", error)
	defer harness.session_destroy(&session)
	if error != "" {
		return
	}
	state: Fake_Renderer_Debug
	backend := harness.Backend {
		ready     = true,
		ctx       = &state,
		get_debug = fake_get_debug,
		set_debug = fake_set_debug,
		snapshot  = fake_snapshot,
	}
	harness.session_set_backend(&session, &backend, false)
	session.debug_renderer = true

	reply := execute(t, &session, `{"cmd":"scene","renderer_debug":{"taa":false,"clip_height":4}}`)
	defer harness.reply_destroy(&reply, context.allocator)
	testing.expectf(t, reply.ok, "scene renderer debug failed: %s", reply.error)
	testing.expect(t, state.debug.active, "the override is not active")
	testing.expect(t, !state.debug.taa, "taa was not disabled")
	testing.expect_value(t, state.debug.clip_height, f32(4))
}

@(test)
scene_snapshot_keeps_every_renderer_debug_field :: proc(t: ^testing.T) {
	session, error := harness.session_create(context.allocator)
	testing.expectf(t, error == "", "session create failed: %s", error)
	defer harness.session_destroy(&session)
	if error != "" {
		return
	}
	expected := full_renderer_debug()
	fake := Fake_Renderer_Debug{}
	backend := harness.Backend {
		ready       = true,
		ctx         = &fake,
		get_debug   = fake_get_debug,
		set_debug   = fake_set_debug,
		clear_debug = fake_clear_debug,
		snapshot    = fake_snapshot,
	}
	harness.session_set_backend(&session, &backend, false)
	session.debug_renderer = true

	scene := frame.scene_capture(
		&session.sim,
		&session.debug,
		frame.Options{captured = true},
		nil,
		&expected,
		context.temp_allocator,
	)
	defer frame.scene_destroy(&scene, context.temp_allocator)
	text := frame.scene_json(scene, context.temp_allocator)
	testing.expectf(t, strings.contains(text, `"clip_height": 3`), "the snapshot lost clip height: %s", text)
	testing.expectf(t, strings.contains(text, `"depth_trust": true`), "the snapshot lost depth trust")

	reply := execute(t, &session, text)
	defer harness.reply_destroy(&reply, context.allocator)
	testing.expectf(t, reply.ok, "scene apply failed: %s", reply.error)
	testing.expect_value(t, fake.debug, expected)
}

@(test)
scene_snapshot_omits_the_automatic_history_weight :: proc(t: ^testing.T) {
	session, error := harness.session_create(context.allocator)
	testing.expectf(t, error == "", "session create failed: %s", error)
	defer harness.session_destroy(&session)
	if error != "" {
		return
	}
	debug := renderer.renderer_debug_default()
	debug.active = true
	scene := frame.scene_capture(
		&session.sim,
		&session.debug,
		frame.Options{captured = true},
		nil,
		&debug,
		context.temp_allocator,
	)
	defer frame.scene_destroy(&scene, context.temp_allocator)
	text := frame.scene_json(scene, context.temp_allocator)
	testing.expect(
		t,
		!strings.contains(text, `"history_weight"`),
		"the automatic history weight entered the snapshot",
	)
}

@(private)
full_renderer_debug :: proc() -> renderer.Renderer_Debug {
	debug := renderer.renderer_debug_default()
	debug.active = true
	debug.taa = false
	debug.jitter = false
	debug.history_weight = 0.25
	debug.clamp = false
	debug.force_depth_trust = true
	debug.synthetic_lights = 9
	debug.clip_height = 3.0
	debug.light_shadows = false
	debug.gi = false
	return debug
}

@(private)
fake_snapshot :: proc(ctx: rawptr) -> harness.Backend_Snapshot {
	return {report = {last_reset = "none"}}
}

@(test)
scene_applies_partial_settings_and_view :: proc(t: ^testing.T) {
	session, error := harness.session_create(context.allocator)
	testing.expectf(t, error == "", "session create failed: %s", error)
	defer harness.session_destroy(&session)
	if error != "" {
		return
	}
	session.sim.settings.type_weight = 640
	session.view = {hud = true, debug = true, hint = false, perf = false}

	reply := execute(
		t,
		&session,
		`{"cmd":"scene","settings":{"type_weight":700},"view":{"hint":true}}`,
	)
	defer harness.reply_destroy(&reply, context.allocator)
	testing.expectf(t, reply.ok, "partial scene failed: %s", reply.error)
	testing.expect_value(t, session.sim.settings.type_weight, f32(700))
	testing.expect(t, session.view.hud, "the partial view cleared hud")
	testing.expect(t, session.view.debug, "the partial view cleared debug")
	testing.expect(t, session.view.hint, "the partial view did not set hint")
	testing.expect(t, !session.view.perf, "the partial view set perf")
}

@(private)
scene_text :: proc(t: ^testing.T, session: ^harness.Session, options: frame.Options) -> string {
	scene := frame.scene_capture(
		&session.sim,
		&session.debug,
		options,
		nil,
		nil,
		context.temp_allocator,
	)
	defer frame.scene_destroy(&scene, context.temp_allocator)
	text := frame.scene_json(scene, context.temp_allocator)
	testing.expectf(t, text != "", "cannot encode the scene")
	return strings.clone(text, context.allocator)
}
