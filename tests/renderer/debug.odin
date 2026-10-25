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
	testing.expect(t, debug.light_shadows, "point-light shadows start off")
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

	debug.light_shadows = false
	testing.expect(t, renderer.set_renderer_debug(state, debug), "light shadow change did not reset history")
	testing.expect_value(t, state.taa.reset_count, before + 1)
	before = state.taa.reset_count

	debug.synthetic_lights = 8
	testing.expect(t, renderer.set_renderer_debug(state, debug), "synthetic lights did not reset history")
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
	testing.expect(t, state.taa.debug.light_shadows, "clear left light shadows off")
	testing.expect_value(t, state.taa.debug.synthetic_lights, 0)
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

	sim := game.simulation_create(context.allocator)
	if !game.simulation_is_valid(&sim) {
		return
	}
	defer game.simulation_destroy(&sim)
	editor := game.debug_mode_create(context.allocator)
	hud: game.HUD_State
	scratch: frame.Scratch
	defer frame.scratch_destroy(&scratch)
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

@(test)
spawn_pop_keeps_taa_history :: proc(t: ^testing.T) {
	device: Test_Device
	if !open_test_device(&device) {
		log.info("skipping the spawn pop history test: no Vulkan device")
		return
	}
	defer close_test_device(&device)
	state := &device.state

	sim := game.simulation_create(context.allocator)
	if !game.simulation_is_valid(&sim) {
		return
	}
	defer game.simulation_destroy(&sim)
	id := game.simulation_create_object(
		&sim,
		{prefab = .Block, body_mode = .Static, center = {0, 0.5, 9}, yaw_rad = 0},
	)
	testing.expect(t, id != game.INVALID_OBJECT_ID, "block did not create")

	editor := game.debug_mode_create(context.allocator)
	hud: game.HUD_State
	scratch: frame.Scratch
	defer frame.scratch_destroy(&scratch)
	scene := frame.build(&sim, &editor, {alpha = 1.0}, nil, &hud, &scratch)
	if frame.draw(state, scene) != .Ok {
		return
	}
	before := state.taa.reset_count
	box_before := scene.boxes[len(scene.boxes) - 1].half_extents.y
	model_before := state.taa.prev_models[state.taa.prev_model_count - 1]

	game.simulation_step_world(&sim, game.SIMULATION_STEP)
	scene = frame.build(&sim, &editor, {alpha = 1.0}, nil, &hud, &scratch)
	box_after := scene.boxes[len(scene.boxes) - 1].half_extents.y
	if frame.draw(state, scene) != .Ok {
		return
	}

	testing.expect(t, box_after > box_before, "the visual box did not grow")
	testing.expect(
		t,
		state.taa.prev_models[state.taa.prev_model_count - 1] != model_before,
		"the pop did not change the model",
	)
	testing.expect_value(t, state.taa.reset_count, before)
}
