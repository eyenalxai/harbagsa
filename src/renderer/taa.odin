#+vet explicit-allocators
package renderer

import "core:log"
import "core:math"

import vk "vendor:vulkan"

// The history is the only accumulated value. At the 512-sample cap a new
// sample carries weight 1/513, below one fp16 step at the shaded floor's
// linear value. Rounding then keeps the ray-count steps instead of the
// average, so the history is 32-bit while the scene and velocity stay 16-bit.
HISTORY_FORMAT :: vk.Format.R32G32B32A32_SFLOAT
COUNT_FORMAT :: vk.Format.R16_SFLOAT

TAA_TELEPORT_DISTANCE :: 2.0
TAA_TELEPORT_ANGLE :: math.PI / 4
// A still pixel keeps accumulating until this many samples. The resolve
// weights each new sample by one over the count, so a reset converges in a few
// frames while a settled image stays still.
TAA_MAX_SAMPLES :: 512

TAA_HISTORY_IMAGES :: 2
TAA_DESCRIPTOR_SETS :: MAX_FRAMES_IN_FLIGHT * TAA_HISTORY_IMAGES

TAA :: struct {
	enabled:      bool,
	jitter_index: int,

	// The values the last recorded frame used, so the renderer report names the
	// frame the state describes rather than the next one.
	applied_jitter_index: int,
	convergence_frames:   int,
	reset_count:          int,
	last_reset:           History_Reset_Reason,

	prev_models:              [dynamic]Mat4,
	prev_model_count:         int,
	has_prev_models:          bool,
	prev_view_projection:     Mat4,
	has_prev_view_projection: bool,

	prev_camera:     Camera,
	has_prev_camera: bool,

	depth:       [MAX_FRAMES_IN_FLIGHT]Image,
	scene_color: [MAX_FRAMES_IN_FLIGHT]Image,
	velocity:    [MAX_FRAMES_IN_FLIGHT]Image,
	history:     [TAA_HISTORY_IMAGES]Image,
	counts:      [TAA_HISTORY_IMAGES]Image,

	history_read:    int,
	applied_history_read: int,
	history_valid:   bool,
	history_layouts: [TAA_HISTORY_IMAGES]vk.ImageLayout,
	count_layouts:   [TAA_HISTORY_IMAGES]vk.ImageLayout,

	sampler:               vk.Sampler,
	descriptor_set_layout: vk.DescriptorSetLayout,
	descriptor_pool:       vk.DescriptorPool,
	descriptor_sets:       [TAA_DESCRIPTOR_SETS]vk.DescriptorSet,

	pipeline:        vk.Pipeline,
	pipeline_layout: vk.PipelineLayout,
	pipeline_format: vk.Format,
}

init_taa :: proc(r: ^Renderer) -> Error {
	r.taa.enabled = true
	r.taa.prev_models = make([dynamic]Mat4, 0, 0, r.allocator)
	if !check_taa_formats(r) {
		return .Create_TAA
	}
	if !create_taa_history(r, .Create) {
		return .Create_TAA
	}
	if !create_clamp_sampler(r, &r.taa.sampler) {
		return .Create_TAA
	}
	if !create_taa_descriptors(r) {
		return .Create_TAA
	}
	if !create_taa_pipeline(r) {
		return .Create_TAA
	}
	return .None
}

destroy_taa :: proc(r: ^Renderer) {
	if r.device != nil {
		destroy_pipeline_pair(r, &r.taa.pipeline, &r.taa.pipeline_layout)
		if r.taa.descriptor_pool != 0 {
			vk.DestroyDescriptorPool(r.device, r.taa.descriptor_pool, nil)
			r.taa.descriptor_pool = 0
		}
		if r.taa.descriptor_set_layout != 0 {
			vk.DestroyDescriptorSetLayout(r.device, r.taa.descriptor_set_layout, nil)
			r.taa.descriptor_set_layout = 0
		}
		if r.taa.sampler != 0 {
			vk.DestroySampler(r.device, r.taa.sampler, nil)
			r.taa.sampler = 0
		}
	}
	destroy_taa_history(r)
	if r.taa.prev_models != nil {
		delete(r.taa.prev_models)
	}
}

check_taa_formats :: proc(r: ^Renderer) -> bool {
	formats := [2]vk.Format{HISTORY_FORMAT, COUNT_FORMAT}
	for format in formats {
		if !format_supports(r, format, COLOR_TARGET_FEATURES) {
			log.errorf("renderer: format %v lacks the TAA color, sample, filter, or transfer features", format)
			return false
		}
	}
	return true
}

create_taa_history :: proc(r: ^Renderer, reason: History_Reset_Reason) -> bool {
	destroy_taa_history(r)

	extent := target_extent_vk(r)
	if extent.width == 0 || extent.height == 0 {
		log.error("renderer: cannot create TAA history without a target extent")
		return false
	}

	for i in 0 ..< TAA_HISTORY_IMAGES {
		history, history_ok := create_color_attachment(r, extent, HISTORY_FORMAT)
		if !history_ok {
			destroy_taa_history(r)
			return false
		}
		r.taa.history[i] = history

		count, count_ok := create_color_attachment(r, extent, COUNT_FORMAT)
		if !count_ok {
			destroy_taa_history(r)
			return false
		}
		r.taa.counts[i] = count
	}

	reset_history(r, reason)
	r.taa.history_read = 0
	r.taa.history_layouts = {.UNDEFINED, .UNDEFINED}
	r.taa.count_layouts = {.UNDEFINED, .UNDEFINED}
	return true
}

reset_history :: proc(r: ^Renderer, reason: History_Reset_Reason) {
	r.taa.history_valid = false
	r.taa.jitter_index = 0
	r.taa.has_prev_view_projection = false
	r.taa.prev_model_count = 0
	r.taa.has_prev_models = false
	r.taa.applied_history_read = 0
	r.taa.convergence_frames = 0
	r.taa.reset_count += 1
	r.taa.last_reset = reason
}

taa_note_camera :: proc(r: ^Renderer, camera: Camera) {
	if r.taa.has_prev_camera {
		previous := r.taa.prev_camera
		dx := camera.position.x - previous.position.x
		dy := camera.position.y - previous.position.y
		dz := camera.position.z - previous.position.z
		moved := math.sqrt(dx * dx + dy * dy + dz * dz)

		yaw_delta := math.abs(camera.yaw - previous.yaw)
		if yaw_delta > math.PI {
			yaw_delta = 2 * math.PI - yaw_delta
		}
		turned := yaw_delta > TAA_TELEPORT_ANGLE ||
			math.abs(camera.pitch - previous.pitch) > TAA_TELEPORT_ANGLE
		if moved > TAA_TELEPORT_DISTANCE || turned {
			reset_history(r, .Teleport)
		}
	}
	r.taa.prev_camera = camera
	r.taa.has_prev_camera = true
}

toggle_taa :: proc(r: ^Renderer) {
	r.taa.enabled = !r.taa.enabled
	if r.debug.active {
		r.debug.taa = r.taa.enabled
	}
	reset_history(r, .Toggle)
	log.infof("renderer: TAA %s", r.taa.enabled ? "on" : "off")
}

destroy_taa_history :: proc(r: ^Renderer) {
	for i in 0 ..< TAA_HISTORY_IMAGES {
		destroy_image(r, &r.taa.history[i])
		destroy_image(r, &r.taa.counts[i])
	}
	r.taa.history_valid = false
	r.taa.history_layouts = {.UNDEFINED, .UNDEFINED}
	r.taa.count_layouts = {.UNDEFINED, .UNDEFINED}
}

