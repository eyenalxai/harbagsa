#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package harness_test

import "core:strings"
import "core:testing"

import "src:harness"
import "src:renderer"

@(test)
renderer_debug_parses_every_override :: proc(t: ^testing.T) {
	command, error := harness.command_parse_string(
		`{"cmd": "renderer_debug", "taa": false, "jitter": false, "history_weight": 0.25,
		  "clamp": false, "depth_trust": true, "freeze_shadow_phase": true,
		  "shadow_phase": 9, "light_shadows": false, "synthetic_lights": 8,
		  "sky": false, "ao": false}`,
		context.allocator,
	)
	defer harness.command_destroy(&command, context.allocator)
	testing.expectf(t, error == "", "renderer_debug parse failed: %s", error)
	if error != "" {
		return
	}
	debug := command.renderer_debug
	testing.expect(t, command.kind == .Renderer_Debug, "wrong command kind")
	testing.expect(t, debug.has_taa && !debug.taa, "taa was not parsed")
	testing.expect(t, debug.has_jitter && !debug.jitter, "jitter was not parsed")
	testing.expect(t, debug.has_history_weight && debug.history_weight == 0.25, "weight was not parsed")
	testing.expect(t, debug.has_clamp && !debug.clamp, "clamp was not parsed")
	testing.expect(t, debug.has_depth_trust && debug.depth_trust, "depth trust was not parsed")
	testing.expect(t, debug.has_freeze_shadow_phase, "freeze was not parsed")
	testing.expect(t, debug.has_shadow_phase && debug.shadow_phase == 9, "phase was not parsed")
	testing.expect(t, debug.has_light_shadows && !debug.light_shadows, "light shadows were not parsed")
	testing.expect(t, debug.has_synthetic_lights && debug.synthetic_lights == 8, "synthetic lights were not parsed")
	testing.expect(t, debug.has_sky && !debug.sky, "sky was not parsed")
	testing.expect(t, debug.has_ao && !debug.ao, "ao was not parsed")
}

@(test)
renderer_debug_rejects_bad_fields :: proc(t: ^testing.T) {
	bad := []string{
		`{"cmd": "renderer_debug", "shadow_phase": 64}`,
		`{"cmd": "renderer_debug", "history_weight": 1.5}`,
		`{"cmd": "renderer_debug", "clear": true, "jitter": false}`,
		`{"cmd": "renderer_debug", "clear": true, "synthetic_lights": 2}`,
		`{"cmd": "renderer_debug", "synthetic_lights": 9}`,
		`{"cmd": "renderer_debug", "light_shadows": 1}`,
		`{"cmd": "renderer_debug", "speed": 2}`,
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
scenario_compiles_a_renderer_debug_block :: proc(t: ^testing.T) {
	scenario, error := harness.scenario_parse(
		`{"renderer_debug": {"jitter": false, "shadow_phase": 2, "sky": false, "ao": false},
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
	testing.expect(t, first.renderer_debug.has_jitter && !first.renderer_debug.jitter, "jitter was dropped")
	testing.expect(t, first.renderer_debug.shadow_phase == 2, "shadow phase was dropped")
	testing.expect(t, first.renderer_debug.has_sky && !first.renderer_debug.sky, "sky was dropped")
	testing.expect(t, first.renderer_debug.has_ao && !first.renderer_debug.ao, "ao was dropped")
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
		`{"cmd": "renderer_debug", "jitter": false, "history_weight": 0.5, "shadow_phase": 3,
		  "light_shadows": false, "synthetic_lights": 8}`,
	)
	testing.expectf(t, reply.ok, "gated debug command failed: %s", reply.error)
	harness.reply_destroy(&reply, context.allocator)
	testing.expect(t, fake.debug.active, "debug overrides were not activated")
	testing.expect(t, !fake.debug.jitter, "jitter was not disabled")
	testing.expect(t, fake.debug.history_weight == 0.5, "history weight was not set")
	testing.expect(t, fake.debug.freeze_shadow_phase, "shadow phase was not frozen")
	testing.expect(t, fake.debug.shadow_phase == 3, "shadow phase was not set")
	testing.expect(t, !fake.debug.light_shadows, "light shadows were not disabled")
	testing.expect(t, fake.debug.synthetic_lights == 8, "synthetic lights were not set")

	reply = execute(t, &session, `{"cmd": "renderer_debug", "clear": true}`)
	testing.expectf(t, reply.ok, "clear failed: %s", reply.error)
	harness.reply_destroy(&reply, context.allocator)
	testing.expect_value(t, fake.clears, 1)
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
