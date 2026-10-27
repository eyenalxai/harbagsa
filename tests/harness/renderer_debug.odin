#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package harness_test

import "core:os"
import "core:reflect"
import "core:strings"
import "core:testing"

import "src:harness"
import "src:renderer"

@(test)
renderer_debug_parses_every_override :: proc(t: ^testing.T) {
	command, error := harness.command_parse_string(
		`{"cmd": "renderer_debug", "taa": false, "jitter": false, "history_weight": 0.25,
		  "clamp": false, "depth_trust": true, "synthetic_lights": 9, "clip_height": 3.0,
		  "light_shadows": false}`,
		context.allocator,
	)
	defer harness.command_destroy(&command, context.allocator)
	testing.expectf(t, error == "", "renderer_debug parse failed: %s", error)
	if error != "" {
		return
	}
	debug := command.renderer_debug
	testing.expect(t, command.kind == .Renderer_Debug, "wrong command kind")
	expect_patch_value(t, debug.taa, false, "taa")
	expect_patch_value(t, debug.jitter, false, "jitter")
	expect_patch_value(t, debug.history_weight, f32(0.25), "weight")
	expect_patch_value(t, debug.clamp, false, "clamp")
	expect_patch_value(t, debug.depth_trust, true, "depth trust")
	expect_patch_value(t, debug.synthetic_lights, 9, "synthetic lights")
	expect_patch_value(t, debug.clip_height, f32(3.0), "clip height")
	expect_patch_value(t, debug.light_shadows, false, "light shadows")
}

@(test)
renderer_debug_rejects_bad_fields :: proc(t: ^testing.T) {
	bad := []string{
		`{"cmd": "renderer_debug", "history_weight": 1.5}`,
		`{"cmd": "renderer_debug", "clear": true, "jitter": false}`,
		`{"cmd": "renderer_debug", "clear": true, "synthetic_lights": 2}`,
		`{"cmd": "renderer_debug", "clear": true, "taa": null}`,
		`{"cmd": "renderer_debug", "synthetic_lights": "many"}`,		`{"cmd": "renderer_debug", "speed": 2}`,
		`{"cmd": "renderer_debug", "clip_height": 1001}`,
	}
	for line in bad {
		_, error := harness.command_parse_string(line, context.allocator)
		testing.expectf(t, error != "", "bad debug command was accepted: %s", line)
		if error != "" {
			delete(error, context.allocator)
		}
	}
}

@(test)
renderer_debug_parses_a_null_reset :: proc(t: ^testing.T) {
	command, error := harness.command_parse_string(
		`{"cmd":"renderer_debug","history_weight":null,"synthetic_lights":null,"clip_height":null,"light_shadows":null}`,
		context.allocator,
	)
	defer harness.command_destroy(&command, context.allocator)
	testing.expectf(t, error == "", "null reset parse failed: %s", error)
	if error != "" {
		return
	}
	debug := command.renderer_debug
	expect_patch_unset(t, debug.history_weight, "weight")
	expect_patch_unset(t, debug.synthetic_lights, "synthetic lights")
	expect_patch_unset(t, debug.light_shadows, "light shadows")
	testing.expect(t, .History_Weight in debug.reset, "the weight reset was dropped")
	testing.expect(t, .Synthetic_Lights in debug.reset, "the synthetic light reset was dropped")
	testing.expect(t, .Light_Shadows in debug.reset, "the light shadow reset was dropped")
	testing.expect(t, .Clip_Height in debug.reset, "the clip height reset was dropped")
}

@(test)
scenario_compiles_a_renderer_debug_block :: proc(t: ^testing.T) {
	scenario, error := harness.scenario_parse(
		`{"renderer_debug": {"jitter": false, "synthetic_lights": 2, "clip_height": 4},
		  "commands": [{"cmd": "step", "frames": 1}]}`,
		context.allocator,
	)
	defer harness.scenario_destroy(&scenario, context.allocator)
	testing.expectf(t, error == "", "scenario parse failed: %s", error)
	if error != "" {
		return
	}
	testing.expect(t, len(scenario.commands) > 0, "scenario has no commands")
	if len(scenario.commands) == 0 {
		return
	}
	first := scenario.commands[0]
	testing.expect(t, first.kind == .Renderer_Debug, "debug block is not the first command")
	expect_patch_value(t, first.renderer_debug.jitter, false, "jitter")
	expect_patch_value(t, first.renderer_debug.synthetic_lights, 2, "synthetic lights")
	expect_patch_value(t, first.renderer_debug.clip_height, f32(4), "clip height")
}

@(test)
scenario_declares_the_renderer_debug_gate :: proc(t: ^testing.T) {
	scenario, error := harness.scenario_parse(
		`{"requires": {"renderer_debug": true}, "commands": [{"cmd": "step", "frames": 1}]}`,
		context.allocator,
	)
	defer harness.scenario_destroy(&scenario, context.allocator)
	testing.expectf(t, error == "", "scenario parse failed: %s", error)
	if error == "" {
		testing.expect(t, scenario.requires.renderer_debug, "the renderer debug gate was dropped")
	}

	bad := []string{
		`{"requires": true, "commands": [{"cmd": "step", "frames": 1}]}`,
		`{"requires": {"renderer_debug": 1}, "commands": [{"cmd": "step", "frames": 1}]}`,
		`{"requires": {"nope": true}, "commands": [{"cmd": "step", "frames": 1}]}`,
	}
	for line in bad {
		_, bad_error := harness.scenario_parse(line, context.allocator)
		testing.expectf(t, bad_error != "", "bad requires block was accepted: %s", line)
		if bad_error != "" {
			delete(bad_error, context.allocator)
		}
	}
}

@(test)
renderer_debug_needs_the_gate :: proc(t: ^testing.T) {
	session, _ := harness.session_create(context.allocator)
	defer harness.session_destroy(&session)
	fake := Fake_Renderer_Debug{}
	backend := harness.Backend {
		ready       = true,
		ctx         = &fake,
		get_debug   = fake_get_debug,
		set_debug   = fake_set_debug,
		clear_debug = fake_clear_debug,
	}
	harness.session_set_backend(&session, &backend, false)

	reply := execute(t, &session, `{"cmd": "renderer_debug", "jitter": false}`)
	testing.expect(t, !reply.ok, "debug command passed without the gate")
	gate_error := strings.contains(reply.error, "--debug-renderer")
	harness.reply_destroy(&reply, context.allocator)
	testing.expect(t, gate_error, "the gate error does not name the flag")

	session.debug_renderer = true
	reply = execute(
		t,
		&session,
		`{"cmd": "renderer_debug", "jitter": false, "history_weight": 0.5,
		  "synthetic_lights": 8, "clip_height": 3}`,
	)
	testing.expectf(t, reply.ok, "gated debug command failed: %s", reply.error)
	harness.reply_destroy(&reply, context.allocator)
	testing.expect(t, fake.debug.active, "debug overrides were not activated")
	testing.expect(t, !fake.debug.jitter, "jitter was not disabled")
	testing.expect(t, fake.debug.history_weight == 0.5, "history weight was not set")
	testing.expect(t, fake.debug.clip_height == 3, "clip height was not set")
	testing.expect(t, fake.debug.synthetic_lights == 8, "synthetic lights were not set")

	reply = execute(t, &session, `{"cmd": "renderer_debug", "history_weight": null, "clip_height": null}`)
	testing.expectf(t, reply.ok, "null reset failed: %s", reply.error)
	harness.reply_destroy(&reply, context.allocator)
	testing.expect_value(t, fake.debug.history_weight, f32(-1))
	testing.expect(t, fake.debug.clip_height == 1000, "the clip reset did not restore the default")
	testing.expect(t, fake.debug.synthetic_lights == 8, "the clip reset cleared another override")

	reply = execute(t, &session, `{"cmd": "renderer_debug", "clear": true}`)
	testing.expectf(t, reply.ok, "clear failed: %s", reply.error)
	harness.reply_destroy(&reply, context.allocator)
	testing.expect_value(t, fake.clears, 1)
}

RENDERER_DEBUG_RECORD_PATH :: "/tmp/opencode/harbagsa-renderer-debug-record.json"

@(test)
renderer_debug_record_keeps_the_gate :: proc(t: ^testing.T) {
	session, _ := harness.session_create(context.allocator)
	defer harness.session_destroy(&session)
	fake := Fake_Renderer_Debug{}
	backend := harness.Backend {
		ready       = true,
		ctx         = &fake,
		get_debug   = fake_get_debug,
		set_debug   = fake_set_debug,
		clear_debug = fake_clear_debug,
	}
	harness.session_set_backend(&session, &backend, false)
	session.debug_renderer = true

	record_line := `{"cmd":"record","path":"` + RENDERER_DEBUG_RECORD_PATH + `"}`
	reply := execute(t, &session, record_line)
	harness.reply_destroy(&reply, context.allocator)
	reply = execute(t, &session, `{"cmd":"renderer_debug","jitter":false}`)
	harness.reply_destroy(&reply, context.allocator)
	reply = execute(t, &session, `{"cmd":"record"}`)
	harness.reply_destroy(&reply, context.allocator)
	defer os.remove(RENDERER_DEBUG_RECORD_PATH)

	data, read_error := os.read_entire_file(RENDERER_DEBUG_RECORD_PATH, context.allocator)
	testing.expectf(t, read_error == nil, "cannot read the recording: %v", read_error)
	if read_error != nil {
		return
	}
	defer delete(data, context.allocator)
	text := string(data)
	testing.expect(t, strings.contains(text, `"requires"`), "the recording lost the gate")
	testing.expect(t, strings.contains(text, "renderer_debug"), "the recording lost the command")

	session.debug_renderer = false
	replay_line := `{"cmd":"replay","path":"` + RENDERER_DEBUG_RECORD_PATH + `"}`
	reply = execute(t, &session, replay_line)
	defer harness.reply_destroy(&reply, context.allocator)
	testing.expectf(t, reply.ok, "replay failed: %s", reply.error)
	testing.expect(t, session.debug_renderer, "replay did not enable the declared gate")
}

@(test)
renderer_debug_field_table_matches_the_patch :: proc(t: ^testing.T) {
	keys := harness.renderer_debug_keys(context.temp_allocator, false)
	defer delete(keys, context.temp_allocator)
	for field in reflect.struct_fields_zipped(typeid_of(renderer.Renderer_Debug_Patch)) {
		name := reflect.struct_tag_get(field.tag, "json")
		if index := strings.index_byte(name, ','); index >= 0 {
			name = name[:index]
		}
		testing.expectf(t, key_in(name, keys), "patch field %q has no debug table row", name)
	}
	for key in keys {
		if key == "clear" {
			continue
		}
		found := false
		for field in reflect.struct_fields_zipped(typeid_of(renderer.Renderer_Debug_Patch)) {
			name := reflect.struct_tag_get(field.tag, "json")
			if index := strings.index_byte(name, ','); index >= 0 {
				name = name[:index]
			}
			if name == key {
				found = true
				break
			}
		}
		testing.expectf(t, found, "debug table row %q has no patch field", key)
	}
}

@(private)
key_in :: proc(value: string, values: []string) -> bool {
	for candidate in values {
		if candidate == value {
			return true
		}
	}
	return false
}

@(private)
expect_patch_value :: proc(t: ^testing.T, value: Maybe($Value), expected: Value, name: string) {
	actual, has := value.?
	testing.expectf(t, has && actual == expected, "%s was not parsed", name)
}

@(private)
expect_patch_unset :: proc(t: ^testing.T, value: Maybe($Value), name: string) {
	_, has := value.?
	testing.expectf(t, !has, "%s was set by a null reset", name)
}

Fake_Renderer_Debug :: struct {
	debug:  renderer.Renderer_Debug,
	clears: int,
}

fake_get_debug :: proc(ctx: rawptr) -> renderer.Renderer_Debug {
	return (cast(^Fake_Renderer_Debug)ctx).debug
}

fake_set_debug :: proc(ctx: rawptr, debug: renderer.Renderer_Debug) -> bool {
	(cast(^Fake_Renderer_Debug)ctx).debug = debug
	return true
}

fake_clear_debug :: proc(ctx: rawptr) {
	fake := cast(^Fake_Renderer_Debug)ctx
	fake.clears += 1
	fake.debug = {}
}
