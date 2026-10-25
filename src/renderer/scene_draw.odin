#+vet explicit-allocators
package renderer

import "core:log"

import "src:perf"
import vk "vendor:vulkan"

record_scene :: proc(
	r: ^Renderer,
	command_buffer: vk.CommandBuffer,
	image_index: u32,
	input: Render_Input,
	capture: Frame_Capture,
) -> bool {
	input := input
	r.frame_count += 1
	if int(image_index) >= len(r.target.views) {
		log.errorf("renderer: target image index %d is out of range", image_index)
		return false
	}
	box_count := len(input.boxes)
	if box_count > MAX_SCENE_BOXES {
		log.errorf("renderer: scene has %d boxes, the limit is %d", box_count, MAX_SCENE_BOXES)
		return false
	}

	if !prepare_overlay(r, input.debug_lines, input.hud) {
		log.error("renderer: overlay vertex upload failed")
		return false
	}
	if r.taa.has_prev_models && box_count != r.taa.prev_model_count {
		reset_history(r, .Scene_Change)
	}
	lights := frame_lights(r, input.lights)
	if !write_light_data(r, lights) {
		return false
	}
	input.lights = lights[:r.light_count]
	if r.taa.has_prev_sun &&
	   (r.taa.prev_light_direction != input.light_direction ||
		   r.taa.prev_sun_angular_diameter != input.sun_angular_diameter) {
		reset_history(r, .Scene_Change)
	}
	r.taa.prev_light_direction = input.light_direction
	r.taa.prev_sun_angular_diameter = input.sun_angular_diameter
	r.taa.has_prev_sun = true

	// The recorder owns the renderer-internal inputs, so one value goes to the
	// uniform, the digest, and the pass list.
	extent := target_extent_vk(r)
	// The camera reset runs before the jitter advances, because a reset puts the
	// jitter index back to zero.
	taa_note_camera(r, input.camera)
	input.width = extent.width
	input.height = extent.height
	input.jitter = taa_frame_jitter(r, extent)
	input.shadow_phase = taa_shadow_phase(r)
	r.taa.current_jitter = input.jitter
	r.taa.shadow_phase = input.shadow_phase
	input.atlas_weight = text_atlas_applied_weight(r)
	debug := renderer_debug(r)
	input.sky = debug.sky
	input.ao = debug.ao
	r.render_digest = render_digest(input)
	r.has_render_digest = true
	if !update_camera(r, input) {
		return false
	}
	if !write_object_data(r, input.boxes) {
		return false
	}

	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}
	if !check(vk.BeginCommandBuffer(command_buffer, &begin_info), "vkBeginCommandBuffer") {
		return false
	}

	reset_timing(r, command_buffer)
	write_timing_start(r, command_buffer)
	for kind in perf.PASS_ORDER {
		pass: Pass
		build_pass(r, &pass, kind, image_index, input.boxes)
		record_pass(r, command_buffer, &pass)
		write_timing(r, command_buffer, kind)
	}
	slot := 0
	for target in capture.targets {
		if !record_capture_copy(r, command_buffer, image_index, target, slot) {
			return false
		}
		slot += 1
	}
	if r.target.kind == .Swapchain {
		record_present_pass(r, command_buffer, image_index)
	}

	if !check(vk.EndCommandBuffer(command_buffer), "vkEndCommandBuffer") {
		return false
	}

	r.taa.applied_history_read = r.taa.history_read
	r.taa.history_read = (r.taa.history_read + 1) % TAA_HISTORY_IMAGES
	r.taa.history_valid = true
	r.taa.convergence_frames = min(r.taa.convergence_frames + 1, TAA_MAX_SAMPLES)
	return true
}

// The present transition is its own pass concern. The capture pass puts the
// target back in the colour-attachment layout, so this barrier has no capture
// branch.
record_present_pass :: proc(
	r: ^Renderer,
	command_buffer: vk.CommandBuffer,
	image_index: u32,
) {
	record_present_barrier(r, command_buffer, image_index)
}
