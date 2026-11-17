#+vet explicit-allocators
package renderer

import "core:log"

import vk "vendor:vulkan"

// recreate_target rebuilds the surface the frame draws into. The platform event
// that marks the target dirty only names the new size, so the recreation asks
// the adapter for it.
recreate_target :: proc(r: ^Renderer) -> Frame_Status {
	width, height := r.platform.pixel_size(r.platform.user)
	if width == 0 || height == 0 {
		r.target.dirty = true
		return .Skipped
	}
	#partial switch r.target.kind {
	case .Swapchain:
		return recreate_swapchain(r)
	case .Offscreen:
		return recreate_offscreen(r, width, height)
	}
	return .Fatal
}

@(private)
recreate_offscreen :: proc(r: ^Renderer, width, height: u32) -> Frame_Status {
	old_extent := vk.Extent2D{r.target.config.width, r.target.config.height}
	old_format := r.target.config.format

	if !check(vk.DeviceWaitIdle(r.device), "vkDeviceWaitIdle") {
		return .Fatal
	}
	destroy_image(r, &r.target.color)
	delete_target_slices(r)
	destroy_readback(r)
	if init_offscreen_target(r, width, height) != .None {
		return .Fatal
	}
	return recreate_attachments(r, old_extent, old_format)
}

// recreate_attachments rebinds everything that holds the target's extent. The
// UI shim reattaches last, so its renderer sees the new format and reuses the
// text atlas it filled.
@(private)
recreate_attachments :: proc(
	r: ^Renderer,
	old_extent: vk.Extent2D,
	old_format: vk.Format,
) -> Frame_Status {
	if r.target.config.width != old_extent.width || r.target.config.height != old_extent.height {
		if !recreate_frame_targets(r) {
			log.error("renderer: could not recreate the frame targets")
			return .Fatal
		}
		if !create_taa_history(r, .Extent) {
			log.error("renderer: could not recreate the TAA history")
			return .Fatal
		}
		if !write_taa_descriptors(r) {
			log.error("renderer: could not rebind the TAA targets")
			return .Fatal
		}
	} else if r.target.config.format != old_format {
		reset_history(r, .Extent)
	}

	if r.taa.pipeline_format != r.target.config.format {
		destroy_taa_pipelines(r)
		if !create_taa_pipeline(r) {
			return .Fatal
		}
	}
	if r.overlay.pipeline_format != r.target.config.format {
		destroy_overlay_pipelines(r)
		if !create_overlay_pipelines(r) {
			return .Fatal
		}
	}
	if !ui_attach_target(r) {
		return .Fatal
	}
	r.target.dirty = false
	return .Ok
}
