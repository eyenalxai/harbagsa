#+vet explicit-allocators
package renderer

import "core:log"

import vk "vendor:vulkan"

SCENE_COLOR_FORMAT :: vk.Format.R16G16B16A16_SFLOAT
VELOCITY_FORMAT :: vk.Format.R16G16B16A16_SFLOAT
DEPTH_FORMAT :: vk.Format.D32_SFLOAT

COLOR_TARGET_FEATURES :: vk.FormatFeatureFlags {
	.COLOR_ATTACHMENT,
	.SAMPLED_IMAGE,
	.SAMPLED_IMAGE_FILTER_LINEAR,
	.TRANSFER_SRC,
}

DEPTH_SUBRESOURCE :: vk.ImageSubresourceRange {
	aspectMask = {.DEPTH},
	levelCount = 1,
	layerCount = 1,
}

// The depth, lit, and velocity attachments belong to the frame, not to TAA:
// the depth, scene, and sky passes read them with temporal filtering off.
Frame_Targets :: struct {
	depth:       [MAX_FRAMES_IN_FLIGHT]Image,
	scene_color: [MAX_FRAMES_IN_FLIGHT]Image,
	velocity:    [MAX_FRAMES_IN_FLIGHT]Image,
}

init_frame_targets :: proc(r: ^Renderer) -> Error {
	if !check_frame_target_formats(r) {
		return .Create_Frame_Targets
	}
	if !create_frame_targets(r) {
		return .Create_Frame_Targets
	}
	return .None
}

recreate_frame_targets :: proc(r: ^Renderer) -> bool {
	return create_frame_targets(r)
}

destroy_frame_targets :: proc(r: ^Renderer) {
	for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
		destroy_image(r, &r.frame_targets.depth[i])
		destroy_image(r, &r.frame_targets.scene_color[i])
		destroy_image(r, &r.frame_targets.velocity[i])
	}
}

@(private)
create_frame_targets :: proc(r: ^Renderer) -> bool {
	destroy_frame_targets(r)

	extent := target_extent_vk(r)
	if extent.width == 0 || extent.height == 0 {
		log.error("renderer: cannot create the frame targets without a target extent")
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
			destroy_frame_targets(r)
			return false
		}
		r.frame_targets.depth[i] = depth

		color, color_ok := create_color_attachment(r, extent, SCENE_COLOR_FORMAT)
		if !color_ok {
			destroy_frame_targets(r)
			return false
		}
		r.frame_targets.scene_color[i] = color

		velocity, velocity_ok := create_color_attachment(r, extent, VELOCITY_FORMAT)
		if !velocity_ok {
			destroy_frame_targets(r)
			return false
		}
		r.frame_targets.velocity[i] = velocity
	}
	return true
}

@(private)
check_frame_target_formats :: proc(r: ^Renderer) -> bool {
	formats := [2]vk.Format{SCENE_COLOR_FORMAT, VELOCITY_FORMAT}
	for format in formats {
		if !format_supports(r, format, COLOR_TARGET_FEATURES) {
			log.errorf("renderer: format %v lacks the frame color, sample, filter, or transfer features", format)
			return false
		}
	}
	depth_required := vk.FormatFeatureFlags{.DEPTH_STENCIL_ATTACHMENT, .TRANSFER_SRC}
	if !format_supports(r, DEPTH_FORMAT, depth_required) {
		log.errorf("renderer: format %v lacks the depth or transfer features", DEPTH_FORMAT)
		return false
	}
	return true
}
