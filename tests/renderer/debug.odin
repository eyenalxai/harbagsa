#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package renderer_test

import "core:log"
import "core:testing"

import "src:frame"
import "src:game"
import "src:renderer"

@(test)
debug_taa_inputs_reset_history :: proc(t: ^testing.T) {
	device: Test_Device
	if !open_test_device(&device) {
		log.info("skipping the renderer debug test: no Vulkan device")
		return
	}
	defer close_test_device(&device)
	state := &device.state

	debug := renderer.renderer_debug(state)
	testing.expect(t, !debug.active, "debug overrides start active")
	debug.active = true
	debug.jitter = false
	testing.expect(t, renderer.set_renderer_debug(state, debug), "jitter change did not reset history")
	testing.expect(t, state.taa.last_reset == .Debug_Override, "reset reason is not the override")
	before := state.taa.reset_count

	debug.freeze_shadow_phase = true
	debug.shadow_phase = 12
	testing.expect(t, renderer.set_renderer_debug(state, debug), "shadow phase did not reset history")
	testing.expect_value(t, state.taa.reset_count, before + 1)
	before = state.taa.reset_count

	debug.clamp = false
	testing.expect(t, renderer.set_renderer_debug(state, debug), "clamp change did not reset history")
	testing.expect_value(t, state.taa.reset_count, before + 1)
	before = state.taa.reset_count

	debug.sky = false
	testing.expect(t, renderer.set_renderer_debug(state, debug), "sky change did not reset history")
	testing.expect_value(t, state.taa.reset_count, before + 1)
	before = state.taa.reset_count

	debug.ao = false
	testing.expect(t, renderer.set_renderer_debug(state, debug), "ao change did not reset history")
	testing.expect_value(t, state.taa.reset_count, before + 1)
	testing.expect(t, !renderer.renderer_debug(state).sky, "sky override did not stick")
	testing.expect(t, !renderer.renderer_debug(state).ao, "ao override did not stick")

	renderer.clear_renderer_debug(state)
	testing.expect(t, !state.taa.debug.active, "clear left the overrides active")
	testing.expect(t, state.taa.enabled, "clear left TAA off")
	testing.expect(t, state.taa.last_reset == .Debug_Override, "clear did not record a reset")
	testing.expect(t, state.taa.debug.sky, "clear left the sky off")
	testing.expect(t, state.taa.debug.ao, "clear left AO off")
}

@(test)
debug_shadow_phase_is_frozen_or_rotating :: proc(t: ^testing.T) {
	device: Test_Device
	if !open_test_device(&device) {
		log.info("skipping the renderer shadow phase test: no Vulkan device")
		return
	}
	defer close_test_device(&device)
	state := &device.state

	debug := renderer.renderer_debug(state)
	debug.active = true
	debug.freeze_shadow_phase = true
	debug.shadow_phase = 7
	renderer.set_renderer_debug(state, debug)
	testing.expect_value(t, renderer.taa_shadow_phase(state), u32(7))

	debug.freeze_shadow_phase = false
	renderer.set_renderer_debug(state, debug)
	state.frame_count = 13
	testing.expect_value(t, renderer.taa_shadow_phase(state), u32(13))
}

@(test)
render_digest_is_stable_for_a_static_scene :: proc(t: ^testing.T) {
	device: Test_Device
	if !open_test_device(&device) {
		log.info("skipping the static digest test: no Vulkan device")
		return
	}
	defer close_test_device(&device)
	state := &device.state
	debug := renderer.renderer_debug(state)
	debug.active = true
	debug.taa = false
	renderer.set_renderer_debug(state, debug)

	sim := game.simulation_create()
	if !game.simulation_is_valid(&sim) {
		return
	}
	defer game.simulation_destroy(&sim)
	editor := game.debug_mode_create()
	hud: game.HUD_State
	scratch: frame.Scratch
	scene := frame.build(&sim, &editor, {alpha = 1.0, captured = true}, nil, &hud, &scratch)
	if frame.draw(state, scene) != .Ok {
		return
	}
	first := state.render_digest
	if frame.draw(state, scene) != .Ok {
		return
	}
	testing.expect(t, state.has_render_digest, "the render digest is missing")
	testing.expect_value(t, state.render_digest.value, first.value)
}
