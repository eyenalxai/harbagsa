#+vet explicit-allocators
package renderer

import "core:log"

import vk "vendor:vulkan"

// One color image per term view. The images are allocated on the first capture
// that asks for a view and reused until the target extent changes, so the game
// binary that never captures owns none of them.
View_Targets :: struct {
	images:  [Capture_View]Image,
	extent:  vk.Extent2D,
	created: bool,
}

ensure_view_targets :: proc(r: ^Renderer) -> bool {
	extent := target_extent_vk(r)
	if r.view_targets.created && r.view_targets.extent == extent {
		return true
	}
	if !check(vk.DeviceWaitIdle(r.device), "vkDeviceWaitIdle") {
		return false
	}
	destroy_view_targets(r)
	for view in Capture_View {
		if !capture_view_is_term(view) {
			continue
		}
		image, ok := create_color_attachment(r, extent, r.target.config.format)
		if !ok {
			log.errorf("renderer: could not create the %s view image", capture_view_name(view))
			destroy_view_targets(r)
			return false
		}
		r.view_targets.images[view] = image
	}
	r.view_targets.extent = extent
	r.view_targets.created = true
	return true
}

destroy_view_targets :: proc(r: ^Renderer) {
	for view in Capture_View {
		if !capture_view_is_term(view) {
			continue
		}
		destroy_image(r, &r.view_targets.images[view])
	}
	r.view_targets.created = false
}
