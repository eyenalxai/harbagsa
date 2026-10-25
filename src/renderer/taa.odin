#+vet explicit-allocators
package renderer

import "core:log"
import "core:math"

import vk "vendor:vulkan"

SCENE_COLOR_FORMAT :: vk.Format.R16G16B16A16_SFLOAT
VELOCITY_FORMAT :: vk.Format.R16G16B16A16_SFLOAT
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
	shadow_phase:         u32,
	convergence_frames:   int,
	reset_count:          int,
	last_reset:           History_Reset_Reason,
	debug:                Renderer_Debug,

	prev_models:              [dynamic]Mat4,
	prev_model_count:         int,
	has_prev_models:          bool,
	prev_view_projection:     Mat4,
	has_prev_view_projection: bool,

	prev_camera:     Camera,
	has_prev_camera: bool,

	prev_light_direction:      [3]f32,
	prev_sun_angular_diameter: f32,
	has_prev_sun:              bool,

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
	r.taa.debug = renderer_debug_default()
	if !check_taa_formats(r) {
		return .Create_TAA
	}
	if !create_taa_targets(r, .Create) {
		return .Create_TAA
	}
	if !create_taa_sampler(r) {
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
	destroy_taa_targets(r)
	if r.taa.prev_models != nil {
		delete(r.taa.prev_models)
	}
}

check_taa_formats :: proc(r: ^Renderer) -> bool {
	required := vk.FormatFeatureFlags {
		.COLOR_ATTACHMENT,
		.SAMPLED_IMAGE,
		.SAMPLED_IMAGE_FILTER_LINEAR,
		.TRANSFER_SRC,
	}
	formats := [4]vk.Format{SCENE_COLOR_FORMAT, VELOCITY_FORMAT, HISTORY_FORMAT, COUNT_FORMAT}
	for format in formats {
		properties: vk.FormatProperties
		vk.GetPhysicalDeviceFormatProperties(r.physical_device, format, &properties)
		if (properties.optimalTilingFeatures & required) != required {
			log.errorf("renderer: format %v lacks the TAA color, sample, filter, or transfer features", format)
			return false
		}
	}
	depth_required := vk.FormatFeatureFlags{.DEPTH_STENCIL_ATTACHMENT, .TRANSFER_SRC}
	depth_properties: vk.FormatProperties
	vk.GetPhysicalDeviceFormatProperties(r.physical_device, DEPTH_FORMAT, &depth_properties)
	if (depth_properties.optimalTilingFeatures & depth_required) != depth_required {
		log.errorf("renderer: format %v lacks the depth or transfer features", DEPTH_FORMAT)
		return false
	}
	return true
}

// Any color target failure leaves no partial TAA state behind.
@(private)
create_taa_color_target :: proc(r: ^Renderer, extent: vk.Extent2D, format: vk.Format) -> (Image, bool) {
	image, ok := create_image(
		r,
		extent.width,
		extent.height,
		format,
		{.COLOR_ATTACHMENT, .SAMPLED, .TRANSFER_SRC},
		{.COLOR},
	)
	if !ok {
		destroy_taa_targets(r)
	}
	return image, ok
}

create_taa_targets :: proc(r: ^Renderer, reason: History_Reset_Reason) -> bool {
	destroy_taa_targets(r)

	extent := vk.Extent2D{r.target.config.width, r.target.config.height}
	if extent.width == 0 || extent.height == 0 {
		log.error("renderer: cannot create TAA targets without a target extent")
		return false
	}

	for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
		depth, depth_ok := create_image(
			r,
			extent.width,
			extent.height,
			DEPTH_FORMAT,
			{.DEPTH_STENCIL_ATTACHMENT, .TRANSFER_SRC},
			{.DEPTH},
		)
		if !depth_ok {
			destroy_taa_targets(r)
			return false
		}
		r.taa.depth[i] = depth

		color, color_ok := create_taa_color_target(r, extent, SCENE_COLOR_FORMAT)
		if !color_ok {
			return false
		}
		r.taa.scene_color[i] = color

		velocity, velocity_ok := create_taa_color_target(r, extent, VELOCITY_FORMAT)
		if !velocity_ok {
			return false
		}
		r.taa.velocity[i] = velocity
	}

	for i in 0 ..< TAA_HISTORY_IMAGES {
		history, history_ok := create_taa_color_target(r, extent, HISTORY_FORMAT)
		if !history_ok {
			return false
		}
		r.taa.history[i] = history

		count, count_ok := create_taa_color_target(r, extent, COUNT_FORMAT)
		if !count_ok {
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
	r.taa.has_prev_sun = false
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
	if r.taa.debug.active {
		r.taa.debug.taa = r.taa.enabled
	}
	reset_history(r, .Toggle)
	log.infof("renderer: TAA %s", r.taa.enabled ? "on" : "off")
}

destroy_taa_targets :: proc(r: ^Renderer) {
	for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
		destroy_image(r, &r.taa.depth[i])
		destroy_image(r, &r.taa.scene_color[i])
		destroy_image(r, &r.taa.velocity[i])
	}
	for i in 0 ..< TAA_HISTORY_IMAGES {
		destroy_image(r, &r.taa.history[i])
		destroy_image(r, &r.taa.counts[i])
	}
	r.taa.history_valid = false
	r.taa.history_layouts = {.UNDEFINED, .UNDEFINED}
	r.taa.count_layouts = {.UNDEFINED, .UNDEFINED}
}

create_taa_sampler :: proc(r: ^Renderer) -> bool {
	info := vk.SamplerCreateInfo {
		sType        = .SAMPLER_CREATE_INFO,
		magFilter    = .LINEAR,
		minFilter    = .LINEAR,
		mipmapMode   = .NEAREST,
		addressModeU = .CLAMP_TO_EDGE,
		addressModeV = .CLAMP_TO_EDGE,
		addressModeW = .CLAMP_TO_EDGE,
		maxLod       = 0,
	}
	return check(vk.CreateSampler(r.device, &info, nil, &r.taa.sampler), "vkCreateSampler")
}
