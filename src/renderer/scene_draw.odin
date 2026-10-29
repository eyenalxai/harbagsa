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

	if !prepare_overlay(r, input.debug_lines, input.hud) {
		log.error("renderer: overlay vertex upload failed")
		return false
	}
	if r.taa.has_prev_models && box_count != r.taa.prev_model_count {
		reset_history(r, .Scene_Change)
	}
	lights := frame_lights(r, input.lights)
	if !ensure_scene_capacity(r, box_count, len(lights)) {
		return false
	}
	if !ensure_acceleration_capacity(r, box_count) {
		return false
	}
	if !write_light_data(r, lights) {
		return false
	}
	input.lights = lights[:r.light_count]
	// The recorder owns the renderer-internal inputs, so one value goes to the
	// uniform, the digest, and the pass list.
	extent := target_extent_vk(r)
	// The camera reset runs before the jitter advances, because a reset puts the
	// jitter index back to zero.
	taa_note_camera(r, input.camera)
	input.width = extent.width
	input.height = extent.height
	input.jitter = taa_frame_jitter(r, extent)
	input.atlas_weight = text_atlas_applied_weight(r)
	debug := renderer_debug(r)
	input.clip_height = debug.clip_height
	input.lightmap = debug.lightmap
	input.probe = debug.probe
	if r.debug.active {
		input.light_shadows = debug.light_shadows
	}
	update_bake(r, bake_key(r, input.bake_static))
	input.bake_key = r.bake.current_key
	input.bake_status = r.bake.status
	r.render_digest = render_digest(input)
	r.has_render_digest = true
	if !update_camera(r, input) {
		return false
	}
	if !write_object_data(r, input.boxes, input.box_slots, input.lightmap, input.probe) {
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
	// Term views redraw the scene, so the target copies happen first: a group
	// that asks for scene_color and a view keeps the beauty scene color.
	for view in capture.views {
		if !record_scene_view(r, command_buffer, capture, view, image_index, input.boxes) {
			return false
		}
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
